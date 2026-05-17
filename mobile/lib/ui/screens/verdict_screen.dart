import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../config/app_theme.dart';
import '../../analysis/verdict_schema.dart';
import 'home_screen.dart';

/// The verdict display screen — where the analysis pays off.
///
/// Displays: verdict badge, confidence bar, recommendation,
/// evidence breakdown, and explanations.
class VerdictScreen extends StatelessWidget {
  final Verdict verdict;

  const VerdictScreen({super.key, required this.verdict});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ─── Top bar ──────────────────────────────────────
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_rounded),
                    color: AppTheme.textSecondary,
                  ),
                  const Spacer(),
                  Text(
                    'Analysis Complete',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const Spacer(),
                  const SizedBox(width: 48), // balance
                ],
              ),
              const SizedBox(height: 24),

              // ─── 1. Verdict badge ─────────────────────────────
              _VerdictBadge(verdict: verdict.overallVerdict),
              const SizedBox(height: 24),

              // ─── 2. Confidence bar ────────────────────────────
              _ConfidenceBar(confidence: verdict.overallConfidence),
              const SizedBox(height: 16),

              // ─── 3. Recommendation card ───────────────────────
              _RecommendationCard(recommendation: verdict.recommendation),
              const SizedBox(height: 20),

              // ─── 4. Evidence list ─────────────────────────────
              if (verdict.evidence.isNotEmpty) ...[
                Text(
                  'Evidence',
                  style: GoogleFonts.fraunces(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                ...verdict.evidence.map((e) => _EvidenceCard(evidence: e)),
                const SizedBox(height: 16),
              ],

              // ─── 5. Explanation ───────────────────────────────
              _ExplanationSection(
                shortText: verdict.explanationShort,
                detailedText: verdict.explanationDetailed,
              ),
              const SizedBox(height: 24),

              // ─── 6. Action row ────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        // TODO Phase 3: report incorrect verdict to Firebase
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Feedback recorded. Thank you!'),
                          ),
                        );
                      },
                      icon: const Icon(Icons.flag_outlined, size: 18),
                      label: const Text('Report'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.textSecondary,
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(
                            builder: (_) => const HomeScreen(),
                          ),
                          (route) => false,
                        );
                      },
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('Analyze Another'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryIndigo,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Verdict Badge ─────────────────────────────────────────────────────

class _VerdictBadge extends StatelessWidget {
  final OverallVerdict verdict;
  const _VerdictBadge({required this.verdict});

  Color get _color {
    switch (verdict) {
      case OverallVerdict.likelyAuthentic:
        return AppTheme.verdictAuthentic;
      case OverallVerdict.inconclusive:
        return AppTheme.verdictInconclusive;
      case OverallVerdict.likelyManipulated:
        return AppTheme.verdictManipulated;
      case OverallVerdict.likelySynthetic:
        return AppTheme.verdictSynthetic;
    }
  }

  IconData get _icon {
    switch (verdict) {
      case OverallVerdict.likelyAuthentic:
        return Icons.check_circle_rounded;
      case OverallVerdict.inconclusive:
        return Icons.help_rounded;
      case OverallVerdict.likelyManipulated:
        return Icons.warning_rounded;
      case OverallVerdict.likelySynthetic:
        return Icons.smart_toy_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _color.withValues(alpha: 0.25),
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          Icon(_icon, size: 56, color: _color),
          const SizedBox(height: 16),
          Text(
            verdict.displayLabel,
            style: GoogleFonts.fraunces(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: _color,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ─── Confidence Bar ────────────────────────────────────────────────────

class _ConfidenceBar extends StatelessWidget {
  final double confidence;
  const _ConfidenceBar({required this.confidence});

  Color get _barColor {
    if (confidence >= 0.7) return AppTheme.accentGreen;
    if (confidence >= 0.4) return AppTheme.accentAmber;
    return AppTheme.accentRed;
  }

  @override
  Widget build(BuildContext context) {
    final percentage = (confidence * 100).toInt();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Confidence',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textSecondary,
                ),
              ),
              Text(
                '$percentage%',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: _barColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: confidence,
              minHeight: 8,
              backgroundColor: Colors.white.withValues(alpha: 0.08),
              valueColor: AlwaysStoppedAnimation<Color>(_barColor),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Recommendation Card ───────────────────────────────────────────────

class _RecommendationCard extends StatelessWidget {
  final Recommendation recommendation;
  const _RecommendationCard({required this.recommendation});

  Color get _color {
    switch (recommendation) {
      case Recommendation.safeToForward:
        return AppTheme.accentGreen;
      case Recommendation.verifyBeforeForwarding:
        return AppTheme.accentAmber;
      case Recommendation.doNotForward:
        return AppTheme.accentRed;
    }
  }

  IconData get _icon {
    switch (recommendation) {
      case Recommendation.safeToForward:
        return Icons.check_rounded;
      case Recommendation.verifyBeforeForwarding:
        return Icons.info_outline_rounded;
      case Recommendation.doNotForward:
        return Icons.block_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _color.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Icon(_icon, color: _color, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              recommendation.displayLabel,
              style: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: _color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Evidence Card ─────────────────────────────────────────────────────

class _EvidenceCard extends StatelessWidget {
  final Evidence evidence;
  const _EvidenceCard({required this.evidence});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.accentAmber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  evidence.type,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.accentAmber,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                evidence.location,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: AppTheme.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            evidence.description,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: AppTheme.textPrimary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Explanation Section ───────────────────────────────────────────────

class _ExplanationSection extends StatefulWidget {
  final String shortText;
  final String detailedText;
  const _ExplanationSection({
    required this.shortText,
    required this.detailedText,
  });

  @override
  State<_ExplanationSection> createState() => _ExplanationSectionState();
}

class _ExplanationSectionState extends State<_ExplanationSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Explanation',
            style: GoogleFonts.fraunces(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            widget.shortText,
            style: GoogleFonts.inter(
              fontSize: 14,
              color: AppTheme.textPrimary,
              height: 1.5,
            ),
          ),
          if (widget.detailedText.isNotEmpty &&
              widget.detailedText != widget.shortText) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Row(
                children: [
                  Text(
                    _expanded ? 'Show less' : 'Tell me more',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.accentGreen,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 18,
                    color: AppTheme.accentGreen,
                  ),
                ],
              ),
            ),
            if (_expanded) ...[
              const SizedBox(height: 10),
              Divider(color: Colors.white.withValues(alpha: 0.06)),
              const SizedBox(height: 10),
              Text(
                widget.detailedText,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: AppTheme.textSecondary,
                  height: 1.6,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
