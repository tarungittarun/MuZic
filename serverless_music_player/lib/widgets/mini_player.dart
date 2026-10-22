import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/player_controller.dart';
import '../services/sleep_timer_service.dart';
import '../services/video_export_manager.dart';
import '../theme/app_theme.dart';
import 'cover_art.dart';
import 'now_playing_sheet.dart';

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    final palette = context.palette;
    final song = player.currentSong;
    if (song == null) return const SizedBox.shrink();
    final sleepTimer = context.watch<SleepTimerService>();
    final export = context.watch<VideoExportManager>();
    final max = player.duration.inMilliseconds;

    final warning = sleepTimer.isWarningActive;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (warning)
          Container(
            margin: const EdgeInsets.fromLTRB(10, 4, 10, 0),
            padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
            decoration: BoxDecoration(
              color: palette.accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: palette.accent.withValues(alpha: 0.5)),
            ),
            child: Row(
              children: <Widget>[
                Icon(Icons.bedtime_rounded, size: 17, color: palette.accent),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    'Still listening? MuZic pauses in '
                    '${sleepTimer.remaining.inMinutes + 1} min without activity.',
                    style: const TextStyle(fontSize: 11.5, height: 1.35),
                  ),
                ),
                TextButton(
                  onPressed: sleepTimer.snooze,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    textStyle: const TextStyle(fontSize: 11),
                  ),
                  child: const Text("I'm here"),
                ),
              ],
            ),
          ),
        if (export.isBusy)
          Container(
            margin: const EdgeInsets.fromLTRB(10, 4, 10, 0),
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            decoration: BoxDecoration(
              color: palette.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: palette.accent.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: <Widget>[
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    value: export.percent == 0 ? null : export.progress,
                    strokeWidth: 2,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Rendering lyric video · ${export.percent}%'
                    '${export.songTitle == null ? '' : ' · ${export.songTitle}'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5),
                  ),
                ),
                TextButton(
                  onPressed: () => showExportProgress(context),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    textStyle: const TextStyle(fontSize: 11),
                  ),
                  child: const Text('Stop'),
                ),
              ],
            ),
          ),
        // Lock-screen-style mini player: same compact height class as
        // before, but artwork-led with previous/play/next and a real seek
        // strip (like Android's system media card), not just a progress line.
        Container(
          height: 80,
          margin: const EdgeInsets.fromLTRB(10, 4, 10, 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              colors: <Color>[
                palette.surfaceRaised,
                Color.alphaBlend(
                  palette.accent.withValues(alpha: 0.13),
                  palette.surfaceRaised,
                ),
              ],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            border: Border.all(color: palette.outline.withValues(alpha: 0.55)),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.16),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => showNowPlaying(context),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 7, 5, 5),
                child: Row(
                  children: <Widget>[
                    CoverArt(song: song, size: 58, radius: 14),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: Text(
                                  song.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              if (player.isPlaying)
                                Icon(
                                  Icons.graphic_eq_rounded,
                                  size: 14,
                                  color: palette.mint,
                                ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            song.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: palette.textMuted, fontSize: 11),
                          ),
                          SizedBox(
                            height: 20,
                            child: Row(
                              children: <Widget>[
                                Text(
                                  _formatMiniTime(player.position),
                                  style: TextStyle(
                                    color: palette.textMuted,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Expanded(
                                  child: SliderTheme(
                                    data: SliderTheme.of(context).copyWith(
                                      trackHeight: 2.5,
                                      thumbShape: const RoundSliderThumbShape(
                                        enabledThumbRadius: 5,
                                      ),
                                      overlayShape: const RoundSliderOverlayShape(
                                        overlayRadius: 11,
                                      ),
                                      activeTrackColor: palette.mint,
                                      inactiveTrackColor:
                                          palette.outline.withValues(alpha: 0.65),
                                      thumbColor: palette.mint,
                                    ),
                                    child: Slider(
                                      value: max <= 0
                                          ? 0
                                          : player.position.inMilliseconds
                                              .clamp(0, max)
                                              .toDouble(),
                                      max: max <= 0 ? 1 : max.toDouble(),
                                      onChanged: max <= 0
                                          ? null
                                          : (value) => player.seek(
                                                Duration(
                                                  milliseconds: value.round(),
                                                ),
                                              ),
                                    ),
                                  ),
                                ),
                                Text(
                                  _formatMiniTime(player.duration),
                                  style: TextStyle(
                                    color: palette.textMuted,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Previous track',
                      visualDensity: VisualDensity.compact,
                      onPressed: player.previous,
                      icon: const Icon(Icons.skip_previous_rounded, size: 24),
                    ),
                    if (player.isResolving || player.isBuffering)
                      const SizedBox(
                        width: 40,
                        height: 40,
                        child: Padding(
                          padding: EdgeInsets.all(10),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    else
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: palette.accent,
                          boxShadow: <BoxShadow>[
                            BoxShadow(
                              color: palette.accent.withValues(alpha: 0.35),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: IconButton(
                          tooltip: player.isPlaying ? 'Pause' : 'Play',
                          onPressed: player.togglePlayback,
                          icon: Icon(
                            player.isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 25,
                          ),
                        ),
                      ),
                    IconButton(
                      tooltip: 'Next track',
                      visualDensity: VisualDensity.compact,
                      onPressed: player.next,
                      icon: const Icon(Icons.skip_next_rounded, size: 24),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}


String _formatMiniTime(Duration duration) {
  final totalSeconds = duration.inSeconds < 0 ? 0 : duration.inSeconds;
  final minutes = totalSeconds ~/ 60;
  final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

void showNowPlaying(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const NowPlayingSheet(),
  );
}
