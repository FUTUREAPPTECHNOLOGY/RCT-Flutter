import 'package:rct/main.dart';
import 'package:rct/shared_pref.dart';
import 'package:rct/view-model/services/nafath_api.dart';
import 'package:rct/view-model/services/nafath_logger.dart';

const String _tag = 'NafathStore';

/// Writes an authenticated Nafath session to storage.
///
/// This mirrors what the OTP path in [LogiScreen] persists, so the rest of the
/// app (home screen, profile, drawer) finds the same keys regardless of which
/// login method was used.
class NafathSessionStore {
  const NafathSessionStore._();

  static Future<void> persist(NafathStatusResponse status) async {
    final token = status.token;
    if (token == null || token.isEmpty) {
      throw const NafathException('Nafath did not return a session token.');
    }

    final user = status.user ?? const <String, dynamic>{};
    final name = _stringOrNull(user['name']);
    final phone = _stringOrNull(user['phone']);
    final image = _stringOrNull(user['image']);
    final email = _stringOrNull(user['email']);

    await secureStorage.write(key: 'token', value: token);
    await _writeOrClear(secure: 'name', prefs: 'username', value: name);
    await _writeOrClear(secure: 'image', prefs: 'image', value: image);
    await _writeOrClear(prefs: 'phone', value: phone);
    await _writeOrClear(prefs: 'email', value: email);
    await AppPreferences.saveData(key: 'loginToken', value: token);

    NafathLog.info(
      _tag,
      'session persisted → hasName=${name != null}, hasPhone=${phone != null}, '
      'hasImage=${image != null}, hasEmail=${email != null}',
    );
  }

  static String? _stringOrNull(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty || text == 'null' ? null : text;
  }

  /// Saves [value], or removes the old one when the response has none, so a
  /// previous user's name or photo never shows under the new session.
  static Future<void> _writeOrClear({
    String? secure,
    String? prefs,
    String? value,
  }) async {
    if (value != null) {
      if (secure != null) await secureStorage.write(key: secure, value: value);
      if (prefs != null) {
        await AppPreferences.saveData(key: prefs, value: value);
      }
      return;
    }
    if (secure != null) await secureStorage.delete(key: secure);
    if (prefs != null) await AppPreferences.removeDate(key: prefs);
  }
}
