import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:rct/constants/linkapi.dart';
import 'package:rct/services/cache_helper.dart';

class NafathSessionResponse {
  final String nafathUrl;
  final String requestId;

  NafathSessionResponse({required this.nafathUrl, required this.requestId});

  factory NafathSessionResponse.fromJson(Map<String, dynamic> json) {
    return NafathSessionResponse(
      nafathUrl: json['nafath_url'] as String,
      requestId: json['request_id'] as String,
    );
  }
}

class NafathStatusResponse {
  final String status;
  final String? token;
  final Map<String, dynamic>? user;

  NafathStatusResponse({required this.status, this.token, this.user});

  factory NafathStatusResponse.fromJson(Map<String, dynamic> json) {
    return NafathStatusResponse(
      status: json['status'] as String,
      token: json['token'] as String?,
      user: json['user'] is Map<String, dynamic>
          ? json['user'] as Map<String, dynamic>
          : null,
    );
  }
}

class NafathApi {
  final Dio _dio = Dio();

  Future<NafathSessionResponse> createSession({String locale = 'ar'}) async {
    _log('Calling create session: locale=$locale');
    final response = await _dio.get(
      linkNafathSession,
      queryParameters: {'locale': locale},
      options: Options(headers: {
        'Accept': 'application/json',
        'Accept-Language': CacheHelper.getData(key: 'lang') ?? 'ar',
      }),
    );
    _logResponse('create session', response);

    if (response.statusCode == 200) {
      return NafathSessionResponse.fromJson(
          response.data as Map<String, dynamic>);
    }

    throw Exception('Failed to create Nafath session: ${response.statusCode}');
  }

  Future<NafathStatusResponse> checkStatus(String requestId) async {
    _log('Calling check status: requestId=${_mask(requestId)}');
    final response = await _dio.get(
      '$linkNafathStatus/$requestId',
      options: Options(headers: {
        'Accept': 'application/json',
        'Accept-Language': CacheHelper.getData(key: 'lang') ?? 'ar',
      }),
    );
    _logResponse('check status', response);

    if (response.statusCode == 200) {
      return NafathStatusResponse.fromJson(
          response.data as Map<String, dynamic>);
    }

    throw Exception('Failed to get Nafath status: ${response.statusCode}');
  }

  void _logResponse(String operation, Response<dynamic> response) {
    debugPrint(
      '[NafathApi] $operation response: '
      'statusCode=${response.statusCode}, data=${_sanitizeData(response.data)}',
    );
  }

  dynamic _sanitizeData(dynamic data) {
    if (data is Map) {
      return data.map(
        (key, value) => MapEntry(
          key,
          key.toString().toLowerCase() == 'token'
              ? '<redacted>'
              : _sanitizeData(value),
        ),
      );
    }
    if (data is Iterable) {
      return data.map(_sanitizeData).toList();
    }
    return data;
  }

  void _log(String message) {
    debugPrint('[NafathApi] $message');
  }

  String _mask(String value) {
    if (value.length <= 4) return '****';
    return '${value.substring(0, 2)}****${value.substring(value.length - 2)}';
  }
}
