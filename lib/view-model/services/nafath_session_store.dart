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
    if (name != null) await secureStorage.write(key: 'name', value: name);
    if (image != null) await secureStorage.write(key: 'image', value: image);

    await AppPreferences.saveData(key: 'loginToken', value: token);
    if (name != null) {
      await AppPreferences.saveData(key: 'username', value: name);
    }
    if (phone != null) {
      await AppPreferences.saveData(key: 'phone', value: phone);
    }
    if (image != null) {
      await AppPreferences.saveData(key: 'image', value: image);
    }
    if (email != null) {
      await AppPreferences.saveData(key: 'email', value: email);
    }

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
}
