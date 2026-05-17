import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'firebase_options.dart';
import 'analysis/gemma_service.dart';
import 'config/app_theme.dart';
import 'ui/screens/setup_screen.dart';
import 'ui/screens/home_screen.dart';
import 'ui/screens/analyzing_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Initialize flutter_gemma with the HF token from --dart-define
  await FlutterGemma.initialize(
    huggingFaceToken: const String.fromEnvironment('HF_TOKEN'),
    maxDownloadRetries: 10,
  );

  // Check if the model is already installed
  final isInstalled = await GemmaService.instance.checkInstalled();

  // Check for initial shared content (app launched via share)
  final initialMedia = await ReceiveSharingIntent.instance.getInitialMedia();

  runApp(SatyaApp(
    modelInstalled: isInstalled,
    initialSharedMedia: initialMedia.isNotEmpty ? initialMedia : null,
  ));
}

class SatyaApp extends StatefulWidget {
  final bool modelInstalled;
  final List<SharedMediaFile>? initialSharedMedia;

  const SatyaApp({
    super.key,
    required this.modelInstalled,
    this.initialSharedMedia,
  });

  @override
  State<SatyaApp> createState() => _SatyaAppState();
}

class _SatyaAppState extends State<SatyaApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  StreamSubscription<List<SharedMediaFile>>? _shareSubscription;

  @override
  void initState() {
    super.initState();

    // Listen for shares received while the app is already running
    _shareSubscription = ReceiveSharingIntent.instance
        .getMediaStream()
        .listen(_handleSharedMedia, onError: (err) {
      debugPrint('[SATYA] Share intent error: $err');
    });
  }

  @override
  void dispose() {
    _shareSubscription?.cancel();
    super.dispose();
  }

  /// Handle incoming shared media — navigate directly to analysis.
  void _handleSharedMedia(List<SharedMediaFile> files) {
    if (files.isEmpty) return;

    final file = files.first;
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;

    final contentType = _detectContentType(file);

    debugPrint('[SATYA] Received shared content: ${file.path} (type: $contentType)');

    navigator.push(
      MaterialPageRoute(
        builder: (_) => AnalyzingScreen(
          filePath: file.path,
          text: contentType == 'text' ? file.path : null,
          contentType: contentType,
        ),
      ),
    );
  }

  /// Detect content type from SharedMediaFile.
  String _detectContentType(SharedMediaFile file) {
    final mimeType = file.mimeType?.toLowerCase() ?? '';
    final path = file.path.toLowerCase();

    if (mimeType.startsWith('image/') || path.endsWith('.jpg') ||
        path.endsWith('.jpeg') || path.endsWith('.png') ||
        path.endsWith('.webp') || path.endsWith('.gif')) {
      return 'image';
    }
    if (mimeType.startsWith('video/') || path.endsWith('.mp4') ||
        path.endsWith('.mov') || path.endsWith('.avi') ||
        path.endsWith('.mkv')) {
      return 'video';
    }
    if (mimeType.startsWith('audio/') || path.endsWith('.mp3') ||
        path.endsWith('.wav') || path.endsWith('.ogg') ||
        path.endsWith('.m4a')) {
      return 'audio';
    }
    return 'text';
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'SATYA — On-Device Truth Detection',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark, // default to dark for the demo
      home: widget.modelInstalled
          ? _ModelInitializer(initialSharedMedia: widget.initialSharedMedia)
          : const SetupScreen(),
    );
  }
}

/// Intermediate widget that initializes the already-downloaded model
/// before navigating to the Home screen (or directly to analysis if
/// launched via share intent).
class _ModelInitializer extends StatefulWidget {
  final List<SharedMediaFile>? initialSharedMedia;

  const _ModelInitializer({this.initialSharedMedia});

  @override
  State<_ModelInitializer> createState() => _ModelInitializerState();
}

class _ModelInitializerState extends State<_ModelInitializer> {
  @override
  void initState() {
    super.initState();
    _initModel();
  }

  Future<void> _initModel() async {
    try {
      await GemmaService.instance.initialize();
      if (!mounted) return;

      // If launched via share intent, go directly to analysis
      if (widget.initialSharedMedia != null &&
          widget.initialSharedMedia!.isNotEmpty) {
        final file = widget.initialSharedMedia!.first;
        final contentType = _detectContentType(file);

        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => AnalyzingScreen(
              filePath: file.path,
              text: contentType == 'text' ? file.path : null,
              contentType: contentType,
            ),
          ),
        );
      } else {
        // Normal launch — go to home screen
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load model: $e'),
            backgroundColor: AppTheme.accentRed,
          ),
        );
      }
    }
  }

  /// Detect content type from SharedMediaFile.
  String _detectContentType(SharedMediaFile file) {
    final mimeType = file.mimeType?.toLowerCase() ?? '';
    final path = file.path.toLowerCase();

    if (mimeType.startsWith('image/') || path.endsWith('.jpg') ||
        path.endsWith('.jpeg') || path.endsWith('.png') ||
        path.endsWith('.webp')) {
      return 'image';
    }
    if (mimeType.startsWith('video/') || path.endsWith('.mp4') ||
        path.endsWith('.mov')) {
      return 'video';
    }
    if (mimeType.startsWith('audio/') || path.endsWith('.mp3') ||
        path.endsWith('.wav')) {
      return 'audio';
    }
    return 'text';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundDark,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(
              color: AppTheme.accentGreen,
            ),
            const SizedBox(height: 24),
            Text(
              'Loading Gemma 4...',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
