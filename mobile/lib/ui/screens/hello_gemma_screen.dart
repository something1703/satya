import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../analysis/gemma_service.dart';
import '../../config/app_config.dart';

/// Phase 1 verification screen: text input → Gemma 4 response.
///
/// Also includes a "Test Firestore" button to verify Firebase wiring.
/// This screen is intentionally simple — it exists to prove the plumbing works.
/// It will be replaced by the real UI in Phase 2.
class HelloGemmaScreen extends StatefulWidget {
  const HelloGemmaScreen({super.key});

  @override
  State<HelloGemmaScreen> createState() => _HelloGemmaScreenState();
}

class _HelloGemmaScreenState extends State<HelloGemmaScreen> {
  final _promptController = TextEditingController();
  final _scrollController = ScrollController();
  String _response = '';
  bool _isGenerating = false;
  String _firestoreStatus = '';

  @override
  void dispose() {
    _promptController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendPrompt() async {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty || _isGenerating) return;

    setState(() {
      _isGenerating = true;
      _response = '';
    });

    try {
      final stream = GemmaService.instance.generateTextStream(prompt);
      await for (final chunk in stream) {
        if (!mounted) return;
        setState(() {
          _response += chunk;
        });
        // Auto-scroll to bottom as tokens arrive
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _response = 'Error: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGenerating = false;
        });
      }
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
      );
    }
  }

  /// Write and read a test document from Firestore to verify connectivity.
  Future<void> _testFirestore() async {
    setState(() {
      _firestoreStatus = 'Writing to Firestore...';
    });

    try {
      final testDoc = FirebaseFirestore.instance
          .collection('_phase1_test')
          .doc();

      final testData = {
        'timestamp': FieldValue.serverTimestamp(),
        'device_id': testDoc.id,
        'message': 'Phase 1 connectivity test from ${AppConfig.appName}',
      };

      await testDoc.set(testData);

      // Read it back
      final snapshot = await testDoc.get();
      if (snapshot.exists) {
        setState(() {
          _firestoreStatus =
              '✓ Firestore OK — wrote and read doc ${testDoc.id}';
        });
      } else {
        setState(() {
          _firestoreStatus = '✗ Write succeeded but read failed';
        });
      }
    } catch (e) {
      setState(() {
        _firestoreStatus = '✗ Firestore error: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        title: const Text(
          'SATYA — Phase 1 Test',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        backgroundColor: const Color(0xFF1A1F3A),
        elevation: 0,
        actions: [
          // Firestore test button
          TextButton.icon(
            onPressed: _testFirestore,
            icon: const Icon(Icons.cloud_outlined, color: Colors.white70, size: 18),
            label: const Text(
              'Test Firestore',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Firestore status bar
          if (_firestoreStatus.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: _firestoreStatus.startsWith('✓')
                  ? const Color(0xFF10B981).withValues(alpha: 0.15)
                  : _firestoreStatus.startsWith('✗')
                      ? const Color(0xFFDC2626).withValues(alpha: 0.15)
                      : const Color(0xFFF59E0B).withValues(alpha: 0.15),
              child: Text(
                _firestoreStatus,
                style: TextStyle(
                  fontSize: 12,
                  color: _firestoreStatus.startsWith('✓')
                      ? const Color(0xFF10B981)
                      : _firestoreStatus.startsWith('✗')
                          ? const Color(0xFFDC2626)
                          : const Color(0xFFF59E0B),
                ),
              ),
            ),

          // Response area
          Expanded(
            child: _response.isEmpty
                ? Center(
                    child: Text(
                      'Type a prompt below to test Gemma 4 E4B inference.\n'
                      'The response streams directly from the model\n'
                      'running on this device.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withValues(alpha: 0.4),
                        height: 1.6,
                      ),
                    ),
                  )
                : ListView(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    children: [
                      // User prompt
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1F3A).withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _promptController.text,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      // Model response
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                        child: SelectableText(
                          _response,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            height: 1.6,
                          ),
                        ),
                      ),
                      if (_isGenerating)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white.withValues(alpha: 0.4),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Generating...',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white.withValues(alpha: 0.4),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),

          // Input area
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF111111),
              border: Border(
                top: BorderSide(
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _promptController,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Type a prompt...',
                        hintStyle: TextStyle(
                          color: Colors.white.withValues(alpha: 0.3),
                        ),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.05),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      onSubmitted: (_) => _sendPrompt(),
                      textInputAction: TextInputAction.send,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _isGenerating ? null : _sendPrompt,
                    icon: Icon(
                      Icons.send_rounded,
                      color: _isGenerating
                          ? Colors.white.withValues(alpha: 0.2)
                          : const Color(0xFF10B981),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
