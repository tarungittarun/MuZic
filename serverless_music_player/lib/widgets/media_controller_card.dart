import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/song_model.dart';
import 'muzic_home_button.dart';

/// The in-app twin of Android's lock-screen media player.
///
/// The song's artwork ("face card") covers the whole card, with the MuZic
/// icon at the top-left, a "This phone" output pill at the top-right, the
/// title/artist overlaid at the bottom-left, a large rounded-square
/// play/pause button, and the wavy seek bar with previous/next — the same
/// layout the system draws on the lock screen, reproduced inside MuZic so
/// both surfaces feel like one controller.
class MediaControllerCard extends StatelessWidget {
  const MediaControllerCard({
    required this.song,
    required this.isPlaying,
    required this.isBusy,
    required this.position,
    required this.duration,
    required this.onPlayPause,
    required this.onNext,
    required this.onPrevious,
    required this.onSeek,
    super.key,
  });

  final SongModel song;
  final bool isPlaying;

  /// Buffering/resolving: the play button becomes a spinner.
  final bool isBusy;
  final Duration position;
  final Duration duration;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final ValueChanged<Duration> onSeek;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          ArtworkBackdrop(song: song),
          // Legibility scrim: light at the top, deep at the bottom where
          // the text and controls live — same as the system card.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  Color(0x2E000000),
                  Color(0x00000000),
                  Color(0x59000000),
                  Color(0xC4000000),
                ],
                stops: <double>[0, 0.35, 0.68, 1],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Column(
              children: <Widget>[
                const Row(
                  children: <Widget>[
                    MuZicAppIcon(size: 34),
                    Spacer(),
                    _ThisPhonePill(),
                  ],
                ),
                const Spacer(),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            song.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              height: 1.15,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            song.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xD9FFFFFF),
                              fontSize: 13.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    _PlayPauseButton(
                      isPlaying: isPlaying,
                      isBusy: isBusy,
                      onPressed: onPlayPause,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: <Widget>[
                    IconButton(
                      tooltip: 'Previous track',
                      onPressed: onPrevious,
                      icon: const Icon(Icons.skip_previous_rounded,
                          color: Colors.white, size: 28),
                    ),
                    Expanded(
                      child: WavySeekBar(
                        position: position,
                        duration: duration,
                        isPlaying: isPlaying,
                        onSeek: onSeek,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Next track',
                      onPressed: onNext,
                      icon: const Icon(Icons.skip_next_rounded,
                          color: Colors.white, size: 28),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 2),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      Text(
                        formatMediaTime(position),
                        style: const TextStyle(
                          color: Color(0xB3FFFFFF),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        formatMediaTime(duration),
                        style: const TextStyle(
                          color: Color(0xB3FFFFFF),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The artwork-only card used when transport controls sit below the art.
class MediaArtworkCard extends StatelessWidget {
  const MediaArtworkCard({
    required this.song,
    this.onLyricsTap,
    super.key,
  });

  final SongModel song;
  final VoidCallback? onLyricsTap;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          ArtworkBackdrop(song: song),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  Color(0x2E000000),
                  Color(0x00000000),
                  Color(0x59000000),
                  Color(0xC4000000),
                ],
                stops: <double>[0, 0.35, 0.68, 1],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Row(
                  children: <Widget>[
                    MuZicAppIcon(size: 34),
                    Spacer(),
                    _ThisPhonePill(),
                  ],
                ),
                const Spacer(),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            song.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              height: 1.15,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            song.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xD9FFFFFF),
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 56),
                  ],
                ),
              ],
            ),
          ),
          if (onLyricsTap != null)
            Positioned(
              right: 14,
              bottom: 14,
              child: Material(
                color: Colors.white.withValues(alpha: 0.92),
                shape: const CircleBorder(),
                child: IconButton(
                  tooltip: 'Lyrics',
                  onPressed: onLyricsTap,
                  icon: const Icon(
                    Icons.lyrics_outlined,
                    color: Color(0xFF2A2438),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Playback buttons and the live seek line placed directly under the art.
class MediaTransportControls extends StatelessWidget {
  const MediaTransportControls({
    required this.isPlaying,
    required this.isBusy,
    required this.position,
    required this.duration,
    required this.onPlayPause,
    required this.onNext,
    required this.onPrevious,
    required this.onSeek,
    this.leadingControl,
    super.key,
  });

  final bool isPlaying;
  final bool isBusy;
  final Duration position;
  final Duration duration;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final ValueChanged<Duration> onSeek;
  final Widget? leadingControl;

  @override
  Widget build(BuildContext context) {
    final textColor = Theme.of(context).colorScheme.onSurface;
    final timeStyle = TextStyle(
      color: textColor.withValues(alpha: 0.62),
      fontSize: 10.5,
      fontWeight: FontWeight.w600,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              if (leadingControl != null) ...<Widget>[
                leadingControl!,
                const SizedBox(width: 8),
              ],
              IconButton(
                tooltip: 'Previous track',
                onPressed: onPrevious,
                icon: const Icon(Icons.skip_previous_rounded, size: 29),
              ),
              const SizedBox(width: 12),
              _PlayPauseButton(
                isPlaying: isPlaying,
                isBusy: isBusy,
                onPressed: onPlayPause,
              ),
              const SizedBox(width: 12),
              IconButton(
                tooltip: 'Next track',
                onPressed: onNext,
                icon: const Icon(Icons.skip_next_rounded, size: 29),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            children: <Widget>[
              Text(formatMediaTime(position), style: timeStyle),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 9),
                  child: WavySeekBar(
                    position: position,
                    duration: duration,
                    isPlaying: isPlaying,
                    onSeek: onSeek,
                  ),
                ),
              ),
              Text(formatMediaTime(duration), style: timeStyle),
            ],
          ),
        ],
      ),
    );
  }
}

class _ThisPhonePill extends StatelessWidget {
  const _ThisPhonePill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xE6FFFFFF),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.smartphone_rounded, size: 13, color: Color(0xFF2A2438)),
          SizedBox(width: 5),
          Text(
            'This phone',
            style: TextStyle(
              color: Color(0xFF2A2438),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayPauseButton extends StatelessWidget {
  const _PlayPauseButton({
    required this.isPlaying,
    required this.isBusy,
    required this.onPressed,
  });

  final bool isPlaying;
  final bool isBusy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xF2FFFFFF),
      borderRadius: BorderRadius.circular(19),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(19),
        child: SizedBox(
          width: 64,
          height: 56,
          child: isBusy
              ? const Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Color(0xFF2A2438),
                    ),
                  ),
                )
              : Icon(
                  isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: const Color(0xFF2A2438),
                  size: 32,
                ),
        ),
      ),
    );
  }
}

/// Full-bleed song artwork used as a card background (the "face card").
/// Falls back to a brand gradient with a note when a song has no artwork.
class ArtworkBackdrop extends StatelessWidget {
  const ArtworkBackdrop({required this.song, super.key});

  final SongModel song;

  @override
  Widget build(BuildContext context) {
    final localPath = song.localArtworkPath;
    if (localPath != null && localPath.isNotEmpty && File(localPath).existsSync()) {
      return Image.file(File(localPath), fit: BoxFit.cover);
    }
    if (song.artworkUrl.startsWith('http')) {
      return CachedNetworkImage(
        imageUrl: song.artworkUrl,
        fit: BoxFit.cover,
        placeholder: (_, __) => _fallback(),
        errorWidget: (_, __, ___) => _fallback(),
      );
    }
    return _fallback();
  }

  // Fixed brand colours (not theme lookups) so the backdrop is safe in any
  // host — dialogs, tests, or themes without the MuZic extension.
  Widget _fallback() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[Color(0xFF3A2E5C), Color(0xFF173F3A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Icon(
          Icons.music_note_rounded,
          size: 84,
          color: Colors.white.withValues(alpha: 0.5),
        ),
      ),
    );
  }
}

/// Seek bar drawn like Android's expressive media slider: the played part
/// is a gentle wave, the rest is a straight line, with a round thumb.
class WavySeekBar extends StatefulWidget {
  const WavySeekBar({
    required this.position,
    required this.duration,
    required this.onSeek,
    this.isPlaying = false,
    this.activeColor = Colors.white,
    this.inactiveColor = const Color(0x66FFFFFF),
    super.key,
  });

  final Duration position;
  final Duration duration;
  final ValueChanged<Duration> onSeek;
  final bool isPlaying;
  final Color activeColor;
  final Color inactiveColor;

  @override
  State<WavySeekBar> createState() => _WavySeekBarState();
}

class _WavySeekBarState extends State<WavySeekBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _waveController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void initState() {
    super.initState();
    if (widget.isPlaying) _startWave();
  }

  @override
  void didUpdateWidget(covariant WavySeekBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying && !oldWidget.isPlaying) {
      _startWave();
    } else if (!widget.isPlaying && oldWidget.isPlaying) {
      _waveController.stop();
      _waveController.value = 0;
    }
  }

  void _startWave() {
    unawaited(_waveController.repeat());
  }

  @override
  void dispose() {
    _waveController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final totalMs = widget.duration.inMilliseconds;
    final value = totalMs <= 0
        ? 0.0
        : widget.position.inMilliseconds.clamp(0, totalMs).toDouble();
    return AnimatedBuilder(
      animation: _waveController,
      builder: (context, _) {
        final phase = widget.isPlaying ? _waveController.value * math.pi * 2 : 0.0;
        return SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            trackShape: WavySliderTrackShape(
              phase: phase,
              amplitudeScale: widget.isPlaying ? 1.0 : 0.72,
            ),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.5),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 15),
            activeTrackColor: widget.activeColor,
            inactiveTrackColor: widget.inactiveColor,
            thumbColor: widget.activeColor,
            overlayColor: widget.activeColor.withValues(alpha: 0.18),
          ),
          child: Slider(
            min: 0,
            max: totalMs <= 0 ? 1 : totalMs.toDouble(),
            value: value,
            onChanged: totalMs <= 0
                ? null
                : (v) => widget.onSeek(Duration(milliseconds: v.round())),
          ),
        );
      },
    );
  }
}

/// Track shape whose played portion undulates like the system media
/// slider's waveform, flattening as it reaches the thumb.
class WavySliderTrackShape extends SliderTrackShape {
  const WavySliderTrackShape({this.phase = 0, this.amplitudeScale = 1});

  final double phase;
  final double amplitudeScale;

  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final trackHeight = sliderTheme.trackHeight ?? 4;
    final trackLeft = offset.dx;
    final trackTop = offset.dy + (parentBox.size.height - trackHeight) / 2;
    return Rect.fromLTWH(trackLeft, trackTop, parentBox.size.width, trackHeight);
  }

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    required TextDirection textDirection,
  }) {
    final trackRect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    final centerY = trackRect.center.dy;
    final activeColor = sliderTheme.activeTrackColor ?? Colors.white;
    final inactiveColor = sliderTheme.inactiveTrackColor ?? const Color(0x66FFFFFF);

    final inactivePaint = Paint()
      ..color = inactiveColor
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    context.canvas.drawLine(
      Offset(thumbCenter.dx, centerY),
      Offset(trackRect.right, centerY),
      inactivePaint,
    );

    if (thumbCenter.dx > trackRect.left) {
      const wavelength = 13.0;
      const amplitude = 2.6;
      final wave = Path()..moveTo(trackRect.left, centerY);
      for (var x = trackRect.left; x < thumbCenter.dx; x += 2) {
        // Flatten the wave near both ends so it leaves the track start and
        // meets the thumb smoothly instead of crossing it.
        final startTaper = ((x - trackRect.left) / 12).clamp(0.0, 1.0);
        final endTaper = ((thumbCenter.dx - x) / 12).clamp(0.0, 1.0);
        final taper = math.min(startTaper, endTaper);
        final y = centerY +
            math.sin((x - trackRect.left) / wavelength * 2 * math.pi + phase) *
                amplitude *
                amplitudeScale *
                taper;
        wave.lineTo(x, y);
      }
      wave.lineTo(thumbCenter.dx, centerY);
      final wavePaint = Paint()
        ..color = activeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      context.canvas.drawPath(wave, wavePaint);
    }
  }
}

String formatMediaTime(Duration duration) {
  final totalSeconds = duration.inSeconds < 0 ? 0 : duration.inSeconds;
  final minutes = totalSeconds ~/ 60;
  final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
