import 'package:flutter/material.dart';

/// The teal-green used across the Nafath screens.
const Color nafathColor = Color(0xFF468285);

/// "Download on the App Store" / "GET IT ON Google Play" badge.
class NafathStoreBadge extends StatelessWidget {
  final bool apple;
  final VoidCallback onTap;

  const NafathStoreBadge({Key? key, required this.apple, required this.onTap})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: apple ? 'App Store' : 'Google Play',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(7),
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: Colors.grey.shade500, width: 0.8),
          ),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (apple)
                  const Icon(Icons.apple, color: Colors.white, size: 26)
                else
                  const SizedBox(
                    width: 22,
                    height: 24,
                    child: CustomPaint(painter: _GooglePlayPainter()),
                  ),
                const SizedBox(width: 7),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      apple ? 'Download on the' : 'GET IT ON',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 8,
                        height: 1.1,
                      ),
                    ),
                    Text(
                      apple ? 'App Store' : 'Google Play',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        height: 1.1,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The four-colour Google Play triangle.
class _GooglePlayPainter extends CustomPainter {
  const _GooglePlayPainter();

  @override
  void paint(Canvas canvas, Size size) {
    Offset p(double x, double y) =>
        Offset(x / 24 * size.width, y / 24 * size.height);

    final a = p(1, 1), b = p(1, 23), c = p(13, 12);
    final d = p(17, 9.1), e = p(17, 14.9), f = p(22.5, 12);

    void fill(List<Offset> points, Color color) {
      final path = Path()..addPolygon(points, true);
      canvas.drawPath(path, Paint()..color = color..isAntiAlias = true);
    }

    fill([a, b, c], const Color(0xFF00A0FF));
    fill([a, d, c], const Color(0xFF00E676));
    fill([d, f, e, c], const Color(0xFFFFD500));
    fill([b, c, e], const Color(0xFFFF3A44));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
