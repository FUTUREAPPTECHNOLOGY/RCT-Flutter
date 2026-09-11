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
    _log('Initializing with URL: ${_displayUrl(widget.nafathUrl)}');
    _log('Request ID: ${_mask(widget.requestId)}');
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setOnConsoleMessage((message) {
        _log('JavaScript console [${message.level.name}]: ${message.message}');
      })
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            _log('Page load progress: $progress%');
          },
          onPageStarted: (url) {
            _log('Page started: ${_displayUrl(url)}');
          },
          onPageFinished: (url) {
            _log('Page finished: ${_displayUrl(url)}');
          },
          onWebResourceError: (error) {
            _log(
              'Web resource error: code=${error.errorCode}, '
              'type=${error.errorType}, mainFrame=${error.isForMainFrame}, '
              'url=${_displayUrl(error.url)}, description=${error.description}',
            );
          },
          onHttpError: (error) {
            _log('HTTP error: $error');
          },
          onUrlChange: (change) {
            _log('URL changed: ${_displayUrl(change.url)}');
          },
          onNavigationRequest: (request) {
            _log(
              'Navigation requested: ${_displayUrl(request.url)}, '
              'isMainFrame=${request.isMainFrame}',
            );
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.nafathUrl));

    _log('Starting status polling every 3 seconds');
    _startStatusPolling();
  }

  Future<void> _startStatusPolling() async {
    _pollingTimer =
        Timer.periodic(const Duration(seconds: 3), (_) => _checkStatus());
    Future.delayed(const Duration(minutes: 5), () {
      if (!_hasCompleted && mounted) {
        _log('Status polling timed out after 5 minutes');
        _pollingTimer?.cancel();
        setState(() {
          _statusMessage = 'Authentication timed out. Please try again.';
        });
      }
    });
  }

  Future<void> _checkStatus() async {
    if (_isChecking || _hasCompleted) {
      _log(
        'Skipping status check: isChecking=$_isChecking, '
        'hasCompleted=$_hasCompleted',
      );
      return;
    }
    _isChecking = true;
    _log('Checking Nafath status for request ${_mask(widget.requestId)}');

    try {
      final statusResponse = await _nafathApi.checkStatus(widget.requestId);
      _log(
        'Nafath response: status=${statusResponse.status}, '
        'hasToken=${statusResponse.token != null}, '
        'userKeys=${statusResponse.user?.keys.toList() ?? <String>[]}',
      );
      if (statusResponse.status.toLowerCase() == 'success' &&
          statusResponse.token != null) {
        _log('Nafath authentication succeeded; saving token');
        _hasCompleted = true;
        _pollingTimer?.cancel();
        await _saveToken(statusResponse.token!);
        if (mounted) {
          _log('Closing WebView screen with successful result');
          Navigator.of(context).pop(true);
        }
      } else if (statusResponse.status.toLowerCase() == 'pending') {
        _log('Nafath authentication is still pending');
        setState(() {
          _statusMessage = 'Waiting for authentication approval...';
        });
      } else {
        _log('Nafath authentication returned non-success status');
        setState(() {
          _statusMessage = 'Authentication status: ${statusResponse.status}';
        });
      }
    } catch (error, stackTrace) {
      _log('Nafath status check failed: $error');
      debugPrintStack(
          label: '[NafathWebView] Status check stack trace',
          stackTrace: stackTrace);
      if (mounted) {
        setState(() {
          _statusMessage = 'Unable to check login status. Please try again.';
        });
      }
    } finally {
      _isChecking = false;
    }
  }

  Future<void> _saveToken(String token) async {
    try {
      await secureStorage.write(key: 'token', value: token);
      await AppPreferences.saveData(key: 'loginToken', value: token);
      _log('Authentication token saved successfully');
    } catch (error, stackTrace) {
      _log('Failed to save authentication token: $error');
      debugPrintStack(
          label: '[NafathWebView] Token storage stack trace',
          stackTrace: stackTrace);
    }
  }

  @override
  void dispose() {
    _log('Disposing WebView screen');
    _pollingTimer?.cancel();
    super.dispose();
  }

  void _log(String message) {
    debugPrint('[NafathWebView] $message');
  }

  String _displayUrl(String? url) {
    if (url == null) return '<null>';
    final uri = Uri.tryParse(url);
    if (uri == null) return '<invalid URL>';
    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: uri.path,
    ).toString();
  }

  String _mask(String value) {
    if (value.length <= 4) return '****';
    return '${value.substring(0, 2)}****${value.substring(value.length - 2)}';
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
