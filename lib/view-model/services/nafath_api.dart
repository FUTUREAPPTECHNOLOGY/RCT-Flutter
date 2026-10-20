import 'package:dio/dio.dart';
import 'package:rct/constants/linkapi.dart';
import 'package:rct/services/cache_helper.dart';
import 'package:rct/view-model/services/nafath_logger.dart';

const String _tag = 'NafathApi';

/// Hosts the Nafath WebView is permitted to navigate to.
const String nafathReturnHost = 'rctapp.com';
const Set<String> nafathAllowedHosts = {
  'rctapp.com',
  'www.rctapp.com',
  'iam.gov.sa',
  'www.iam.gov.sa',
  'nafath.api.elm.sa',
};

class NafathSessionResponse {
  final String nafathUrl;
  final String requestId;
  final DateTime? expiresAt;

  NafathSessionResponse({
    required this.nafathUrl,
    required this.requestId,
    this.expiresAt,
  });

  factory NafathSessionResponse.fromJson(Map<String, dynamic> json) {
    final url = json['nafath_url'];
    final requestId = json['request_id'];
    if (url is! String || url.isEmpty) {
      throw const NafathException('Session response is missing nafath_url.');
    }
    if (requestId is! String || requestId.isEmpty) {
      throw const NafathException('Session response is missing request_id.');
    }
    return NafathSessionResponse(
      nafathUrl: url,
      requestId: requestId,
      expiresAt: _parseDate(json['expires_at']),
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }
}

class NafathStatusResponse {
  final String status;
  final String? token;
  final Map<String, dynamic>? user;
  final String? reason;
  final String? message;

  NafathStatusResponse({
    required this.status,
    this.token,
    this.user,
    this.reason,
    this.message,
  });

  bool get isSuccess =>
      status.toLowerCase() == 'success' && (token?.isNotEmpty ?? false);

  bool get isPending {
    final normalised = status.toLowerCase();
    return normalised == 'pending' || normalised == 'waiting';
  }

  bool get isFailure => status.toLowerCase() == 'failure';

  factory NafathStatusResponse.fromJson(Map<String, dynamic> json) {
    return NafathStatusResponse(
      status: (json['status'] ?? 'unknown').toString(),
      token: json['token'] is String ? json['token'] as String : null,
      user: json['user'] is Map
          ? Map<String, dynamic>.from(json['user'] as Map)
          : null,
      reason: json['reason']?.toString(),
      message: json['message']?.toString(),
    );
  }
}

/// A failure the UI can show to the user without leaking transport details.
class NafathException implements Exception {
  final String message;
  const NafathException(this.message);

  @override
  String toString() => 'NafathException: $message';
}

class NafathApi {
  NafathApi({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 20),
              receiveTimeout: const Duration(seconds: 20),
              sendTimeout: const Duration(seconds: 20),
            ));

  final Dio _dio;

  Options _options() => Options(
        headers: {
          'Accept': 'application/json',
          'Accept-Language': _language(),
        },
        validateStatus: (status) => status != null && status < 500,
      );

  /// [CacheHelper.sharedPreferences] is a `late` field, so reading it before
  /// the app has initialised throws. Falling back to Arabic is always better
  /// than failing the whole login over a header.
  static String _language() {
    try {
      final value = CacheHelper.getData(key: 'lang');
      return value is String && value.isNotEmpty ? value : 'ar';
    } catch (_) {
      return 'ar';
    }
  }

  Future<NafathSessionResponse> createSession({String locale = 'ar'}) async {
    NafathLog.info(_tag, 'createSession → locale=$locale');
    try {
      final response = await _dio.get(
        linkNafathSession,
        queryParameters: {'locale': locale},
        options: _options(),
      );
      _logResponse('createSession', response);

      if (response.statusCode == 200 && response.data is Map) {
        final session = NafathSessionResponse.fromJson(
          Map<String, dynamic>.from(response.data as Map),
        );
        NafathLog.info(
          _tag,
          'createSession ok → requestId=${NafathLog.mask(session.requestId)}, '
          'authorizeHost=${Uri.tryParse(session.nafathUrl)?.host ?? '<unknown>'}, '
          'expiresAt=${session.expiresAt?.toIso8601String() ?? '<absent>'}',
        );
        return session;
      }

      throw NafathException(
        'Could not start Nafath (HTTP ${response.statusCode}).',
      );
    } on DioException catch (error, stackTrace) {
      NafathLog.error(_tag, 'createSession failed', error.type, stackTrace);
      throw const NafathException('Could not reach the Nafath service.');
    }
  }

  Future<NafathStatusResponse> checkStatus(String requestId) async {
    NafathLog.info(
      _tag,
      'checkStatus → requestId=${NafathLog.mask(requestId)}',
    );
    try {
      final response = await _dio.get(
        '$linkNafathStatus/$requestId',
        options: _options(),
      );
      _logResponse('checkStatus', response);

      if (response.statusCode == 200 && response.data is Map) {
        return NafathStatusResponse.fromJson(
          Map<String, dynamic>.from(response.data as Map),
        );
      }

      throw NafathException(
        'Could not confirm Nafath login (HTTP ${response.statusCode}).',
      );
    } on DioException catch (error, stackTrace) {
      NafathLog.error(_tag, 'checkStatus failed', error.type, stackTrace);
      throw const NafathException('Could not reach the Nafath service.');
    }
  }

  void _logResponse(String operation, Response<dynamic> response) {
    NafathLog.info(
      _tag,
      '$operation ← HTTP ${response.statusCode} '
      'body=${NafathLog.data(response.data)}',
    );
  }
}
