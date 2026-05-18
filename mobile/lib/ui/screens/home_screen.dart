import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../../config/app_theme.dart';
import 'analyzing_screen.dart';

/// The main surface of the app. One screen, one purpose.
///
/// Actions: "Analyze from gallery", "Paste text or link", and "Try Examples".
/// No tabs, no bottom nav. Serious tool, clean interface.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _textController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final XFile? file = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1920,
    );
    if (file != null && mounted) {
      _navigateToAnalysis(filePath: file.path, contentType: 'image');
    }
  }

  Future<void> _pickVideo() async {
    final XFile? file = await _picker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(seconds: 60),
    );
    if (file != null && mounted) {
      _navigateToAnalysis(filePath: file.path, contentType: 'video');
    }
  }

  void _analyzeText() {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      HapticFeedback.lightImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Please paste some text or a claim to analyze.',
            style: GoogleFonts.inter(fontSize: 13),
          ),
          backgroundColor: AppTheme.surfaceElevated,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }
    _navigateToAnalysis(text: text, contentType: 'text');
  }

  void _navigateToAnalysis({
    String? filePath,
    String? text,
    required String contentType,
  }) {
    HapticFeedback.mediumImpact();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AnalyzingScreen(
          filePath: filePath,
          text: text,
          contentType: contentType,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 48),

              // ─── Animated shield icon ───────────────────────────
              AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  return Opacity(
                    opacity: _pulseAnimation.value,
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppTheme.accentGreen.withValues(alpha: 0.1),
                        border: Border.all(
                          color: AppTheme.accentGreen.withValues(alpha: 0.3),
                          width: 2,
                        ),
                      ),
                      child: const Icon(
                        Icons.shield_outlined,
                        size: 40,
                        color: AppTheme.accentGreen,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),

              // ─── App name ───────────────────────────────────────
              Text(
                'SATYA',
                style: GoogleFonts.fraunces(
                  fontSize: 44,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                  letterSpacing: 6,
                ),
                semanticsLabel: 'SATYA — On-Device Truth Detection',
              ),
              const SizedBox(height: 6),
              Text(
                'On-Device Truth Detection',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: AppTheme.textSecondary,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 36),

              // ─── Primary actions ────────────────────────────────
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _pickImage,
                  icon: const Icon(Icons.image_search_rounded, size: 22),
                  label: const Text('Analyze Image'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryIndigo,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _pickVideo,
                  icon: const Icon(Icons.videocam_rounded, size: 22),
                  label: const Text('Analyze Video'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.surfaceElevated,
                    foregroundColor: AppTheme.textPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.1),
                      ),
                    ),
                    textStyle: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),

              // ─── Divider ────────────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: Divider(
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'or paste text',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Divider(
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ─── Text input ─────────────────────────────────────
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.surfaceElevated,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: Column(
                  children: [
                    TextField(
                      controller: _textController,
                      maxLines: 4,
                      minLines: 3,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: AppTheme.textPrimary,
                      ),
                      decoration: InputDecoration(
                        hintText:
                            'Paste a suspicious message, claim, or URL...',
                        hintStyle: GoogleFonts.inter(
                          fontSize: 14,
                          color: AppTheme.textMuted,
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.all(16),
                      ),
                    ),
                    Divider(
                      height: 1,
                      color: Colors.white.withValues(alpha: 0.05),
                    ),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton.icon(
                        onPressed: _analyzeText,
                        icon: const Icon(Icons.search_rounded, size: 18),
                        label: const Text('Analyze Text'),
                        style: TextButton.styleFrom(
                          foregroundColor: AppTheme.accentGreen,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          textStyle: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // ─── Try Examples ───────────────────────────────────
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Try an Example',
                  style: GoogleFonts.fraunces(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Tap a card to see SATYA in action',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppTheme.textMuted,
                  ),
                ),
              ),
              const SizedBox(height: 14),

              _ExampleCard(
                icon: Icons.coronavirus_rounded,
                iconColor: AppTheme.accentRed,
                title: 'Health Misinformation',
                subtitle: 'Viral WhatsApp claim about COVID cure',
                onTap: () => _navigateToAnalysis(
                  text: 'BREAKING: Exposed government report reveals drinking warm lemon water with turmeric cures COVID-19 in 24 hours. Big pharma has been hiding this from you! Share with everyone before they delete this! 🚨🍋',
                  contentType: 'text',
                ),
              ),

              _ExampleCard(
                icon: Icons.how_to_vote_rounded,
                iconColor: AppTheme.accentAmber,
                title: 'Political Fabrication',
                subtitle: 'Fake quote attributed to a public figure',
                onTap: () => _navigateToAnalysis(
                  text: 'JUST IN: Supreme Court of India has officially declared that all digital payments will be banned from next month. Cash will be the only legal tender. RBI has confirmed this. Forward to all your contacts immediately!',
                  contentType: 'text',
                ),
              ),

              _ExampleCard(
                icon: Icons.smart_toy_rounded,
                iconColor: AppTheme.verdictSynthetic,
                title: 'AI-Generated Content',
                subtitle: 'Deepfake-style synthetic claim',
                onTap: () => _navigateToAnalysis(
                  text: 'NASA has confirmed that a second moon has been captured by Earth\'s gravity. The new moon, named Luna-2, will be visible starting next week. Scientists say this happens once every 10,000 years. Share this historic moment! 🌙',
                  contentType: 'text',
                ),
              ),
              const SizedBox(height: 28),

              // ─── Share hint ─────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.share_rounded,
                    size: 14,
                    color: AppTheme.textMuted.withValues(alpha: 0.6),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Or share content directly to SATYA from any app',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: AppTheme.textMuted.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // ─── Privacy assurance ──────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.lock_outline_rounded,
                    size: 13,
                    color: AppTheme.accentGreen.withValues(alpha: 0.5),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'All analysis runs locally. Nothing leaves your device.',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: AppTheme.textMuted.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ─── Powered by footer ──────────────────────────────
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceElevated.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.04),
                  ),
                ),
                child: Text(
                  'Powered by Gemma 4 · Unsloth · LiteRT',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: AppTheme.textMuted.withValues(alpha: 0.5),
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Example Card ──────────────────────────────────────────────────────

class _ExampleCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ExampleCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          splashColor: iconColor.withValues(alpha: 0.08),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: iconColor, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 14,
                  color: AppTheme.textMuted.withValues(alpha: 0.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
