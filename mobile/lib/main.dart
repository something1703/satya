import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'firebase_options.dart';
import 'analysis/gemma_service.dart';
import 'config/app_theme.dart';
import 'ui/screens/setup_screen.dart';
import 'ui/screens/home_screen.dart';

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

  runApp(SatyaApp(modelInstalled: isInstalled));
}

class SatyaApp extends StatelessWidget {
  final bool modelInstalled;

  const SatyaApp({super.key, required this.modelInstalled});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SATYA — On-Device Truth Detection',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark, // default to dark for the demo
      home: modelInstalled
          ? const _ModelInitializer()
          : const SetupScreen(),
    );
  }
}

/// Intermediate widget that initializes the already-downloaded model
/// before navigating to the Home screen.
class _ModelInitializer extends StatefulWidget {
  const _ModelInitializer();

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
      if (mounted) {
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
