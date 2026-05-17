import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:path_provider/path_provider.dart';
import '../config/app_config.dart';

/// Manages the Gemma 4 model lifecycle: installation, initialization,
/// and inference. This is the single point of contact with flutter_gemma.
class GemmaService {
  GemmaService._();
  static final GemmaService instance = GemmaService._();

  /// The active inference model instance. Type is dynamic because
  /// flutter_gemma's internal type changes between versions.
  dynamic _model;
  bool _isInstalled = false;

  /// Whether the model file has been downloaded and is ready for inference.
  bool get isInstalled => _isInstalled;

  /// Whether a model instance is currently loaded and ready to use.
  bool get isReady => _model != null;

  // ─── Model filename ──────────────────────────────────────────────────

  /// Extracts the filename from the model URL for isModelInstalled checks.
  static String get _modelFileName {
    final uri = Uri.parse(AppConfig.modelUrl);
    return uri.pathSegments.last; // "gemma-4-E4B-it.litertlm"
  }

  // ─── Installation (first launch) ─────────────────────────────────────

  /// Check whether the model has already been installed on-device.
  Future<bool> checkInstalled() async {
    _isInstalled = await FlutterGemma.isModelInstalled(_modelFileName);
    return _isInstalled;
  }

  /// Download and install the model from HuggingFace.
  ///
  /// [onProgress] fires with download percentage (0–100 int).
  /// [hfToken] is the HuggingFace access token for gated models.
  Future<void> installModel({
    required String hfToken,
    void Function(int progress)? onProgress,
  }) async {
    await FlutterGemma.installModel(
      modelType: ModelType.gemma4,
      fileType: ModelFileType.litertlm, // tells plugin to use LiteRtLmFfiClient
    )
        .fromNetwork(
          AppConfig.modelUrl,
          token: hfToken,
        )
        .withProgress((progress) {
          if (onProgress != null) {
            onProgress(progress);
          }
        })
        .install();

    _isInstalled = true;
  }

  // ─── Initialization ──────────────────────────────────────────────────

  /// Load the installed model into memory, ready for inference.
  ///
  /// The model file is already on disk from the download step. We re-register
  /// it using fromFile() + ModelFileType.litertlm so the active spec points
  /// flutter_gemma to LiteRtLmFfiClient (Dart FFI) instead of EngineFactory.
  /// install() is idempotent — it skips re-downloading and just sets the spec.
  Future<void> initialize() async {
    if (_model != null) return; // already loaded

    // Re-register using the local file path and the correct file type.
    // This is idempotent — no re-download happens, just updates the active spec.
    final appDir = await _getModelDirectory();
    final modelPath = '$appDir/$_modelFileName';

    await FlutterGemma.installModel(
      modelType: ModelType.gemma4,
      fileType: ModelFileType.litertlm,
    ).fromFile(modelPath).install();

    _model = await FlutterGemma.getActiveModel(
      maxTokens: AppConfig.maxTokens,
      preferredBackend: PreferredBackend.cpu, // Switched to CPU to prevent GPU Out-of-Memory crashes
      supportImage: true, // enable multimodal — needed for Phase 2
    );

    debugPrint('[GemmaService] Model loaded: $modelPath');
  }

  /// Returns the directory where flutter_gemma stores downloaded models.
  Future<String> _getModelDirectory() async {
    // flutter_gemma saves models to app_flutter inside the app's data directory.
    // On Android: /data/user/0/<package>/app_flutter/
    final dir = await getApplicationDocumentsDirectory();
    return dir.path;
  }

  // ─── Inference ───────────────────────────────────────────────────────

  /// Send a text prompt and get a streamed response.
  ///
  /// Returns a stream of token strings as they arrive from the model.
  /// Uses generateChatResponseAsync() which returns TextResponse/etc.
  Stream<String> generateTextStream(String prompt) async* {
    if (_model == null) {
      throw StateError('GemmaService not initialized. Call initialize() first.');
    }

    final chat = await _model!.createChat();

    await chat.addQueryChunk(Message.text(
      text: prompt,
      isUser: true,
    ));

    await for (final response in chat.generateChatResponseAsync()) {
      if (response is TextResponse) {
        yield response.token;
      }
    }
  }

  /// Send a text prompt and get the complete response at once.
  Future<String> generateText(String prompt) async {
    if (_model == null) {
      throw StateError('GemmaService not initialized. Call initialize() first.');
    }

    final chat = await _model!.createChat();

    await chat.addQueryChunk(Message.text(
      text: prompt,
      isUser: true,
    ));

    final response = await chat.generateChatResponse();
    return response ?? '';
  }

  /// Send a text prompt with a single image and get the complete response.
  Future<String> generateWithImage(String prompt, Uint8List imageBytes) async {
    if (_model == null) {
      throw StateError('GemmaService not initialized. Call initialize() first.');
    }

    final chat = await _model!.createChat(supportImage: true);

    await chat.addQueryChunk(Message.withImage(
      text: prompt,
      imageBytes: imageBytes,
      isUser: true,
    ));

    final response = await chat.generateChatResponse();
    return response ?? '';
  }

  /// Send a text prompt with multiple images and get the complete response.
  Future<String> generateWithImages(String prompt, List<Uint8List> images) async {
    if (_model == null) {
      throw StateError('GemmaService not initialized. Call initialize() first.');
    }

    final chat = await _model!.createChat(supportImage: true);

    await chat.addQueryChunk(Message.withImages(
      text: prompt,
      imageBytes: images,
      isUser: true,
    ));

    final response = await chat.generateChatResponse();
    return response ?? '';
  }

  // ─── Cleanup ─────────────────────────────────────────────────────────

  /// Release model resources. Call when the app is being disposed.
  Future<void> dispose() async {
    await _model?.close();
    _model = null;
  }
}
