// Phase 2: Verdict data model and JSON schema enforcement
// See PHASE_2_CORE_ENGINE.md Section 4 for the full schema spec.

import 'dart:convert';

// ─── Enums ─────────────────────────────────────────────────────────────

/// The model's overall assessment of the content.
enum OverallVerdict {
  likelyAuthentic,
  inconclusive,
  likelyManipulated,
  likelySynthetic;

  String get label {
    switch (this) {
      case OverallVerdict.likelyAuthentic:
        return 'LIKELY_AUTHENTIC';
      case OverallVerdict.inconclusive:
        return 'INCONCLUSIVE';
      case OverallVerdict.likelyManipulated:
        return 'LIKELY_MANIPULATED';
      case OverallVerdict.likelySynthetic:
        return 'LIKELY_SYNTHETIC';
    }
  }

  /// Human-readable display text for the UI.
  String get displayLabel {
    switch (this) {
      case OverallVerdict.likelyAuthentic:
        return 'Likely Authentic';
      case OverallVerdict.inconclusive:
        return 'Inconclusive';
      case OverallVerdict.likelyManipulated:
        return 'Likely Manipulated';
      case OverallVerdict.likelySynthetic:
        return 'Likely Synthetic';
    }
  }

  static OverallVerdict fromString(String value) {
    switch (value.toUpperCase()) {
      case 'LIKELY_AUTHENTIC':
        return OverallVerdict.likelyAuthentic;
      case 'INCONCLUSIVE':
        return OverallVerdict.inconclusive;
      case 'LIKELY_MANIPULATED':
        return OverallVerdict.likelyManipulated;
      case 'LIKELY_SYNTHETIC':
        return OverallVerdict.likelySynthetic;
      default:
        return OverallVerdict.inconclusive; // safe default
    }
  }
}

/// Actionable recommendation for the user.
enum Recommendation {
  safeToForward,
  verifyBeforeForwarding,
  doNotForward;

  String get label {
    switch (this) {
      case Recommendation.safeToForward:
        return 'SAFE_TO_FORWARD';
      case Recommendation.verifyBeforeForwarding:
        return 'VERIFY_BEFORE_FORWARDING';
      case Recommendation.doNotForward:
        return 'DO_NOT_FORWARD';
    }
  }

  /// Human-readable display text for the UI.
  String get displayLabel {
    switch (this) {
      case Recommendation.safeToForward:
        return 'Safe to forward';
      case Recommendation.verifyBeforeForwarding:
        return 'Verify before forwarding';
      case Recommendation.doNotForward:
        return 'Do not forward';
    }
  }

  static Recommendation fromString(String value) {
    switch (value.toUpperCase()) {
      case 'SAFE_TO_FORWARD':
        return Recommendation.safeToForward;
      case 'VERIFY_BEFORE_FORWARDING':
        return Recommendation.verifyBeforeForwarding;
      case 'DO_NOT_FORWARD':
        return Recommendation.doNotForward;
      default:
        return Recommendation.verifyBeforeForwarding; // safe default
    }
  }
}

// ─── Data classes ──────────────────────────────────────────────────────

/// Individual category confidence score.
class CategoryScore {
  final String category;
  final double confidence;

  const CategoryScore({
    required this.category,
    required this.confidence,
  });

  factory CategoryScore.fromJson(Map<String, dynamic> json) {
    return CategoryScore(
      category: json['category'] as String? ?? 'unknown',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() => {
        'category': category,
        'confidence': confidence,
      };
}

/// A piece of evidence the model found to support its verdict.
class Evidence {
  final String type;
  final String description;
  final String location;

  const Evidence({
    required this.type,
    required this.description,
    required this.location,
  });

  factory Evidence.fromJson(Map<String, dynamic> json) {
    return Evidence(
      type: json['type'] as String? ?? 'unknown',
      description: json['description'] as String? ?? '',
      location: json['location'] as String? ?? 'N/A',
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type,
        'description': description,
        'location': location,
      };
}

/// The complete verdict returned by the Gemma 4 analysis pipeline.
///
/// Matches the schema defined in PHASE_2_CORE_ENGINE.md Section 4.
class Verdict {
  final String schemaVersion;
  final String contentHash;
  final OverallVerdict overallVerdict;
  final double overallConfidence;
  final List<CategoryScore> categoryScores;
  final List<Evidence> evidence;
  final Recommendation recommendation;
  final String explanationShort;
  final String explanationDetailed;
  final DateTime analyzedAt;

  const Verdict({
    required this.schemaVersion,
    required this.contentHash,
    required this.overallVerdict,
    required this.overallConfidence,
    required this.categoryScores,
    required this.evidence,
    required this.recommendation,
    required this.explanationShort,
    required this.explanationDetailed,
    required this.analyzedAt,
  });

  /// Parse a verdict from the model's JSON function-call output.
  factory Verdict.fromJson(Map<String, dynamic> json) {
    return Verdict(
      schemaVersion: json['schema_version'] as String? ?? 'v1',
      contentHash: json['content_hash'] as String? ?? '',
      overallVerdict: OverallVerdict.fromString(
        json['overall_verdict'] as String? ?? 'INCONCLUSIVE',
      ),
      overallConfidence:
          (json['overall_confidence'] as num?)?.toDouble() ?? 0.0,
      categoryScores: (json['category_scores'] as List<dynamic>?)
              ?.map((e) => CategoryScore.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      evidence: (json['evidence'] as List<dynamic>?)
              ?.map((e) => Evidence.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      recommendation: Recommendation.fromString(
        json['recommendation'] as String? ?? 'VERIFY_BEFORE_FORWARDING',
      ),
      explanationShort: json['explanation_short'] as String? ?? '',
      explanationDetailed: json['explanation_detailed'] as String? ?? '',
      analyzedAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'schema_version': schemaVersion,
        'content_hash': contentHash,
        'overall_verdict': overallVerdict.label,
        'overall_confidence': overallConfidence,
        'category_scores': categoryScores.map((e) => e.toJson()).toList(),
        'evidence': evidence.map((e) => e.toJson()).toList(),
        'recommendation': recommendation.label,
        'explanation_short': explanationShort,
        'explanation_detailed': explanationDetailed,
      };

  /// Try to parse a JSON string into a Verdict. Returns null if parsing fails.
  static Verdict? tryParse(String jsonString) {
    try {
      final map = jsonDecode(jsonString) as Map<String, dynamic>;
      return Verdict.fromJson(map);
    } catch (_) {
      return null;
    }
  }

  /// Returns a safe-default INCONCLUSIVE verdict for error/timeout scenarios.
  static Verdict inconclusive({String reason = 'Analysis could not be completed'}) {
    return Verdict(
      schemaVersion: 'v1',
      contentHash: '',
      overallVerdict: OverallVerdict.inconclusive,
      overallConfidence: 0.0,
      categoryScores: [],
      evidence: [],
      recommendation: Recommendation.verifyBeforeForwarding,
      explanationShort: reason,
      explanationDetailed: reason,
      analyzedAt: DateTime.now(),
    );
  }
}

// ─── JSON Schema Definition ────────────────────────────────────────────

/// The raw JSON schema string used in the system prompt to constrain
/// the model's output via function calling.
const String verdictJsonSchema = '''
{
  "name": "submit_verdict",
  "description": "Submit a structured truth-detection verdict for the analyzed content.",
  "parameters": {
    "type": "object",
    "required": [
      "schema_version",
      "content_hash",
      "overall_verdict",
      "overall_confidence",
      "category_scores",
      "evidence",
      "recommendation",
      "explanation_short",
      "explanation_detailed"
    ],
    "properties": {
      "schema_version": { "type": "string", "enum": ["v1"] },
      "content_hash": { "type": "string" },
      "overall_verdict": {
        "type": "string",
        "enum": ["LIKELY_AUTHENTIC", "INCONCLUSIVE", "LIKELY_MANIPULATED", "LIKELY_SYNTHETIC"]
      },
      "overall_confidence": { "type": "number", "minimum": 0.0, "maximum": 1.0 },
      "category_scores": {
        "type": "array",
        "items": {
          "type": "object",
          "required": ["category", "confidence"],
          "properties": {
            "category": { "type": "string" },
            "confidence": { "type": "number", "minimum": 0.0, "maximum": 1.0 }
          }
        }
      },
      "evidence": {
        "type": "array",
        "maxItems": 5,
        "items": {
          "type": "object",
          "required": ["type", "description", "location"],
          "properties": {
            "type": { "type": "string" },
            "description": { "type": "string" },
            "location": { "type": "string" }
          }
        }
      },
      "recommendation": {
        "type": "string",
        "enum": ["SAFE_TO_FORWARD", "VERIFY_BEFORE_FORWARDING", "DO_NOT_FORWARD"]
      },
      "explanation_short": { "type": "string" },
      "explanation_detailed": { "type": "string" }
    }
  }
}
''';
