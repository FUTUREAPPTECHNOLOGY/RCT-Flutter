import 'package:flutter/material.dart';
import 'package:rct/constants/constants.dart';
import 'package:rct/generated/l10n.dart';
import 'package:rct/services/cache_helper.dart';
import 'package:rct/view-model/functions/snackbar.dart';
import 'package:rct/view-model/services/nafath_api.dart';
import 'package:rct/view-model/services/nafath_logger.dart';
import 'package:rct/view/auth/nafath_id_screen.dart';
import 'package:rct/view/auth/nafath_waiting_screen.dart';
import 'package:rct/view/home_screen.dart';

const String _tag = 'NafathFlow';

/// The single entry point for Nafath login.
///
/// Both the phone-entry screen and the OTP screen call this, so the sequence
/// (send ID → show number → wait for approval → land on home) lives in exactly one place and
/// does not depend on where in the navigation stack it was launched from.
class NafathLoginFlow {
  const NafathLoginFlow._();

  /// Entry point: shows the ID step, which then calls [run].
  static Future<void> start(BuildContext context) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const NafathIdScreen()),
    );
  }

  /// Sends the ID to `mfa/request`, waits for approval in the Nafath app, then
  /// goes home.
  static Future<bool> run(
    BuildContext context, {
    required String nationalId,
    ValueChanged<bool>? onBusy,
    NafathApi? api,
  }) async {
    final client = api ?? NafathApi();
    final locale = CacheHelper.getData(key: 'lang') == 'en' ? 'en' : 'ar';

    onBusy?.call(true);
    NafathMfaResponse mfa;
    try {
      mfa = await client.requestMfa(
        nationalId: nationalId,
        locale: locale,
      );
      NafathLog.info(
        _tag,
        'mfa request ok → requestId=${NafathLog.mask(mfa.requestId)}',
      );
    } on NafathException catch (error) {
      NafathLog.warn(_tag, 'could not start: ${error.message}');
      if (context.mounted) {
        // The backend sends a ready-to-show message for 422/409/429/502.
        final shown = error.statusCode != null
            ? error.message
            : S.of(context).nafathUnavailable;
        showSnackBar(context, shown, redColor);
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

    final result = await Navigator.of(context).push<NafathResult>(
      MaterialPageRoute(
        builder: (_) => NafathWaitingScreen(
          request: mfa,
          nationalId: nationalId,
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
