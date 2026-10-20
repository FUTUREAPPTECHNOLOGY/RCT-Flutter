import 'package:flutter/foundation.dart';

/// Centralised, redacting logger for the Nafath authentication flow.
///
/// Nothing here logs in release builds. In debug builds every value that could
/// identify a user or be replayed against the identity provider is redacted
/// before it reaches the console.
class NafathLog {
  const NafathLog._();

  /// Query parameters that are safe to print in full. Anything not listed here
  /// is redacted, so a new parameter added by the backend leaks nothing.
  static const Set<String> _visibleQueryKeys = {
    'status',
    'result',
    'success',
    'error',
    'error_code',
    'error_description',
    'message',
    'reason',
    'locale',
    'lang',
    'ui_locales',
  };

  /// Map keys whose values are never printed.
  static const Set<String> _redactedDataKeys = {
    'token',
    'id_token',
    'access_token',
    'refresh_token',
    'code',
    'state',
    'nonce',
    'password',
    'secret',
    'authorization',
    'nafath_url',
    'redirect_uri',
    'national_id',
    'nationalid',
    'iqama',
    'phone',
    'email',
  };

  static void info(String tag, String message) => _emit(tag, 'INFO', message);

  static void warn(String tag, String message) => _emit(tag, 'WARN', message);

  static void error(String tag, String message,
      [Object? error, StackTrace? stackTrace]) {
    _emit(tag, 'ERROR', error == null ? message : '$message: $error');
    if (stackTrace != null && !kReleaseMode) {
      debugPrintStack(label: '[$tag]', stackTrace: stackTrace);
    }
  }

  static void _emit(String tag, String level, String message) {
    if (kReleaseMode) return;
    debugPrint('[$tag] $level $message');
  }

  /// Renders a URL as `scheme://host/path?safe=value&sensitive=<redacted>`.
  ///
  /// Parameter *names* are always kept because they are what tells us the shape
  /// of an unknown callback; only the values are withheld.
  static String url(String? raw) {
    if (raw == null) return '<null>';
    final uri = Uri.tryParse(raw);
    if (uri == null) return '<unparseable url>';

    final base = Uri(
      scheme: uri.scheme.isEmpty ? null : uri.scheme,
      host: uri.host.isEmpty ? null : uri.host,
      port: uri.hasPort ? uri.port : null,
      path: uri.path,
    ).toString();

    if (uri.queryParameters.isEmpty) return base;

    final rendered = uri.queryParameters.entries.map((entry) {
      final key = entry.key.toLowerCase();
      final safe = _visibleQueryKeys.contains(key) &&
          !_redactedDataKeys.contains(key);
      return '${entry.key}=${safe ? entry.value : '<redacted>'}';
    }).join('&');

    return '$base?$rendered';
  }

  /// The query parameter names present on a URL, with no values at all.
  /// Useful for discovering the shape of a callback we do not control.
  static String queryKeys(Uri uri) {
    if (uri.queryParameters.isEmpty) return '<none>';
    return uri.queryParameters.keys.join(', ');
  }

  /// Recursively redacts sensitive entries out of a decoded response body.
  static dynamic data(dynamic value) {
    if (value is Map) {
      return value.map((key, child) {
        final isSensitive = _redactedDataKeys.contains(
          key.toString().toLowerCase(),
        );
        return MapEntry(key, isSensitive ? '<redacted>' : data(child));
      });
    }
    if (value is Iterable) return value.map(data).toList();
    return value;
  }

  /// Masks an identifier so log lines can still be correlated with each other.
  static String mask(String? value) {
    if (value == null || value.isEmpty) return '<empty>';
    if (value.length <= 8) return '****';
    return '${value.substring(0, 4)}…${value.substring(value.length - 4)}';
  }
}
