import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/player_controller.dart';
import '../services/sleep_timer_service.dart';
import '../services/video_export_manager.dart';
import '../theme/app_theme.dart';
import 'animated_rhythm_icon.dart';
import 'media_controller_card.dart';
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
        // The same lock-screen media card as the full player, in miniature:
        // the song's face card fills the whole bar, with title/artist, the
        // wavy seek strip and previous/play/next overlaid on a scrim.
        Container(
          height: 84,
          margin: const EdgeInsets.fromLTRB(10, 4, 10, 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.28),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                ArtworkBackdrop(song: song),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: <Color>[Color(0xC2000000), Color(0x8A000000)],
                    ),
                  ),
                ),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => showNowPlaying(context),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 8, 6, 4),
                      child: Row(
                        children: <Widget>[
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
                                          color: Colors.white,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 13.5,
                                        ),
                                      ),
                                    ),
                                    if (player.isPlaying) ...<Widget>[
                                      const SizedBox(width: 6),
                                      const AnimatedRhythmIcon(
                                        active: true,
                                        color: Color(0xFF7EE7D3),
                                        size: 14,
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 1),
                                Text(
                                  song.artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xB3FFFFFF),
                                    fontSize: 11,
                                  ),
                                ),
                                SizedBox(
                                  height: 26,
                                  child: Row(
                                    children: <Widget>[
                                      Text(
                                        formatMediaTime(player.position),
                                        style: const TextStyle(
                                          color: Color(0xB3FFFFFF),
                                          fontSize: 9,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      Expanded(
                                        child: WavySeekBar(
                                          position: player.position,
                                          duration: player.duration,
                                          isPlaying: player.isPlaying,
                                          onSeek: player.seek,
                                        ),
                                      ),
                                      Text(
                                        formatMediaTime(player.duration),
                                        style: const TextStyle(
                                          color: Color(0xB3FFFFFF),
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
                            icon: const Icon(Icons.skip_previous_rounded,
                                color: Colors.white, size: 23),
                          ),
                          if (player.isResolving || player.isBuffering)
                            const SizedBox(
                              width: 44,
                              height: 44,
                              child: Padding(
                                padding: EdgeInsets.all(11),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              ),
                            )
                          else
                            Material(
                              color: const Color(0xF2FFFFFF),
                              borderRadius: BorderRadius.circular(14),
                              child: InkWell(
                                onTap: player.togglePlayback,
                                borderRadius: BorderRadius.circular(14),
                                child: SizedBox(
                                  width: 46,
                                  height: 42,
                                  child: Icon(
                                    player.isPlaying
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                    color: const Color(0xFF2A2438),
                                    size: 25,
                                  ),
                                ),
                              ),
                            ),
                          IconButton(
                            tooltip: 'Next track',
                            visualDensity: VisualDensity.compact,
                            onPressed: player.next,
                            icon: const Icon(Icons.skip_next_rounded,
                                color: Colors.white, size: 23),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
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
