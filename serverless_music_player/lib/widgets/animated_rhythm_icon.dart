import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Small equaliser whose bars bounce in rhythm while [active] is true.
///
/// Used for the Now Playing live-waveform button: when the waveform is on
/// and a song is playing, the top-right symbol dances instead of sitting
/// still; when paused/off it rests as a quiet equaliser glyph.
class AnimatedRhythmIcon extends StatefulWidget {
  const AnimatedRhythmIcon({
    required this.active,
    required this.color,
    this.size = 24,
    super.key,
  });

  final bool active;
  final Color color;
  final double size;

  @override
  State<AnimatedRhythmIcon> createState() => _AnimatedRhythmIconState();
}

class _AnimatedRhythmIconState extends State<AnimatedRhythmIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 760),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant AnimatedRhythmIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.active && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        const base = <double>[0.48, 0.82, 0.58, 0.95];
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              for (var i = 0; i < base.length; i++)
                Container(
                  width: 3,
                  height: widget.size *
                      (widget.active
                          ? (0.28 +
                              0.72 *
                                  base[i] *
                                  (0.55 +
                                      0.45 *
                                          math.sin(
                                            (t + i * 0.17) * math.pi * 2,
                                          )))
                          : base[i] * 0.72),
                  decoration: BoxDecoration(
                    color: widget.color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
