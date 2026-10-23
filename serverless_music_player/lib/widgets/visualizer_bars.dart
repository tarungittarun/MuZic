import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

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
          final buffer = List<double>.filled(widget.barCount, 0.055);
          for (var index = 0; index < widget.barCount; index++) {
            final source = incoming[index % incoming.length]
                .clamp(0.0, 1.0)
                .toDouble();
            // Smooth peaks without pinning the display at a single value.
            buffer[index] = (_levels[index] * 0.42) + (source * 0.58);
          }
          _levels = buffer;
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
