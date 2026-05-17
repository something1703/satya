import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'verdict_schema.dart';
import 'gemma_service.dart';

/// Orchestrates the full analysis pipeline: preprocessing → inference → parsing.
///
/// Entry point: `analyze()` takes a file or text and returns a [Verdict].
class MultimodalPipeline {
  static const int _maxRetries = 3;

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
      final prompt = await _buildPrompt(
        filePath: filePath,
        text: text,
        contentType: contentType,
        contentHash: contentHash,
      );

      // ── Step 3: Inference ─────────────────────────────────────────
      onStepUpdate?.call(3);
      onStatusUpdate?.call('Reasoning with Gemma 4...');

      Verdict? verdict;
      int attempt = 0;

      while (verdict == null && attempt < _maxRetries) {
        attempt++;
        final rawOutput = await GemmaService.instance.generateText(prompt);
        debugPrint('[Pipeline] Raw model output (attempt $attempt): $rawOutput');

        // Try to extract JSON from the model output
        verdict = _parseVerdict(rawOutput, contentHash);

        if (verdict == null && attempt < _maxRetries) {
          onStatusUpdate?.call('Retrying analysis (attempt ${attempt + 1})...');
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
      return Verdict.inconclusive(reason: 'Analysis error: ${e.toString()}');
    }
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

  Future<String> _buildPrompt({
    String? filePath,
    String? text,
    required String contentType,
    required String contentHash,
  }) async {
    // Load the system prompt
    final systemPrompt = await _loadSystemPrompt();

    // Build the user message based on content type
    String userContent;

    switch (contentType) {
      case 'image':
        // For now, describe what we're sending. In future, we pass the actual
        // image bytes via Gemma's multimodal API.
        userContent = 'I am sharing an image for analysis. '
            'Content hash: $contentHash. '
            'Please analyze this image for signs of manipulation, '
            'synthetic generation, or misleading framing.';
        break;

      case 'video':
        userContent = 'I am sharing a video for analysis. '
            'Content hash: $contentHash. '
            'Please analyze this video for signs of deepfake manipulation, '
            'synthetic generation, or misleading editing.';
        break;

      case 'audio':
        userContent = 'I am sharing an audio clip for analysis. '
            'Content hash: $contentHash. '
            'Please analyze this audio for signs of voice cloning, '
            'synthetic speech, or audio manipulation.';
        break;

      case 'text':
      default:
        userContent = 'I am sharing the following text/claim for analysis. '
            'Content hash: $contentHash.\n\n'
            '---\n$text\n---\n\n'
            'Please analyze this text for signs of misinformation, '
            'misleading framing, or fabricated claims.';
        break;
    }

    // Combine into the full prompt with function schema
    return '''$systemPrompt

## Available Function

$verdictJsonSchema

## Content to Analyze

$userContent

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
      debugPrint('[Pipeline] JSON parse error: $e');
      return null;
    }
  }

  /// Extract a JSON object from potentially messy model output.
  ///
  /// Models sometimes wrap JSON in markdown code blocks or add commentary.
  /// This method tries to find the first valid JSON object in the string.
  String? _extractJson(String text) {
    // Strategy 1: Look for a JSON code block
    final codeBlockRegex = RegExp(r'```(?:json)?\s*(\{[\s\S]*?\})\s*```');
    final codeBlockMatch = codeBlockRegex.firstMatch(text);
    if (codeBlockMatch != null) {
      return codeBlockMatch.group(1);
    }

    // Strategy 2: Find the outermost { ... } pair
    final firstBrace = text.indexOf('{');
    if (firstBrace == -1) return null;

    int depth = 0;
    for (int i = firstBrace; i < text.length; i++) {
      if (text[i] == '{') depth++;
      if (text[i] == '}') depth--;
      if (depth == 0) {
        return text.substring(firstBrace, i + 1);
      }
    }
    return null;
  }
}
