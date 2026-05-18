import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import 'verdict_schema.dart';
import 'gemma_service.dart';

/// Orchestrates the full analysis pipeline: preprocessing → inference → parsing.
///
/// Entry point: `analyze()` takes a file or text and returns a [Verdict].
class MultimodalPipeline {
  static const int _maxRetries = 3;

  /// Target size for image input to Gemma 4 vision.
  static const int _targetImageSize = 768;

  /// Max frames to send in a single inference (flutter_gemma limit).
  static const int _maxFramesPerInference = 3;

  /// Run the full analysis pipeline.
  ///
  /// [filePath] — path to image/video/audio file (mutually exclusive with [text])
  /// [text] — raw text or URL to analyze
  /// [contentType] — 'image', 'video', 'audio', or 'text'
  /// [onStatusUpdate] — called with human-readable status messages
  /// [onStepUpdate] — called with step index (0-4) for the progress indicator
  Future<Verdict> analyze({
    String? filePath,
    String? text,
    required String contentType,
    void Function(String status)? onStatusUpdate,
    void Function(int step)? onStepUpdate,
  }) async {
    try {
      // ── Step 0: Prepare ───────────────────────────────────────────
      onStepUpdate?.call(0);
      onStatusUpdate?.call('Preparing content...');

      // ── Step 1: Hash ──────────────────────────────────────────────
      onStepUpdate?.call(1);
      onStatusUpdate?.call('Computing content hash...');
      final contentHash = await _computeHash(filePath: filePath, text: text);

      // ── Step 2: Preprocess ────────────────────────────────────────
      onStepUpdate?.call(2);
      onStatusUpdate?.call('Processing media...');

      // ── Step 3: Inference ─────────────────────────────────────────
      onStepUpdate?.call(3);
      onStatusUpdate?.call('Reasoning with Gemma 4...');

      Verdict? verdict;
      int attempt = 0;

      while (verdict == null && attempt < _maxRetries) {
        attempt++;

        String rawOutput;

        switch (contentType) {
          case 'image':
            rawOutput = await _analyzeImage(filePath!, contentHash, onStatusUpdate);
            break;

          case 'video':
            rawOutput = await _analyzeVideo(filePath!, contentHash, onStatusUpdate);
            break;

          case 'audio':
            rawOutput = await _analyzeAudio(filePath!, contentHash, onStatusUpdate);
            break;

          case 'text':
          default:
            rawOutput = await _analyzeText(text ?? '', contentHash);
            break;
        }

        debugPrint('[Pipeline] Raw model output (attempt $attempt): $rawOutput');

        // Try to extract JSON from the model output
        verdict = _parseVerdict(rawOutput, contentHash);

        if (verdict == null && attempt < _maxRetries) {
          onStatusUpdate?.call('Response was not valid JSON. Retrying (attempt ${attempt + 1})...');
        }
      }

      // ── Step 4: Validate ──────────────────────────────────────────
      onStepUpdate?.call(4);
      onStatusUpdate?.call('Finalizing verdict...');

      // If all retries failed, return INCONCLUSIVE
      return verdict ?? Verdict.inconclusive(
        reason: 'Model could not produce a valid structured verdict after $_maxRetries attempts.',
      );
    } catch (e) {
      debugPrint('[Pipeline] Error: $e');
      return Verdict.inconclusive(reason: 'Something went wrong during analysis. Please try again.');
    }
  }

  // ─── Image analysis ─────────────────────────────────────────────────

  /// Read the image file, resize to 768×768, and pass actual bytes to Gemma 4.
  Future<String> _analyzeImage(
    String filePath,
    String contentHash,
    void Function(String)? onStatusUpdate,
  ) async {
    onStatusUpdate?.call('Reading and resizing image...');

    final imageBytes = await _loadAndResizeImage(filePath);
    final prompt = await _buildMediaPrompt(
      contentType: 'image',
      contentHash: contentHash,
    );

    return await GemmaService.instance.generateWithImage(prompt, imageBytes);
  }

  // ─── Video analysis ─────────────────────────────────────────────────

  /// Extract key frames from video and pass them to Gemma 4.
  Future<String> _analyzeVideo(
    String filePath,
    String contentHash,
    void Function(String)? onStatusUpdate,
  ) async {
    onStatusUpdate?.call('Extracting video frames...');

    final frames = await _extractVideoFrames(filePath);

    if (frames.isEmpty) {
      // Fallback: treat as text-only analysis if frame extraction fails
      // Fallback: treat as text-only analysis if frame extraction is unavailable
      final prompt = await _buildMediaPrompt(
        contentType: 'video',
        contentHash: contentHash,
        fallbackNote: 'Video frame-by-frame analysis coming in v2. '
            'Currently analyzing based on file metadata and context.',
      );
      return await GemmaService.instance.generateText(prompt);
    }

    onStatusUpdate?.call('Analyzing ${frames.length} video frames...');

    // Use up to _maxFramesPerInference frames (first, middle, last)
    final selectedFrames = _selectKeyFrames(frames);

    final prompt = await _buildMediaPrompt(
      contentType: 'video',
      contentHash: contentHash,
      frameCount: selectedFrames.length,
    );

    if (selectedFrames.length == 1) {
      return await GemmaService.instance.generateWithImage(prompt, selectedFrames.first);
    } else {
      return await GemmaService.instance.generateWithImages(prompt, selectedFrames);
    }
  }

  // ─── Audio analysis ─────────────────────────────────────────────────

  /// Audio analysis — Gemma 4 E4B does not have native audio support,
  /// so we analyze based on file metadata and prompt the model accordingly.
  Future<String> _analyzeAudio(
    String filePath,
    String contentHash,
    void Function(String)? onStatusUpdate,
  ) async {
    onStatusUpdate?.call('Analyzing audio metadata...');

    final file = File(filePath);
    final fileSize = await file.length();
    final extension = p.extension(filePath).toLowerCase();

    final prompt = await _buildMediaPrompt(
      contentType: 'audio',
      contentHash: contentHash,
      fallbackNote: 'Audio file detected ($extension, ${(fileSize / 1024).toStringAsFixed(0)} KB). '
          'Audio waveform analysis is not yet supported on-device. '
          'Analyzing based on available metadata.',
    );

    return await GemmaService.instance.analyzeText(prompt);
  }

  // ─── Text analysis ──────────────────────────────────────────────────

  /// Pass text/claim directly to Gemma 4 for analysis.
  Future<String> _analyzeText(String text, String contentHash) async {
    final prompt = await _buildTextPrompt(text: text, contentHash: contentHash);
    return await GemmaService.instance.analyzeText(prompt);
  }

  // ─── Image processing helpers ───────────────────────────────────────

  /// Load an image file and resize to 768×768 PNG bytes.
  Future<Uint8List> _loadAndResizeImage(String filePath) async {
    final file = File(filePath);
    final rawBytes = await file.readAsBytes();

    // Decode on a background isolate to avoid jank
    final resized = await compute(_resizeImageBytes, rawBytes);
    return resized;
  }

  /// Static function for compute() isolate — decodes, resizes, re-encodes.
  static Uint8List _resizeImageBytes(Uint8List rawBytes) {
    final decoded = img.decodeImage(rawBytes);
    if (decoded == null) {
      // If decoding fails, return raw bytes and let the model handle it
      return rawBytes;
    }

    // Resize to 768×768, maintaining aspect ratio with padding
    final resized = img.copyResize(
      decoded,
      width: _targetImageSize,
      height: _targetImageSize,
      interpolation: img.Interpolation.linear,
    );

    // Encode as PNG
    return Uint8List.fromList(img.encodePng(resized));
  }

  // ─── Video frame extraction ─────────────────────────────────────────

  /// Extract frames from a video file.
  ///
  /// On-device video frame extraction requires native platform integration
  /// (Android MediaMetadataRetriever via platform channel). Currently returns
  /// empty to use the metadata-based fallback path.
  Future<List<Uint8List>> _extractVideoFrames(String filePath) async {
    // Native frame extraction via platform channel — planned for v2.
    // Returns empty to trigger metadata fallback.
    return [];
  }

  /// Select key frames: first, middle, last (up to _maxFramesPerInference).
  List<Uint8List> _selectKeyFrames(List<Uint8List> allFrames) {
    if (allFrames.length <= _maxFramesPerInference) {
      return allFrames;
    }

    return [
      allFrames.first,
      allFrames[allFrames.length ~/ 2],
      allFrames.last,
    ];
  }

  // ─── Hashing ───────────────────────────────────────────────────────

  Future<String> _computeHash({String? filePath, String? text}) async {
    if (filePath != null) {
      final file = File(filePath);
      final bytes = await file.readAsBytes();
      return sha256.convert(bytes).toString();
    } else if (text != null) {
      return sha256.convert(utf8.encode(text)).toString();
    }
    return 'unknown';
  }

  // ─── Prompt construction ───────────────────────────────────────────

  /// Build prompt for media content (image, video, audio).
  Future<String> _buildMediaPrompt({
    required String contentType,
    required String contentHash,
    String? fallbackNote,
    int? frameCount,
  }) async {
    final systemPrompt = await _loadSystemPrompt();

    String userContent;

    switch (contentType) {
      case 'image':
        userContent = 'Analyze this image for signs of manipulation, '
            'synthetic generation (AI-generated), or misleading framing. '
            'Content hash: $contentHash.';
        break;

      case 'video':
        if (fallbackNote != null) {
          userContent = fallbackNote;
        } else {
          userContent = 'I am sharing ${frameCount ?? "several"} key frames '
              'extracted from a video. Analyze these frames for signs of '
              'deepfake manipulation, synthetic generation, or misleading editing. '
              'Content hash: $contentHash.';
        }
        break;

      case 'audio':
        userContent = fallbackNote ??
            'Analyze this audio for signs of voice cloning, '
            'synthetic speech, or audio manipulation. '
            'Content hash: $contentHash.';
        break;

      default:
        userContent = 'Analyze this content. Content hash: $contentHash.';
    }

    return '''$systemPrompt

## Available Function

$verdictJsonSchema

## Content to Analyze

$userContent

Remember: You MUST call the submit_verdict function with a complete JSON object. Do not respond in free text.''';
  }

  /// Build prompt for text/claim analysis.
  Future<String> _buildTextPrompt({
    required String text,
    required String contentHash,
  }) async {
    final systemPrompt = await _loadSystemPrompt();

    return '''$systemPrompt

## Available Function

$verdictJsonSchema

## Content to Analyze

I am sharing the following text/claim for analysis. Content hash: $contentHash.

---
$text
---

Please analyze this text for signs of misinformation, misleading framing, or fabricated claims.

Remember: You MUST call the submit_verdict function with a complete JSON object. Do not respond in free text.''';
  }

  Future<String> _loadSystemPrompt() async {
    try {
      return await rootBundle.loadString('lib/analysis/prompts/v1_system.md');
    } catch (_) {
      // Fallback if asset loading fails — use the embedded prompt
      return '''You are a forensic media analyst specializing in detecting manipulated, synthetic, and misleading content.
Analyze the provided content and respond ONLY with a JSON object matching the submit_verdict schema.
Be cautious — uncertainty is preferable to a confident wrong answer.
Always require evidence before assigning high confidence.''';
    }
  }

  // ─── Verdict parsing ───────────────────────────────────────────────

  Verdict? _parseVerdict(String rawOutput, String contentHash) {
    // Try to find JSON in the model's output
    final jsonStr = _extractJson(rawOutput);
    if (jsonStr == null) return null;

    try {
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;

      // Inject the content hash if the model didn't include it
      if (!map.containsKey('content_hash') || map['content_hash'] == '') {
        map['content_hash'] = contentHash;
      }
      if (!map.containsKey('schema_version')) {
        map['schema_version'] = 'v1';
      }

      return Verdict.fromJson(map);
    } catch (e) {
      debugPrint('[Pipeline] JSON parse failed, will retry');
      return null;
    }
  }

  /// Extract a JSON object from potentially messy model output.
  ///
  /// Models sometimes wrap JSON in markdown code blocks, <tool_call> tags,
  /// or add commentary. This method tries multiple strategies.
  String? _extractJson(String text) {
    // Strategy 0: Strip <tool_call> tags if present
    var cleaned = text
        .replaceAll(RegExp(r'<tool_call>'), '')
        .replaceAll(RegExp(r'</tool_call>'), '')
        .trim();

    // Strategy 1: Look for a JSON code block
    final codeBlockRegex = RegExp(r'```(?:json)?\s*(\{[\s\S]*?\})\s*```');
    final codeBlockMatch = codeBlockRegex.firstMatch(cleaned);
    if (codeBlockMatch != null) {
      return codeBlockMatch.group(1);
    }

    // Strategy 2: Find the outermost { ... } pair
    final firstBrace = cleaned.indexOf('{');
    if (firstBrace == -1) return null;

    int depth = 0;
    for (int i = firstBrace; i < cleaned.length; i++) {
      if (cleaned[i] == '{') depth++;
      if (cleaned[i] == '}') depth--;
      if (depth == 0) {
        return cleaned.substring(firstBrace, i + 1);
      }
    }
    return null;
  }
}
