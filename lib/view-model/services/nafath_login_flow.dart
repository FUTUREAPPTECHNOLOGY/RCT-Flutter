import 'package:flutter/material.dart';
import 'package:rct/constants/constants.dart';
import 'package:rct/generated/l10n.dart';
import 'package:rct/services/cache_helper.dart';
import 'package:rct/view-model/functions/snackbar.dart';
import 'package:rct/view-model/services/nafath_api.dart';
import 'package:rct/view-model/services/nafath_logger.dart';
import 'package:rct/view/auth/nafath_webview_screen.dart';
import 'package:rct/view/home_screen.dart';

const String _tag = 'NafathFlow';

/// The single entry point for Nafath login.
///
/// Both the phone-entry screen and the OTP screen call this, so the sequence
/// (create session → authorize → land on home) lives in exactly one place and
/// does not depend on where in the navigation stack it was launched from.
class NafathLoginFlow {
  const NafathLoginFlow._();

  static Future<bool> start(
    BuildContext context, {
    ValueChanged<bool>? onBusy,
    NafathApi? api,
  }) async {
    final client = api ?? NafathApi();
    final locale = CacheHelper.getData(key: 'lang') == 'en' ? 'en' : 'ar';

    onBusy?.call(true);
    NafathSessionResponse session;
    try {
      session = await client.createSession(locale: locale);
    } on NafathException catch (error) {
      NafathLog.warn(_tag, 'could not start: ${error.message}');
      if (context.mounted) {
        showSnackBar(context, S.of(context).nafathUnavailable, redColor);
      }
      return false;
    } catch (error, stackTrace) {
      NafathLog.error(_tag, 'could not start', error, stackTrace);
      if (context.mounted) {
        showSnackBar(context, S.of(context).nafathUnavailable, redColor);
      }
      return false;
    } finally {
      onBusy?.call(false);
    }

    if (!context.mounted) return false;

    final result = await Navigator.of(context).push<NafathWebViewResult>(
      MaterialPageRoute(
        builder: (_) => NafathWebViewScreen(
          session: session,
          locale: locale,
          api: client,
        ),
      ),
    );

    if (result?.authenticated != true) {
      NafathLog.info(_tag, 'flow ended without authentication');
      final errorMessage = result?.errorMessage;
      if (context.mounted &&
          errorMessage != null &&
          errorMessage.trim().isNotEmpty) {
        showSnackBar(context, errorMessage, redColor);
      }
      return false;
    }

    // Own the destination here rather than popping a result up an unknown
    // stack: the phone-entry screen is often the root, so there is nothing to
    // pop back to and the user would otherwise be left logged in but stranded.
    if (context.mounted) {
      NafathLog.info(_tag, 'authenticated, going to home');
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => HomeScreen()),
        (route) => false,
      );
    }
    return true;
  }
}
