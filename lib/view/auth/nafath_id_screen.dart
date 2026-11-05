import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rct/generated/l10n.dart';
import 'package:rct/view-model/services/nafath_api.dart';
import 'package:rct/view-model/services/nafath_login_flow.dart';
import 'package:rct/view/auth/nafath_style.dart';
import 'package:url_launcher/url_launcher.dart';

/// National ID (1), iqama (2) or visitor/border number (3-6, 9): 10 digits.
final RegExp _idPattern = RegExp(r'^[1-69]\d{9}$');

/// First step of Nafath login: collect the ID, then hand over to the flow.
class NafathIdScreen extends StatefulWidget {
  const NafathIdScreen({Key? key}) : super(key: key);

  @override
  State<NafathIdScreen> createState() => _NafathIdScreenState();
}

class _NafathIdScreenState extends State<NafathIdScreen> {
  final _formKey = GlobalKey<FormState>();
  final _controller = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    await NafathLoginFlow.run(
      context,
      nationalId: _controller.text.trim(),
      onBusy: (busy) {
        if (mounted) setState(() => _busy = busy);
      },
    );
  }

  Future<void> _open(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  /// "Login with Nafath" with the last word in the Nafath colour.
  Widget _subtitle(String text) {
    final words = text.trim().split(' ');
    final lead = words.length > 1
        ? '${words.sublist(0, words.length - 1).join(' ')} '
        : '';
    final highlight = words.last;
    return Text.rich(
      TextSpan(
        text: lead,
        style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
        children: [
          TextSpan(
            text: highlight,
            style: const TextStyle(
                color: nafathColor, fontWeight: FontWeight.bold),
          ),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }

  @override
  Widget build(BuildContext context) {
    final local = S.of(context);
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Image.asset('assets/images/logo.png', height: 70),
                const SizedBox(height: 50),
                Text(local.login,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                _subtitle(local.nafathIdSubtitle),
                const SizedBox(height: 40),
                TextFormField(
                  controller: _controller,
                  enabled: !_busy,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  maxLength: 10,
                  onFieldSubmitted: (_) => _submit(),
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: (v) => _idPattern.hasMatch(v?.trim() ?? '')
                      ? null
                      : local.nafathIdInvalid,
                  style: const TextStyle(fontSize: 15, letterSpacing: 1),
                  decoration: InputDecoration(
                    labelText: local.nafathIdLabel,
                    labelStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87),
                    floatingLabelBehavior: FloatingLabelBehavior.always,
                    hintText: '1012345678',
                    hintStyle: TextStyle(color: Colors.grey.shade400),
                    counterText: '',
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 22),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide:
                          const BorderSide(color: nafathColor, width: 1.5),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _busy ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: nafathColor,
                      disabledBackgroundColor: nafathColor.withOpacity(0.6),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: _busy
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : Text(local.nafathContinue,
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(height: 40),
                Text(local.nafathDownloadApp,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade600)),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    NafathStoreBadge(
                        apple: true, onTap: () => _open(nafathAppStoreUrl)),
                    const SizedBox(width: 14),
                    NafathStoreBadge(
                        apple: false, onTap: () => _open(nafathPlayStoreUrl)),
                  ],
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
