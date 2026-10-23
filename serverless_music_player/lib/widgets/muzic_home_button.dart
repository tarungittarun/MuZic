import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// The MuZic app icon shown at the top-left of the main pages.
///
/// It redraws the exact launcher icon (dark disc, lavender + mint double
/// note from `res/mipmap-anydpi/ic_launcher.xml`) so what you tap in-app is
/// the same mark as on the home screen. Tapping it acts as Home; the icon
/// gives a short vibration-like shake (plus a light haptic) when tapped.
class MuZicHomeButton extends StatefulWidget {
  const MuZicHomeButton({required this.onPressed, super.key});

  final VoidCallback onPressed;

  @override
  State<MuZicHomeButton> createState() => _MuZicHomeButtonState();
}

class _MuZicHomeButtonState extends State<MuZicHomeButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 460),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTap() {
    _controller.forward(from: 0);
    // Best-effort: the shake remains visible even on devices with haptics off.
    HapticFeedback.lightImpact();
    widget.onPressed();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final progress = _controller.value;
        final shake = progress == 0 || progress == 1
            ? 0.0
            : math.sin(progress * math.pi * 6) * (1 - progress) * 0.16;
        final scale = 1 + math.sin(progress * math.pi) * 0.07;
        return Transform.rotate(
          angle: shake,
          child: Transform.scale(scale: scale, child: child),
        );
      },
      child: Tooltip(
        message: 'MuZic home',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _handleTap,
            customBorder: const CircleBorder(),
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: palette.accent.withValues(alpha: 0.28),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const CustomPaint(
                painter: _MuZicAppIconPainter(),
                size: Size(42, 42),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The MuZic launcher icon by itself (no tap behaviour), for places that
/// brand a surface with the app mark — e.g. the lock-screen-style media
/// card, which shows the app icon at its top-left just like Android's
/// system media player does.
class MuZicAppIcon extends StatelessWidget {
  const MuZicAppIcon({this.size = 42, super.key});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: const _MuZicAppIconPainter(),
        size: Size(size, size),
      ),
    );
  }
}

/// Paints the shipped launcher icon: a #11121B disc with the lavender and
/// mint double-note paths from the Android vector, scaled from its 48-unit
/// viewport, so it reads as the app icon rather than a generic note glyph.
class _MuZicAppIconPainter extends CustomPainter {
  const _MuZicAppIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 48;
    canvas.save();
    canvas.translate(
      (size.width - 48 * scale) / 2,
      (size.height - 48 * scale) / 2,
    );
    canvas.scale(scale, scale);
    canvas.drawCircle(
      const Offset(24, 24),
      24,
      Paint()..color = const Color(0xFF11121B),
    );
    final lavender = Path()
      ..moveTo(29, 8)
      ..lineTo(29, 30.5)
      ..arcToPoint(
        const Offset(25, 24.1),
        radius: const Radius.elliptical(7, 7),
        largeArc: true,
        clockwise: true,
      )
      ..lineTo(25, 12)
      ..lineTo(36, 9)
      ..lineTo(36, 14)
      ..lineTo(29, 16)
      ..close();
    canvas.drawPath(lavender, Paint()..color = const Color(0xFFB69CFF));
    final mint = Path()
      ..moveTo(35, 12)
      ..lineTo(35, 29.5)
      ..arcToPoint(
        const Offset(31, 23.2),
        radius: const Radius.elliptical(6.5, 6.5),
        largeArc: true,
        clockwise: true,
      )
      ..lineTo(31, 15)
      ..close();
    canvas.drawPath(mint, Paint()..color = const Color(0xFF7EE7D3));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MuZicAppIconPainter oldDelegate) => false;
}
