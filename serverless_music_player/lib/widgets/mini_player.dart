import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/player_controller.dart';
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
    final max = player.duration.inMilliseconds;
    final value = max <= 0
        ? 0.0
        : (player.position.inMilliseconds / max).clamp(0.0, 1.0).toDouble();

    return Container(
      height: 72,
      margin: const EdgeInsets.fromLTRB(10, 4, 10, 5),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.outline.withValues(alpha: 0.5)),
      ),
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => showNowPlaying(context),
                child: Row(
                  children: <Widget>[
                    const SizedBox(width: 9),
                    CoverArt(song: song, size: 52, radius: 13),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(song.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                          const SizedBox(height: 4),
                          Text(song.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: palette.textMuted, fontSize: 11)),
                        ],
                      ),
                    ),
                    if (player.isResolving || player.isBuffering)
                      const SizedBox(
                        width: 38,
                        height: 38,
                        child: Padding(
                          padding: EdgeInsets.all(11),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    else
                      IconButton(
                        tooltip: player.isPlaying ? 'Pause' : 'Play',
                        onPressed: player.togglePlayback,
                        icon: Icon(
                          player.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          color: palette.accent,
                          size: 30,
                        ),
                      ),
                    IconButton(
                      tooltip: 'Next track',
                      onPressed: player.next,
                      icon: const Icon(Icons.skip_next_rounded, size: 28),
                    ),
                    const SizedBox(width: 4),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(18)),
              child: LinearProgressIndicator(
                value: value,
                minHeight: 2,
                backgroundColor: Colors.transparent,
                color: palette.mint,
              ),
            ),
          ),
        ],
      ),
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
