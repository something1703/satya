import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../config/app_theme.dart';
import '../../analysis/multimodal_pipeline.dart';

import 'verdict_screen.dart';

/// Shown while Gemma 4 is running the analysis pipeline.
///
/// Displays a purposeful scanning animation and status text that updates
/// as pipeline steps complete. This screen is visible for 10–25 seconds —
/// it carries emotional weight and must feel deliberate.
class AnalyzingScreen extends StatefulWidget {
  final String? filePath;
  final String? text;
  final String contentType; // 'image', 'video', 'audio', 'text'

  const AnalyzingScreen({
    super.key,
    this.filePath,
    this.text,
    required this.contentType,
  });

  @override
  State<AnalyzingScreen> createState() => _AnalyzingScreenState();
}

class _AnalyzingScreenState extends State<AnalyzingScreen>
    with TickerProviderStateMixin {
  late AnimationController _scanController;
  late AnimationController _pulseController;
  late Animation<double> _scanAnimation;
  late Animation<double> _pulseAnimation;

  String _statusText = 'Preparing content...';
  int _currentStep = 0;
  bool _hasError = false;
  String? _errorMessage;

  final List<_AnalysisStep> _steps = [
    _AnalysisStep('Preparing content...', Icons.folder_open_rounded),
    _AnalysisStep('Computing content hash...', Icons.fingerprint_rounded),
    _AnalysisStep('Processing media...', Icons.auto_fix_high_rounded),
    _AnalysisStep('Reasoning with Gemma 4...', Icons.psychology_rounded),
    _AnalysisStep('Validating verdict...', Icons.verified_rounded),
  ];

  @override
  void initState() {
    super.initState();

    // Scanning line animation
    _scanController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();
    _scanAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _scanController, curve: Curves.easeInOut),
    );

    // Pulsing glow
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.3, end: 0.8).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _startAnalysis();
  }

  @override
  void dispose() {
    _scanController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _startAnalysis() async {
    try {
      final pipeline = MultimodalPipeline();

      // Step through statuses as the pipeline works
      _updateStep(0); // Preparing

      final verdict = await pipeline.analyze(
        filePath: widget.filePath,
        text: widget.text,
        contentType: widget.contentType,
        onStatusUpdate: (status) {
          if (!mounted) return;
          setState(() => _statusText = status);
        },
        onStepUpdate: (step) {
          if (!mounted) return;
          _updateStep(step);
        },
      );

      if (!mounted) return;

      // Navigate to verdict screen
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => VerdictScreen(verdict: verdict),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = e.toString();
          _statusText = 'Analysis failed';
        });
      }
    }
  }

  void _updateStep(int step) {
    if (!mounted) return;
    setState(() {
      _currentStep = step.clamp(0, _steps.length - 1);
      _statusText = _steps[_currentStep].label;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              const Spacer(flex: 2),

              // ─── Scanning animation ─────────────────────────────
              SizedBox(
                width: 200,
                height: 200,
                child: AnimatedBuilder(
                  animation: Listenable.merge([_scanAnimation, _pulseAnimation]),
                  builder: (context, _) {
                    return CustomPaint(
                      painter: _ScanPainter(
                        scanProgress: _scanAnimation.value,
                        pulseOpacity: _pulseAnimation.value,
                        accentColor: _hasError
                            ? AppTheme.accentRed
                            : AppTheme.accentGreen,
                      ),
                      child: Center(
                        child: Icon(
                          _hasError
                              ? Icons.error_outline_rounded
                              : _steps[_currentStep].icon,
                          size: 48,
                          color: _hasError
                              ? AppTheme.accentRed
                              : AppTheme.accentGreen,
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 40),

              // ─── Status text ────────────────────────────────────
              Text(
                _statusText,
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              // ─── Step indicator ─────────────────────────────────
              if (!_hasError)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_steps.length, (i) {
                    final isActive = i == _currentStep;
                    final isCompleted = i < _currentStep;
                    return Container(
                      width: isActive ? 24 : 8,
                      height: 8,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        color: isCompleted
                            ? AppTheme.accentGreen
                            : isActive
                                ? AppTheme.accentGreen.withValues(alpha: 0.7)
                                : Colors.white.withValues(alpha: 0.15),
                      ),
                    );
                  }),
                ),
              const SizedBox(height: 32),

              // ─── Running locally reassurance ────────────────────
              if (!_hasError)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.lock_outline_rounded,
                      size: 14,
                      color: AppTheme.textMuted.withValues(alpha: 0.6),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Running locally on your device',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: AppTheme.textMuted.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),

              // ─── Error actions ──────────────────────────────────
              if (_hasError) ...[
                const SizedBox(height: 8),
                Text(
                  _errorMessage ?? 'An unknown error occurred.',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: AppTheme.accentRed.withValues(alpha: 0.8),
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back_rounded, size: 18),
                  label: const Text('Go back'),
                ),
              ],

              const Spacer(flex: 3),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Step model ────────────────────────────────────────────────────────

class _AnalysisStep {
  final String label;
  final IconData icon;
  const _AnalysisStep(this.label, this.icon);
}

// ─── Custom painter for the scan animation ─────────────────────────────

class _ScanPainter extends CustomPainter {
  final double scanProgress;
  final double pulseOpacity;
  final Color accentColor;

  _ScanPainter({
    required this.scanProgress,
    required this.pulseOpacity,
    required this.accentColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 8;

    // Outer pulsing circle
    final pulsePaint = Paint()
      ..color = accentColor.withValues(alpha: pulseOpacity * 0.15)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius + 4, pulsePaint);

    // Ring
    final ringPaint = Paint()
      ..color = accentColor.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, radius, ringPaint);

    // Scanning arc
    final arcPaint = Paint()
      ..color = accentColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final startAngle = scanProgress * 2 * pi - pi / 2;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      pi / 3,
      false,
      arcPaint,
    );
  }

  @override
  bool shouldRepaint(_ScanPainter oldDelegate) => true;
}
