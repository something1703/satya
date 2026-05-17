import 'package:flutter_test/flutter_test.dart';
import 'package:satya/analysis/verdict_schema.dart';

void main() {
  group('Verdict Schema', () {
    test('fromJson parses a valid verdict', () {
      final json = {
        'schema_version': 'v1',
        'content_hash': 'abc123',
        'overall_verdict': 'LIKELY_SYNTHETIC',
        'overall_confidence': 0.85,
        'category_scores': [
          {'category': 'deepfake_visual', 'confidence': 0.9},
        ],
        'evidence': [
          {
            'type': 'visual_artifact',
            'description': 'Warping around jawline',
            'location': 'Frame 3, lower face region',
          },
        ],
        'recommendation': 'DO_NOT_FORWARD',
        'explanation_short': 'This video shows signs of face manipulation.',
        'explanation_detailed': 'Detailed analysis reveals...',
      };

      final verdict = Verdict.fromJson(json);

      expect(verdict.overallVerdict, OverallVerdict.likelySynthetic);
      expect(verdict.overallConfidence, 0.85);
      expect(verdict.recommendation, Recommendation.doNotForward);
      expect(verdict.evidence.length, 1);
      expect(verdict.evidence.first.type, 'visual_artifact');
      expect(verdict.categoryScores.first.category, 'deepfake_visual');
    });

    test('fromString handles unknown verdict gracefully', () {
      expect(
        OverallVerdict.fromString('COMPLETELY_BOGUS'),
        OverallVerdict.inconclusive,
      );
    });

    test('inconclusive() factory returns safe default', () {
      final verdict = Verdict.inconclusive(reason: 'Test failure');
      expect(verdict.overallVerdict, OverallVerdict.inconclusive);
      expect(verdict.overallConfidence, 0.0);
      expect(verdict.recommendation, Recommendation.verifyBeforeForwarding);
    });

    test('tryParse handles invalid JSON', () {
      expect(Verdict.tryParse('not json at all'), isNull);
      expect(Verdict.tryParse('{"partial": true}'), isNotNull);
    });
  });
}
