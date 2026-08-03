import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rct/main.dart';
import 'package:rct/shared_pref.dart';
import 'package:rct/view-model/services/nafath_api.dart';
import 'package:webview_flutter/webview_flutter.dart';

class NafathWebViewScreen extends StatefulWidget {
  final String nafathUrl;
  final String requestId;

  const NafathWebViewScreen(
      {Key? key, required this.nafathUrl, required this.requestId})
      : super(key: key);

  @override
  State<NafathWebViewScreen> createState() => _NafathWebViewScreenState();
}

class _NafathWebViewScreenState extends State<NafathWebViewScreen> {
  late final WebViewController _webViewController;
  final NafathApi _nafathApi = NafathApi();
  Timer? _pollingTimer;
  bool _isChecking = false;
  bool _hasCompleted = false;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.nafathUrl));

    _startStatusPolling();
  }

  Future<void> _startStatusPolling() async {
    _pollingTimer =
        Timer.periodic(const Duration(seconds: 3), (_) => _checkStatus());
    Future.delayed(const Duration(minutes: 5), () {
      if (!_hasCompleted && mounted) {
        _pollingTimer?.cancel();
        setState(() {
          _statusMessage = 'Authentication timed out. Please try again.';
        });
      }
    });
  }

  Future<void> _checkStatus() async {
    if (_isChecking || _hasCompleted) return;
    _isChecking = true;

    try {
      final statusResponse = await _nafathApi.checkStatus(widget.requestId);
      if (statusResponse.status.toLowerCase() == 'success' &&
          statusResponse.token != null) {
        _hasCompleted = true;
        _pollingTimer?.cancel();
        await _saveToken(statusResponse.token!);
        if (mounted) {
          Navigator.of(context).pop(true);
        }
      } else if (statusResponse.status.toLowerCase() == 'pending') {
        setState(() {
          _statusMessage = 'Waiting for authentication approval...';
        });
      } else {
        setState(() {
          _statusMessage = 'Authentication status: ${statusResponse.status}';
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Unable to check login status. Please try again.';
      });
    } finally {
      _isChecking = false;
    }
  }

  Future<void> _saveToken(String token) async {
    try {
      await secureStorage.write(key: 'token', value: token);
      await AppPreferences.saveData(key: 'loginToken', value: token);
    } catch (_) {
      // ignore storage failures
    }
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nafath Login'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      body: Column(
        children: [
          Expanded(
            child: WebViewWidget(controller: _webViewController),
          ),
          if (_statusMessage != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              child: Text(
                _statusMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14),
              ),
            ),
          if (!_hasCompleted)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: CircularProgressIndicator(),
            ),
        ],
      ),
    );
  }
}
