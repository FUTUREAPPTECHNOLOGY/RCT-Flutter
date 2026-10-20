import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rct/view-model/services/nafath_api.dart';
import 'package:rct/view-model/services/nafath_logger.dart';

/// Serves canned responses and records every path that was requested, so a
/// test can assert not just the outcome but how many calls it took.
class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this.handler);

  final ResponseBody Function(RequestOptions options) handler;
  final List<String> requestedPaths = [];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? stream,
      Future<void>? cancelFuture) async {
    requestedPaths.add(options.path);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Map<String, dynamic> body, {int status = 200}) {
  return ResponseBody.fromString(
    jsonEncode(body),
    status,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

NafathApi _apiWith(_RecordingAdapter adapter) {
  final dio = Dio();
  dio.httpClientAdapter = adapter;
  return NafathApi(dio: dio);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NafathSessionResponse', () {
    test('parses expires_at, which the UI needs for the timeout', () {
      final session = NafathSessionResponse.fromJson({
        'nafath_url': 'https://www.iam.gov.sa/authservice/authorize?state=abc',
        'request_id': '4e95759d-0006-48a4-b471-0b34f57e0fd6',
        'expires_at': '2026-09-11 09:37:04',
      });

      expect(session.requestId, '4e95759d-0006-48a4-b471-0b34f57e0fd6');
      expect(session.expiresAt, DateTime(2026, 9, 11, 9, 37, 4));
    });

    test('survives a missing expires_at', () {
      final session = NafathSessionResponse.fromJson({
        'nafath_url': 'https://www.iam.gov.sa/authservice/authorize',
        'request_id': 'abc',
      });
      expect(session.expiresAt, isNull);
    });

    test('rejects a response with no nafath_url', () {
      expect(
        () => NafathSessionResponse.fromJson({'request_id': 'abc'}),
        throwsA(isA<NafathException>()),
      );
    });
  });

  group('NafathStatusResponse', () {
    test('success requires a non-empty token', () {
      expect(
        NafathStatusResponse.fromJson({'status': 'success', 'token': 't'})
            .isSuccess,
        isTrue,
      );
      expect(
        NafathStatusResponse.fromJson({'status': 'success'}).isSuccess,
        isFalse,
      );
      expect(
        NafathStatusResponse.fromJson({'status': 'success', 'token': ''})
            .isSuccess,
        isFalse,
      );
    });

    test('recognises pending and rejected states', () {
      expect(
        NafathStatusResponse.fromJson({'status': 'PENDING'}).isPending,
        isTrue,
      );
      final rejected = NafathStatusResponse.fromJson({
        'status': 'rejected',
        'message': 'User declined',
      });
      expect(rejected.isPending, isFalse);
      expect(rejected.isSuccess, isFalse);
      expect(rejected.message, 'User declined');
    });

    test('recognises failure and preserves its reason and message', () {
      final failure = NafathStatusResponse.fromJson({
        'status': 'failure',
        'reason': 'timeout',
        'message': 'انتهت مهلة الجلسة. حاول مرة أخرى.',
      });

      expect(failure.isFailure, isTrue);
      expect(failure.isPending, isFalse);
      expect(failure.isSuccess, isFalse);
      expect(failure.reason, 'timeout');
      expect(failure.message, 'انتهت مهلة الجلسة. حاول مرة أخرى.');
    });

    test('keeps the user object so the profile can be persisted', () {
      final status = NafathStatusResponse.fromJson({
        'status': 'success',
        'token': 't',
        'user': {'name': 'Nada', 'phone': '0500000000'},
      });
      expect(status.user?['name'], 'Nada');
    });
  });

  group('NafathApi', () {
    test('createSession issues exactly one request', () async {
      final adapter = _RecordingAdapter((_) => _json({
            'nafath_url': 'https://www.iam.gov.sa/authservice/authorize',
            'request_id': 'req-1',
            'expires_at': '2026-09-11 09:37:04',
          }));

      final session = await _apiWith(adapter).createSession(locale: 'ar');

      expect(session.requestId, 'req-1');
      expect(adapter.requestedPaths, hasLength(1));
    });

    test('checkStatus issues exactly one request — no polling', () async {
      final adapter = _RecordingAdapter(
        (_) => _json({'status': 'success', 'token': 'secret-token'}),
      );

      final status = await _apiWith(adapter).checkStatus('req-1');

      expect(status.isSuccess, isTrue);
      expect(adapter.requestedPaths, hasLength(1));
      expect(adapter.requestedPaths.single, endsWith('/req-1'));
    });

    test('surfaces a 4xx as a NafathException, not a raw Dio error', () async {
      final adapter = _RecordingAdapter((_) => _json({}, status: 404));

      expect(
        () => _apiWith(adapter).checkStatus('req-1'),
        throwsA(isA<NafathException>()),
      );
    });

    test('surfaces a transport failure as a NafathException', () async {
      final adapter = _RecordingAdapter((options) {
        throw DioException.connectionTimeout(
          timeout: const Duration(seconds: 1),
          requestOptions: options,
        );
      });

      expect(
        () => _apiWith(adapter).createSession(),
        throwsA(isA<NafathException>()),
      );
    });
  });

  group('NafathLog redaction', () {
    test('keeps the URL shape but withholds the signed state blob', () {
      final rendered = NafathLog.url(
        'https://www.iam.gov.sa/authservice/authorize'
        '?state=lfOiE1zrjHpWwky&ui_locales=ar&nonce=b210f867',
      );

      expect(rendered, contains('www.iam.gov.sa/authservice/authorize'));
      expect(rendered, contains('state=<redacted>'));
      expect(rendered, contains('nonce=<redacted>'));
      expect(rendered, contains('ui_locales=ar'));
      expect(rendered, isNot(contains('lfOiE1zrjHpWwky')));
    });

    test('shows diagnostic parameters in full', () {
      final rendered = NafathLog.url(
        'https://rctapp.com/api/nafath/callback?status=success&error=none',
      );
      expect(rendered, contains('status=success'));
      expect(rendered, contains('error=none'));
    });

    test('redacts tokens and identifiers inside a response body', () {
      final sanitised = NafathLog.data({
        'status': 'success',
        'token': 'secret-token',
        'user': {'name': 'Nada', 'phone': '0500000000'},
      }) as Map;

      expect(sanitised['status'], 'success');
      expect(sanitised['token'], '<redacted>');
      expect((sanitised['user'] as Map)['name'], 'Nada');
      expect((sanitised['user'] as Map)['phone'], '<redacted>');
    });

    test('lists callback parameter names without their values', () {
      final uri = Uri.parse(
        'https://rctapp.com/api/nafath/callback?state=abc&id_token=xyz',
      );
      final keys = NafathLog.queryKeys(uri);

      expect(keys, 'state, id_token');
      expect(keys, isNot(contains('xyz')));
    });

    test('masks a request id but keeps it correlatable', () {
      final masked = NafathLog.mask('4e95759d-0006-48a4-b471-0b34f57e0fd6');
      expect(masked, '4e95…0fd6');
    });
  });

  group('host allowlist', () {
    test('permits the identity provider and our own host only', () {
      expect(nafathAllowedHosts.contains('www.iam.gov.sa'), isTrue);
      expect(nafathAllowedHosts.contains('nafath.api.elm.sa'), isTrue);
      expect(nafathAllowedHosts.contains('rctapp.com'), isTrue);
      expect(nafathAllowedHosts.contains('evil.example.com'), isFalse);
    });
  });
}
