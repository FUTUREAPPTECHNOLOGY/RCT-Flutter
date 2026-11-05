import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:rct/constants/constants.dart';
import 'package:rct/generated/l10n.dart';
import 'package:rct/view-model/services/nafath_api.dart';
import 'package:rct/view-model/services/nafath_logger.dart';
import 'package:rct/view-model/services/nafath_session_store.dart';
import 'package:rct/view/auth/nafath_style.dart';
import 'package:url_launcher/url_launcher.dart';

const String _tag = 'NafathWaiting';

const int _pollEverySeconds = 3;
const int _defaultLifetimeSeconds = 60;
const int _maxQuietErrors = 3;

class NafathResult {
  final bool authenticated;
  final String? errorMessage;

  const NafathResult.success()
      : authenticated = true,
        errorMessage = null;

  const NafathResult.failure(this.errorMessage) : authenticated = false;
}

enum _Phase { waiting, finalizing, failed }

/// Shows the number to pick in the Nafath app and waits for the outcome.
///
/// Status is requested every few seconds, never two at once, and once right
/// away when the app returns from Nafath. The backend returns `success` only
/// once, so the token is persisted as soon as it arrives.
class NafathWaitingScreen extends StatefulWidget {
  final NafathMfaResponse request;
  final String nationalId;
  final String locale;
  final NafathApi? api;

  const NafathWaitingScreen({
    Key? key,
    required this.request,
    required this.nationalId,
    this.locale = 'ar',
    this.api,
  }) : super(key: key);

  @override
  State<NafathWaitingScreen> createState() => _NafathWaitingScreenState();
}

class _NafathWaitingScreenState extends State<NafathWaitingScreen>
    with WidgetsBindingObserver {
  late final NafathApi _api = widget.api ?? NafathApi();
  late NafathMfaResponse _request;
  late DateTime _deadline;
  late int _lifetime;

  Timer? _ticker;
  _Phase _phase = _Phase.waiting;
  String? _random;
  String? _message;
  int _remaining = 0;
  int _tickCount = 0;
  int _quietErrors = 0;
  bool _inFlight = false;
  bool _done = false;
  bool _connectionIssue = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _begin(widget.request);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from the Nafath app: check now instead of waiting for the tick.
    if (state == AppLifecycleState.resumed && !_done) {
      NafathLog.info(_tag, 'app resumed, checking status now');
      unawaited(_poll());
    }
  }

  // --------------------------------------------------------------- lifecycle

  void _begin(NafathMfaResponse request) {
    _request = request;
    _random = request.random;
    _lifetime = (request.expiresIn ?? _defaultLifetimeSeconds).clamp(10, 600);
    _deadline = DateTime.now().add(Duration(seconds: _lifetime));
    _remaining = _lifetime;
    _tickCount = 0;
    _quietErrors = 0;
    _done = false;
    _connectionIssue = false;
    _phase = _Phase.waiting;
    _message = null;
    NafathLog.info(
      _tag,
      'waiting for approval → requestId=${NafathLog.mask(request.requestId)}, '
      'lifetime=${_lifetime}s',
    );
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
  }

  void _onTick() {
    if (!mounted || _done) return;
    final left = _deadline.difference(DateTime.now()).inSeconds;
    setState(() => _remaining = left < 0 ? 0 : left);

    if (left <= 0) {
      unawaited(_expire());
      return;
    }
    _tickCount++;
    if (_tickCount % _pollEverySeconds == 0) unawaited(_poll());
  }

  /// The countdown reached zero: ask one last time, then give up.
  Future<void> _expire() async {
    _ticker?.cancel();
    while (_inFlight) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    await _poll();
    if (!_done && mounted) {
      NafathLog.warn(_tag, 'timed out waiting for approval');
      _fail(S.of(context).nafathExpired);
    }
  }

  // ----------------------------------------------------------------- polling

  Future<void> _poll() async {
    if (_inFlight || _done || !mounted) return;
    _inFlight = true;
    final local = S.of(context);
    try {
      final status = await _api.checkMfaStatus(_request.requestId);
      if (!mounted || _done) return;
      _quietErrors = 0;
      if (_connectionIssue) setState(() => _connectionIssue = false);

      if (status.isPending) {
        if (status.random != null && status.random != _random) {
          setState(() => _random = status.random);
        }
        return;
      }

      if (status.isFailure) {
        final message = status.message?.trim();
        _fail(message != null && message.isNotEmpty
            ? message
            : status.reason?.toLowerCase() == 'timeout'
                ? local.nafathExpired
                : local.nafathFailed);
        return;
      }

      if (!status.isSuccess) {
        _fail(local.nafathFailed);
        return;
      }

      // `success` is returned once only: stop everything and save it now.
      _done = true;
      _ticker?.cancel();
      setState(() => _phase = _Phase.finalizing);
      await NafathSessionStore.persist(status);
      NafathLog.info(_tag, 'login complete');
      if (mounted) Navigator.of(context).pop(const NafathResult.success());
    } on NafathException catch (error) {
      _onPollError(error.message);
    } catch (error, stackTrace) {
      NafathLog.error(_tag, 'status check failed', error, stackTrace);
      _onPollError('$error');
    } finally {
      _inFlight = false;
    }
  }

  void _onPollError(String reason) {
    if (!mounted || _done) return;
    _quietErrors++;
    NafathLog.warn(_tag, 'status check failed ($_quietErrors): $reason');
    if (_quietErrors >= _maxQuietErrors && !_connectionIssue) {
      setState(() => _connectionIssue = true);
    }
  }

  void _fail(String message) {
    if (!mounted || (_done && _phase == _Phase.failed)) return;
    _done = true;
    _ticker?.cancel();
    setState(() {
      _phase = _Phase.failed;
      _message = message;
    });
  }

  // ----------------------------------------------------------------- actions

  Future<void> _retry() async {
    NafathLog.info(_tag, 'retrying with a new request');
    setState(() {
      _phase = _Phase.finalizing;
      _message = null;
    });
    try {
      final request = await _api.requestMfa(
        nationalId: widget.nationalId,
        locale: widget.locale,
      );
      if (!mounted) return;
      setState(() => _begin(request));
    } on NafathException catch (error) {
      _done = false;
      _fail(error.statusCode != null
          ? error.message
          : S.of(context).nafathUnavailable);
    } catch (error, stackTrace) {
      NafathLog.error(_tag, 'retry failed', error, stackTrace);
      _done = false;
      if (mounted) _fail(S.of(context).nafathUnavailable);
    }
  }

  Future<void> _openNafath() async {
    final isIos = defaultTargetPlatform == TargetPlatform.iOS;
    final link = isIos
        ? (_request.iosDeepLink ?? nafathIosDeepLink)
        : (_request.androidDeepLink ?? nafathAndroidDeepLink);
    NafathLog.info(_tag, 'opening Nafath app');

    var opened = false;
    try {
      opened = await launchUrl(
        Uri.parse(link),
        mode: LaunchMode.externalApplication,
      );
    } catch (error) {
      NafathLog.warn(_tag, 'deep link failed: $error');
    }

    if (!opened && mounted) {
      final store = isIos ? nafathAppStoreUrl : nafathPlayStoreUrl;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(S.of(context).nafathNotInstalled),
          backgroundColor: redColor,
          action: SnackBarAction(
            label: S.of(context).nafathDownloadApp,
            textColor: Colors.white,
            onPressed: () => launchUrl(
              Uri.parse(store),
              mode: LaunchMode.externalApplication,
            ),
          ),
        ),
      );
    }
  }

  void _cancel() {
    NafathLog.info(_tag, 'cancelled by user');
    _done = true;
    _ticker?.cancel();
    Navigator.of(context).pop();
  }

  // -------------------------------------------------------------------- view

  String get _countdown {
    final minutes = (_remaining ~/ 60).toString();
    final seconds = (_remaining % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final local = S.of(context);
    return Scaffold(
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
      ),
      body: SafeArea(
        child: switch (_phase) {
          _Phase.waiting => _buildWaiting(local),
          _Phase.finalizing => _buildFinalizing(local),
          _Phase.failed => _buildFailed(local),
        },
      ),
    );
  }

  Widget _buildWaiting(S local) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            local.nafathChooseNumber,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 24),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _random ?? '--',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 84,
                fontWeight: FontWeight.bold,
                letterSpacing: 4,
              ),
            ),
          ),
          const SizedBox(height: 20),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _lifetime == 0 ? 0 : _remaining / _lifetime,
              minHeight: 4,
              color: nafathColor,
              backgroundColor: Colors.grey.shade200,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _countdown,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 28),
          SizedBox(
            height: 50,
            child: ElevatedButton(
              onPressed: _openNafath,
              style: ElevatedButton.styleFrom(
                backgroundColor: nafathColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                local.nafathOpenApp,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _connectionIssue ? local.nafathConnectionIssue : local.nafathWaiting,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: _connectionIssue ? redColor : Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFinalizing(S local) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 20),
          Text(local.nafathCompleting, style: const TextStyle(fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildFailed(S local) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 48, color: Colors.grey.shade500),
          const SizedBox(height: 16),
          Text(
            _message ?? local.nafathFailed,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _retry,
              style: ElevatedButton.styleFrom(
                backgroundColor: nafathColor,
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
    );
  }
}
