/// App-wide constants and configuration for SATYA.
///
/// All hardcoded values live here. No magic strings in the codebase.
class AppConfig {
  AppConfig._();

  // ─── Model ───────────────────────────────────────────────────────────
  /// HuggingFace download URL for Gemma 4 E4B in LiteRT-LM format (3.66 GB).
  static const String modelUrl =
      'https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm/resolve/main/gemma-4-E4B-it.litertlm';

  /// Model display name shown to users during download.
  static const String modelDisplayName = 'Gemma 4 E4B';

  /// Maximum tokens for inference output.
  static const int maxTokens = 1024; // raised to 4096 in Phase 2

  // ─── Verdict cache (Phase 3) ─────────────────────────────────────────
  /// Minimum number of agreeing verdicts for consensus.
  static const int consensusThreshold = 3;

  /// Firestore collection names.
  static const String verdictsCollection = 'verdicts';
  static const String publicKeysCollection = 'public_keys';

  // ─── App metadata ────────────────────────────────────────────────────
  static const String appName = 'SATYA';
  static const String appTagline = 'On-Device Truth Detection';
  static const String appVersion = '1.0.0';
  static const String schemaVersion = 'v1';
}
