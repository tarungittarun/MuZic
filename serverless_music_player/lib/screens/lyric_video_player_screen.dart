import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../services/video_library_service.dart';
import '../theme/app_theme.dart';

/// In-app playback for a saved lyric video, including files stored through SAF.
class LyricVideoPlayerScreen extends StatefulWidget {
  const LyricVideoPlayerScreen({required this.video, super.key});

  final VideoExportRecord video;

  @override
  State<LyricVideoPlayerScreen> createState() =>
      _LyricVideoPlayerScreenState();
}

class _LyricVideoPlayerScreenState extends State<LyricVideoPlayerScreen> {
  late final VideoPlayerController _controller;
  bool _loading = true;
  bool _controlsVisible = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = _createController(widget.video.path);
    unawaited(_initializePlayer());
  }

  VideoPlayerController _createController(String path) {
    if (path.startsWith('content://')) {
      return VideoPlayerController.contentUri(Uri.parse(path));
    }
    final uri = Uri.tryParse(path);
    if (uri != null && uri.scheme == 'file') {
      return VideoPlayerController.file(File.fromUri(uri));
    }
    return VideoPlayerController.file(File(path));
  }

  Future<void> _initializePlayer() async {
    try {
      await _controller.initialize();
      if (!mounted) return;
      setState(() => _loading = false);
      await _controller.play();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error =
            'This video could not be opened. It may have been moved or removed.';
      });
    }
  }

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              widget.video.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            if (widget.video.artist.isNotEmpty)
              Text(
                widget.video.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: Colors.white70),
              ),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        child: Center(child: _playerBody(palette)),
      ),
    );
  }

  Widget _playerBody(AppPalette palette) {
    if (_loading) {
      return const Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          CircularProgressIndicator(color: Colors.white),
          SizedBox(height: 14),
          Text('Opening video…', style: TextStyle(color: Colors.white70)),
        ],
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.video_file_outlined, color: Colors.white54, size: 46),
            const SizedBox(height: 14),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 18),
            TextButton.icon(
              onPressed: () {
                Navigator.of(context).maybePop();
              },
              icon: const Icon(Icons.arrow_back_rounded),
              label: const Text('Back to lyric videos'),
              style: TextButton.styleFrom(foregroundColor: palette.accent),
            ),
          ],
        ),
      );
    }

    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: _controller,
      builder: (context, value, _) {
        if (value.hasError) return _playbackError(palette);
        if (!value.isInitialized) {
          return const CircularProgressIndicator(color: Colors.white);
        }
        final aspectRatio = value.aspectRatio > 0 ? value.aspectRatio : 9 / 16;
        final durationMs = value.duration.inMilliseconds;
        final positionMs =
            value.position.inMilliseconds.clamp(0, durationMs).toDouble();
        final progress = durationMs <= 0 ? 0.0 : positionMs / durationMs;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _controlsVisible = !_controlsVisible),
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              Center(
                child: AspectRatio(
                  aspectRatio: aspectRatio,
                  child: VideoPlayer(_controller),
                ),
              ),
              if (_controlsVisible)
                Positioned.fill(
                  child: Stack(
                    children: <Widget>[
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: <Color>[
                              Color(0x44000000),
                              Color(0x00000000),
                              Color(0x66000000),
                            ],
                          ),
                        ),
                        child: SizedBox.expand(),
                      ),
                      Center(
                        child: IconButton.filledTonal(
                          onPressed: _togglePlayback,
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.black.withValues(alpha: 0.58),
                            foregroundColor: Colors.white,
                            fixedSize: const Size(64, 64),
                          ),
                          iconSize: 36,
                          icon: Icon(
                            value.isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                          ),
                        ),
                      ),
                      Positioned(
                        left: 12,
                        right: 12,
                        bottom: 8,
                        child: Row(
                          children: <Widget>[
                            Text(
                              _formatTime(value.position),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontFeatures: <FontFeature>[
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                            Expanded(
                              child: SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  trackHeight: 2.5,
                                  activeTrackColor: palette.accent,
                                  inactiveTrackColor: Colors.white38,
                                  thumbColor: Colors.white,
                                  overlayColor:
                                      palette.accent.withValues(alpha: 0.18),
                                  thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 6,
                                  ),
                                ),
                                child: Slider(
                                  value: progress,
                                  onChanged: durationMs <= 0
                                      ? null
                                      : (value) {
                                          unawaited(
                                            _controller.seekTo(
                                              Duration(
                                                milliseconds:
                                                    (durationMs * value).round(),
                                              ),
                                            ),
                                          );
                                        },
                                ),
                              ),
                            ),
                            Text(
                              _formatTime(value.duration),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontFeatures: <FontFeature>[
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              if (value.isBuffering)
                const CircularProgressIndicator(color: Colors.white),
            ],
          ),
        );
      },
    );
  }

  Widget _playbackError(AppPalette palette) => Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.video_file_outlined, color: Colors.white54, size: 46),
          const SizedBox(height: 14),
          const Text(
            'This video could not be played.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 18),
          TextButton.icon(
            onPressed: () {
              Navigator.of(context).maybePop();
            },
            icon: const Icon(Icons.arrow_back_rounded),
            label: const Text('Back to lyric videos'),
            style: TextButton.styleFrom(foregroundColor: palette.accent),
          ),
        ],
      );

  void _togglePlayback() {
    if (_controller.value.isPlaying) {
      unawaited(_controller.pause());
    } else {
      unawaited(_controller.play());
    }
  }

  String _formatTime(Duration duration) {
    final seconds = duration.inSeconds;
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }
}
