import 'package:flutter/material.dart';

/// The "تسجيل الدخول عبر نفاذ" button, with the trailing word highlighted.
class NafathButton extends StatelessWidget {
  final String text;
  final VoidCallback? onTap;

  const NafathButton({Key? key, required this.text, this.onTap})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    final tokens = text.trim().split(' ');
    final leading = tokens.length > 1
        ? tokens.sublist(0, tokens.length - 1).join(' ')
        : text;
    final highlight = tokens.length > 1 ? tokens.last : '';

    return Semantics(
      button: true,
      label: text,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 45,
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: leading.isNotEmpty ? '$leading ' : '',
                  style: const TextStyle(
                    color: Colors.black87,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                TextSpan(
                  text: highlight,
                  style: const TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
