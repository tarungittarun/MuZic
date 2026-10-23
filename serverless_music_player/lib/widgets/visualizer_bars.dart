import 'package:flutter/material.dart';

import '../theme/app_theme.dart';


/// Low-pass smooths incoming (0..1) audio bands while retaining their
/// differences, so changes in the captured music stay visible in the bars.
List<double> smoothVisualizerLevels({
  required List<double> previous,
  required List<double> incoming,
  required int barCount,
}) {
  final levels = List<double>.filled(barCount, 0.055);
  if (incoming.isEmpty) return levels;
  for (var index = 0; index < barCount; index++) {
    final prior = index < previous.length ? previous[index] : 0.055;
    final source = incoming[index % incoming.length].clamp(0.0, 1.0).toDouble();
    levels[index] = (prior * 0.42) + (source * 0.58);
  }
  return levels;
}

/// Animated bars driven by measured waveform bands from the active playback
/// session. The caller owns the capture lifecycle and supplies the live stream.
class VisualizerBars extends StatefulWidget {
  const VisualizerBars({
    required this.bands,
    this.height = 42,
    this.barCount = 18,
    super.key,
  });

  final Stream<List<double>> bands;
  final double height;
  final int barCount;

  @override
  State<VisualizerBars> createState() => _VisualizerBarsState();
}

class _VisualizerBarsState extends State<VisualizerBars> {
  late List<double> _levels =
      List<double>.filled(widget.barCount, 0.055, growable: false);

  @override
  void didUpdateWidget(covariant VisualizerBars oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.barCount != widget.barCount) {
      _levels = List<double>.filled(widget.barCount, 0.055, growable: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return StreamBuilder<List<double>>(
      stream: widget.bands,
      builder: (context, snapshot) {
        final incoming = snapshot.data;
        if (incoming != null && incoming.isNotEmpty) {
          _levels = smoothVisualizerLevels(
            previous: _levels,
            incoming: incoming,
            barCount: widget.barCount,
          );
        }
        return SizedBox(
          height: widget.height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              for (var index = 0; index < widget.barCount; index++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1.5),
                    child: AnimatedContainer(
                      key: ValueKey<String>('visualizer-bar-$index'),
                      duration: const Duration(milliseconds: 110),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.bottomCenter,
                      height: (widget.height * _levels[index])
                          .clamp(2.0, widget.height)
                          .toDouble(),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: <Color>[palette.accent, palette.mint],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
