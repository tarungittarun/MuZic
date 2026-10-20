import 'package:flutter/material.dart';

import '../services/visualizer_service.dart';
import '../theme/app_theme.dart';

/// Animated bars driven by real waveform data from the playback session.
class VisualizerBars extends StatefulWidget {
  const VisualizerBars({
    required this.service,
    this.height = 42,
    this.barCount = 18,
    super.key,
  });

  final VisualizerService service;
  final double height;
  final int barCount;

  @override
  State<VisualizerBars> createState() => _VisualizerBarsState();
}

class _VisualizerBarsState extends State<VisualizerBars> {
  late List<double> _levels =
      List<double>.filled(widget.barCount, 0.06, growable: false);

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return StreamBuilder<List<double>>(
      stream: widget.service.bands,
      builder: (context, snapshot) {
        final incoming = snapshot.data;
        if (incoming != null && incoming.isNotEmpty) {
          final buffer = List<double>.filled(widget.barCount, 0.06);
          for (var index = 0; index < widget.barCount; index++) {
            final source = incoming[index % incoming.length];
            // Smooth so the bars do not flicker frame to frame.
            buffer[index] = (_levels[index] * 0.55) + (source * 0.45);
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
                    child: TweenAnimationBuilder<double>(
                      tween: Tween<double>(begin: 0, end: _levels[index]),
                      duration: const Duration(milliseconds: 90),
                      builder: (context, value, child) => Container(
                        height: (widget.height * value).clamp(
                          2.0,
                          widget.height,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(3),
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: <Color>[
                              palette.accent,
                              palette.mint,
                            ],
                          ),
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
