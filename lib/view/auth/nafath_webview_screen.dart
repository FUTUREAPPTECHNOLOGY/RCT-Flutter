import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rct/constants/constants.dart';
import 'package:rct/generated/l10n.dart';
import 'package:rct/view-model/services/nafath_api.dart';
import 'package:rct/view-model/services/nafath_logger.dart';
import 'package:rct/view-model/services/nafath_session_store.dart';
import 'package:webview_flutter/webview_flutter.dart';

const String _tag = 'NafathWebView';

const Duration _statusPollInterval = Duration(seconds: 4);
const Duration _statusPollTimeout = Duration(minutes: 5);

enum _Phase { loading, ready, finalizing, failed }

class NafathWebViewResult {
  final bool authenticated;
  final String? errorMessage;

  const NafathWebViewResult.success()
      : authenticated = true,
        errorMessage = null;

  const NafathWebViewResult.failure(this.errorMessage)
      : authenticated = false;
}

/// Hosts the Nafath (IAM) authorization page.
///
/// Completion is detected by watching for the identity provider redirecting
/// back to our own host. The status endpoint is then polled until the backend
/// reports success or failure.
class NafathWebViewScreen extends StatefulWidget {
  final NafathSessionResponse session;
  final String locale;
  final NafathApi? api;

  const NafathWebViewScreen({
    Key? key,
    required this.session,
    this.locale = 'ar',
    this.api,
  }) : super(key: key);

  @override
  State<NafathWebViewScreen> createState() => _NafathWebViewScreenState();
}

class _NafathWebViewScreenState extends State<NafathWebViewScreen> {
  late final NafathApi _api = widget.api ?? NafathApi();
  late final WebViewController _controller;
  late NafathSessionResponse _session;

  _Phase _phase = _Phase.loading;
  int _progress = 0;
  String? _errorMessage;
  bool _handled = false;
  bool _returnHandled = false;
  Timer? _timeoutTimer;

  @override
  void initState() {
    super.initState();
    _session = widget.session;
    _controller = _buildController();
    _start();
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    NafathLog.info(_tag, 'disposed');
    super.dispose();
  }

  // ---------------------------------------------------------------- lifecycle

  Future<void> _start() async {
    NafathLog.info(
      _tag,
      'starting → requestId=${NafathLog.mask(_session.requestId)}, '
      'url=${NafathLog.url(_session.nafathUrl)}',
    );

    // A stale identity-provider cookie would silently skip authentication on a
    // second attempt, which is wrong on a shared device.
    try {
      await WebViewCookieManager().clearCookies();
      NafathLog.info(_tag, 'cleared webview cookies');
    } catch (error, stackTrace) {
      NafathLog.error(_tag, 'could not clear cookies', error, stackTrace);
    }

    if (!mounted) return;
    await _controller.loadRequest(Uri.parse(_session.nafathUrl));
  }

  void _scheduleTimeout() {
    _timeoutTimer?.cancel();
    NafathLog.info(
      _tag,
      'status polling timeout in ${_statusPollTimeout.inMinutes}m',
    );
    _timeoutTimer = Timer(_statusPollTimeout, () {
      if (_handled || !mounted) return;
      _finishWithFailure(S.of(context).nafathExpired);
    });
  }

  // ------------------------------------------------------------- the webview

  WebViewController _buildController() {
    return WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: _onNavigationRequest,
          onProgress: _onProgress,
          onPageStarted: (url) {
            NafathLog.info(_tag, 'page started ${NafathLog.url(url)}');
          },
          onPageFinished: (url) {
            NafathLog.info(_tag, 'page finished ${NafathLog.url(url)}');
            if (!mounted || _handled) return;
            if (_phase == _Phase.loading) {
              setState(() => _phase = _Phase.ready);
            }
          },
          onUrlChange: (change) {
            NafathLog.info(_tag, 'url changed ${NafathLog.url(change.url)}');
            // Safety net: some redirects (JS driven, or a server 302 chain on
            // iOS) can surface here without a navigation request we can veto.
            final uri = Uri.tryParse(change.url ?? '');
            if (uri != null && _isReturnUrl(uri)) {
              _handleReturn(uri, source: 'onUrlChange');
            }
          },
          onWebResourceError: (error) {
            NafathLog.warn(
              _tag,
              'resource error code=${error.errorCode} type=${error.errorType} '
              'mainFrame=${error.isForMainFrame} '
              'url=${NafathLog.url(error.url)} — ${error.description}',
            );
            if (error.isForMainFrame == true && !_handled) {
              _fail(S.of(context).nafathFailed);
            }
          },
          onHttpError: (error) {
            NafathLog.warn(
              _tag,
              'http error ${error.response?.statusCode} on '
              '${NafathLog.url(error.request?.uri.toString())}',
            );
          },
        ),
      );
  }

  void _onProgress(int progress) {
    if (!mounted || _handled) return;
    setState(() {
      _progress = progress;
      if (progress < 100 && _phase == _Phase.ready) _phase = _Phase.loading;
    });
  }

  NavigationDecision _onNavigationRequest(NavigationRequest request) {
    final uri = Uri.tryParse(request.url);
    if (uri == null) {
      NafathLog.warn(_tag, 'blocked unparseable navigation');
      return NavigationDecision.prevent;
    }

    if (_isReturnUrl(uri)) {
      NafathLog.info(
        _tag,
        'intercepted return redirect → ${NafathLog.url(request.url)}',
      );
      _handleReturn(uri, source: 'onNavigationRequest');
      return NavigationDecision.prevent;
    }

    if (!nafathAllowedHosts.contains(uri.host.toLowerCase())) {
      NafathLog.warn(
        _tag,
        'blocked navigation to unexpected host "${uri.host}"',
      );
      return NavigationDecision.prevent;
    }

    return NavigationDecision.navigate;
  }

  bool _isReturnUrl(Uri uri) {
    return uri.toString().toLowerCase().contains('callback');
  }

  // ------------------------------------------------------------- completion

  /// Called once, when the identity provider hands control back to our host.
  void _handleReturn(Uri uri, {required String source}) {
    if (_handled || _returnHandled) return;
    _returnHandled = true;
    final local = S.of(context);

    // The exact shape of this callback is owned by the backend. Logging the
    // parameter names (never the values) is what lets us tighten the match
    // later from "any rctapp.com URL" to the precise path.
    NafathLog.info(
      _tag,
      'RETURN DETECTED via $source → path="${uri.path}" '
      'queryKeys=[${NafathLog.queryKeys(uri)}]',
    );

    if (mounted) {
      setState(() {
        _phase = _Phase.finalizing;
        _errorMessage = null;
      });
    }

    // If the callback already states the outcome, trust it over a round trip.
    final declared = _declaredFailure(uri);
    if (declared != null) {
      NafathLog.warn(_tag, 'callback declared failure: $declared');
      _finishWithFailure(local.nafathFailed);
      return;
    }

    _scheduleTimeout();
    unawaited(_pollStatus());
  }

  Future<void> _pollStatus() async {
    final local = S.of(context);
    try {
      while (mounted && !_handled) {
        final status = await _api.checkStatus(_session.requestId);
        NafathLog.info(
          _tag,
          'status=${status.status} hasToken=${status.token != null} '
          'userKeys=[${status.user?.keys.join(', ') ?? ''}]',
        );

        if (status.isPending) {
          await Future<void>.delayed(_statusPollInterval);
          continue;
        }

        if (status.isFailure) {
          final message = status.message?.trim();
          _finishWithFailure(
            message != null && message.isNotEmpty
                ? message
                : status.reason?.toLowerCase() == 'timeout'
                    ? local.nafathExpired
                    : local.nafathFailed,
          );
          return;
        }

        if (!status.isSuccess) {
          _finishWithFailure(local.nafathFailed);
          return;
        }

        _timeoutTimer?.cancel();
        await NafathSessionStore.persist(status);
        if (!mounted || _handled) return;
        _handled = true;
        NafathLog.info(_tag, 'login complete');
        Navigator.of(context).pop(const NafathWebViewResult.success());
        return;
      }
    } on NafathException catch (error) {
      NafathLog.error(_tag, 'status polling failed', error.message);
      _fail(error.message);
    } catch (error, stackTrace) {
      NafathLog.error(_tag, 'status polling failed', error, stackTrace);
      _fail(local.nafathFailed);
    }
  }

  String? _declaredFailure(Uri uri) {
    final params = uri.queryParameters;
    final error = params['error'] ?? params['error_code'];
    if (error != null && error.isNotEmpty) return error;
    final status = params['status']?.toLowerCase();
    if (status != null &&
        status.isNotEmpty &&
        status != 'success' &&
        status != 'ok') {
      return status;
    }
    return null;
  }

  void _fail(String message) {
    if (!mounted || _handled) return;
    _handled = true;
    _timeoutTimer?.cancel();
    setState(() {
      _phase = _Phase.failed;
      _errorMessage = message;
    });
  }

  void _finishWithFailure(String message) {
    if (!mounted || _handled) return;
    _handled = true;
    _timeoutTimer?.cancel();
    NafathLog.warn(_tag, 'flow failed');
    Navigator.of(context).pop(NafathWebViewResult.failure(message));
  }

  Future<void> _retry() async {
    NafathLog.info(_tag, 'retrying with a fresh session');
    setState(() {
      _phase = _Phase.loading;
      _errorMessage = null;
      _progress = 0;
      _handled = false;
      _returnHandled = false;
    });

    try {
      final session = await _api.createSession(locale: widget.locale);
      if (!mounted) return;
      _session = session;
      await _start();
    } on NafathException catch (error) {
      _fail(error.message);
    } catch (error, stackTrace) {
      NafathLog.error(_tag, 'retry failed', error, stackTrace);
      if (mounted) _fail(S.of(context).nafathFailed);
    }
  }

  void _cancel() {
    NafathLog.info(_tag, 'cancelled by user');
    _handled = true;
    _timeoutTimer?.cancel();
    Navigator.of(context).pop();
  }

  // ------------------------------------------------------------------- view

  @override
  Widget build(BuildContext context) {
    final local = S.of(context);
    final isTerminal = _phase == _Phase.failed;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: Text(local.nafathTitle),
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close),
            tooltip: local.nafathCancel,
            onPressed: _cancel,
          ),
          // A thin, determinate bar that disappears once the page is up —
          // instead of a spinner that never stops.
          bottom: _phase == _Phase.loading
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(2),
                  child: LinearProgressIndicator(
                    value: _progress == 0 ? null : _progress / 100,
                    minHeight: 2,
                    backgroundColor: Colors.grey.shade200,
                  ),
                )
              : null,
        ),
        body: Stack(
          children: [
            // Kept mounted underneath so a transient failure can be retried
            // without tearing down and rebuilding the whole page.
            Offstage(
              offstage: isTerminal,
              child: WebViewWidget(controller: _controller),
            ),
            if (_phase == _Phase.finalizing) _buildFinalizingOverlay(local),
            if (isTerminal) _buildTerminalView(local),
          ],
        ),
      ),
    );
  }

  Widget _buildFinalizingOverlay(S local) {
    return Positioned.fill(
      child: Container(
        color: Colors.white,
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Text(
              local.nafathCompleting,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTerminalView(S local) {
    return Positioned.fill(
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: Colors.grey.shade500,
            ),
            const SizedBox(height: 16),
            Text(
              _errorMessage ?? local.nafathFailed,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _retry,
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(local.nafathRetry),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _cancel,
              child: Text(
                local.nafathCancel,
                style: TextStyle(color: Colors.grey.shade700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
