import 'package:dio/dio.dart';
import 'package:rct/constants/linkapi.dart';
import 'package:rct/services/cache_helper.dart';
import 'package:rct/view-model/services/nafath_logger.dart';

const String _tag = 'NafathApi';

const String nafathPlayStoreUrl =
    'https://play.google.com/store/apps/details?id=sa.gov.nic.myid';
const String nafathAppStoreUrl =
    'https://apps.apple.com/sa/app/%D9%86%D9%81%D8%A7%D8%B0-nafath/id1598909871';

/// Used when the backend does not send `deep_links`.
const String nafathIosDeepLink = 'nafath://home';
const String nafathAndroidDeepLink = 'nic://nafath';

/// Reply to `POST /api/nafath/mfa/request`.
class NafathMfaResponse {
  final String requestId;
  final String? random;
  final int? expiresIn;
  final String? iosDeepLink;
  final String? androidDeepLink;

  NafathMfaResponse({
    required this.requestId,
    this.random,
    this.expiresIn,
    this.iosDeepLink,
    this.androidDeepLink,
  });

  factory NafathMfaResponse.fromJson(Map<String, dynamic> json) {
    final requestId = json['request_id'];
    if (requestId is! String || requestId.isEmpty) {
      throw const NafathException('Response is missing request_id.');
    }
    final links = json['deep_links'] is Map
        ? Map<String, dynamic>.from(json['deep_links'] as Map)
        : const <String, dynamic>{};
    return NafathMfaResponse(
      requestId: requestId,
      random: json['random']?.toString(),
      expiresIn: json['expires_in'] is int ? json['expires_in'] as int : null,
      iosDeepLink: links['ios']?.toString(),
      androidDeepLink: links['android']?.toString(),
    );
  }
}

class NafathStatusResponse {
  final String status;
  final String? token;
  final Map<String, dynamic>? user;
  final String? reason;
  final String? message;
  final String? random;

  NafathStatusResponse({
    required this.status,
    this.token,
    this.user,
    this.reason,
    this.message,
    this.random,
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
      random: json['random']?.toString(),
    );
  }
}

/// A failure the UI can show to the user without leaking transport details.
class NafathException implements Exception {
  final String message;
  final int? statusCode;
  const NafathException(this.message, {this.statusCode});

  /// An active Nafath request already exists for this ID.
  bool get isConflict => statusCode == 409;

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

  /// Sends the national ID to the backend, which creates the Nafath request.
  /// Server messages (422 / 409 / 429 / 502) are carried on the exception.
  Future<NafathMfaResponse> requestMfa({
    required String nationalId,
    String locale = 'ar',
  }) async {
    NafathLog.info(_tag, 'requestMfa → locale=$locale');
    try {
      final response = await _dio.post(
        linkNafathMfaRequest,
        data: {'national_id': nationalId, 'locale': locale},
        options: Options(
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            'Accept-Language': _language(),
          },
          validateStatus: (status) => status != null && status < 600,
        ),
      );
      _logResponse('requestMfa', response);

      final body = response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : const <String, dynamic>{};
      if (response.statusCode == 200) {
        return NafathMfaResponse.fromJson(body);
      }
      throw NafathException(
        body['message']?.toString() ??
            'Could not start Nafath (HTTP ${response.statusCode}).',
        statusCode: response.statusCode,
      );
    } on DioException catch (error, stackTrace) {
      NafathLog.error(_tag, 'requestMfa failed', error.type, stackTrace);
      throw const NafathException('Could not reach the Nafath service.');
    }
  }

  /// One status check for an MFA request. The backend always answers 200 with
  /// `pending`, `success` (returned once) or `failure`.
  Future<NafathStatusResponse> checkMfaStatus(String requestId) async {
    NafathLog.info(
      _tag,
      'checkMfaStatus → requestId=${NafathLog.mask(requestId)}',
    );
    try {
      final response = await _dio.get(
        '$linkNafathMfaStatus/$requestId',
        options: _options(),
      );
      _logResponse('checkMfaStatus', response);

      if (response.statusCode == 200 && response.data is Map) {
        return NafathStatusResponse.fromJson(
          Map<String, dynamic>.from(response.data as Map),
        );
      }

      throw NafathException(
        'Could not confirm Nafath login (HTTP ${response.statusCode}).',
        statusCode: response.statusCode,
      );
    } on DioException catch (error, stackTrace) {
      NafathLog.error(_tag, 'checkMfaStatus failed', error.type, stackTrace);
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
