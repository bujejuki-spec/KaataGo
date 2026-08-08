import 'package:flutter/material.dart';

import '../theme.dart';

/// KaataGo's mark: a fork & spoon, drawn as vector shapes (no image asset
/// needed) so it stays crisp at any size and can be reused for the splash
/// badge, app bar, etc. Matches assets/icon/kaata_icon.png (the app's
/// home-screen launcher icon) so the brand looks the same everywhere.
///
/// [size] is the outer square badge size — the cutlery scale with it
/// automatically.
class KaataLogo extends StatelessWidget {
  final double size;
  final bool showBadgeBackground;

  const KaataLogo({super.key, this.size = 96, this.showBadgeBackground = true});

  @override
  Widget build(BuildContext context) {
    final mark = CustomPaint(
      size: Size.square(size),
      painter: _KaataLogoPainter(),
    );

    if (!showBadgeBackground) return mark;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [KaataTheme.brand, KaataTheme.brandDark],
        ),
        borderRadius: BorderRadius.circular(size * 0.29),
        boxShadow: [
          BoxShadow(
            color: KaataTheme.brand.withOpacity(0.35),
            blurRadius: size * 0.25,
            offset: Offset(0, size * 0.1),
          ),
        ],
      ),
      child: mark,
    );
  }
}

class _KaataLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final cx = w / 2;
    final white = Paint()..color = Colors.white;

    void capLine(double x1, double y1, double x2, double y2, double width) {
      final paint = Paint()
        ..color = Colors.white
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(x1, y1), Offset(x2, y2), paint);
    }

    final top = w * 0.22;
    final bottom = w * 0.78;
    final handleWidth = w * 0.052;

    // --- Fork (left) ---
    final forkX = cx - w * 0.115;
    final tineBottom = w * 0.42;
    capLine(forkX, tineBottom, forkX, bottom, handleWidth);
    for (final dx in [-0.05, 0.0, 0.05]) {
      capLine(forkX + w * dx, top, forkX + w * dx, tineBottom + w * 0.015, w * 0.034);
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(
          forkX - w * 0.05 - handleWidth / 2,
          tineBottom - w * 0.01,
          forkX + w * 0.05 + handleWidth / 2,
          tineBottom + w * 0.035,
        ),
        Radius.circular(w * 0.02),
      ),
      white,
    );

    // --- Spoon (right) ---
    final spoonX = cx + w * 0.115;
    final bowlCenterY = top + w * 0.10;
    final bowlW = w * 0.165;
    final bowlH = w * 0.215;
    canvas.drawOval(
      Rect.fromCenter(center: Offset(spoonX, bowlCenterY), width: bowlW, height: bowlH),
      white,
    );
    capLine(spoonX, bowlCenterY + bowlH / 2 - w * 0.01, spoonX, bottom, handleWidth);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
