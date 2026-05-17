import 'package:flutter/material.dart';
import '../../analysis/gemma_service.dart';
import '../../config/app_config.dart';
import 'home_screen.dart';

/// Shown on first launch when the model hasn't been downloaded yet.
///
/// Displays download progress and navigates to HelloGemmaScreen when done.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  int _progress = 0;
  bool _isDownloading = false;
  String _statusText = 'Ready to download ${AppConfig.modelDisplayName}';
  String? _errorText;

  Future<void> _startDownload() async {
    setState(() {
      _isDownloading = true;
      _errorText = null;
      _statusText = 'Starting download...';
    });

    try {
      // Read the HF token passed via --dart-define at build time.
      const hfToken = String.fromEnvironment('HF_TOKEN', defaultValue: '');

      await GemmaService.instance.installModel(
        hfToken: hfToken,
        onProgress: (progress) {
          if (mounted) {
            setState(() {
              _progress = progress;
              _statusText =
                  'Downloading ${AppConfig.modelDisplayName}... $progress%';
            });
          }
        },
      );

      if (!mounted) return;

      setState(() {
        _statusText = 'Initializing model...';
      });

      await GemmaService.instance.initialize();

      if (!mounted) return;

      // Navigate to the Hello Gemma screen
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _errorText = e.toString();
          _statusText = 'Download failed';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // App name
                Text(
                  AppConfig.appName,
                  style: const TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: 8,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  AppConfig.appTagline,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white.withValues(alpha: 0.6),
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 64),

                // Model info card
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.download_rounded,
                        size: 48,
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _statusText,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white.withValues(alpha: 0.8),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Progress bar
                      if (_isDownloading) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: _progress / 100.0,
                            minHeight: 6,
                            backgroundColor: Colors.white.withValues(alpha: 0.1),
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              Color(0xFF10B981), // sage green
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '3.66 GB — runs entirely on your device',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.4),
                          ),
                        ),
                      ],

                      // Error display
                      if (_errorText != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _errorText!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFFDC2626),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],

                      // Download button (shown when not downloading)
                      if (!_isDownloading) ...[
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _startDownload,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1A1F3A),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              'Download Model',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Privacy assurance
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.lock_outline,
                      size: 14,
                      color: Colors.white.withValues(alpha: 0.3),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'All analysis runs locally. Nothing leaves your device.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.3),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
