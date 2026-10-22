import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// The MuZic note shown at the top-left of the main pages.
///
/// Tapping it acts as Home. The note gives a short vibration-like shake so
/// the action feels alive without depending on device haptics being enabled.
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
                gradient: LinearGradient(
                  colors: <Color>[palette.accent, palette.mint],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: palette.accent.withValues(alpha: 0.28),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(
                Icons.music_note_rounded,
                color: palette.background,
                size: 24,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
