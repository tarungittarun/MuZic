import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';

import '../models/lyrics_model.dart';
import '../models/song_model.dart';
import '../providers/player_controller.dart';
import '../services/music_api_service.dart';
import '../theme/app_theme.dart';
import 'cover_art.dart';

class NowPlayingSheet extends StatefulWidget {
  const NowPlayingSheet({super.key});

  @override
  State<NowPlayingSheet> createState() => _NowPlayingSheetState();
}

class _NowPlayingSheetState extends State<NowPlayingSheet> {
  bool _showLyrics = false;

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    final song = player.currentSong;
    if (song == null) return const SizedBox.shrink();
    final screenHeight = MediaQuery.sizeOf(context).height;
    final totalMs = player.duration.inMilliseconds;
    final sliderValue = totalMs <= 0
        ? 0.0
        : player.position.inMilliseconds.clamp(0, totalMs).toDouble();

    return Container(
      height: screenHeight * 0.94,
      decoration: const BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: <Widget>[
            const SizedBox(height: 10),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 12, 4),
              child: Row(
                children: <Widget>[
                  IconButton(
                    tooltip: 'Close player',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30),
                  ),
                  const Expanded(
                    child: Column(
                      children: <Widget>[
                        Text('NOW PLAYING', style: TextStyle(fontSize: 10, letterSpacing: 2, color: Colors.white54, fontWeight: FontWeight.w700)),
                        SizedBox(height: 3),
                        Text('Auralis', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Up next',
                    onPressed: () => _showQueue(context),
                    icon: const Icon(Icons.queue_music_rounded),
                  ),
                ],
              ),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: _showLyrics
                    ? _LyricsPanel(
                        key: ValueKey<String>('lyrics-${song.id}'),
                        song: song,
                        position: player.position,
                      )
                    : _ArtworkPanel(key: ValueKey<String>('art-${song.id}'), song: song),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(song.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 6),
                        Text(song.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white60, fontSize: 14)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: player.isFavorite(song) ? 'Unlike' : 'Like',
                    onPressed: () => player.toggleFavorite(song),
                    icon: Icon(
                      player.isFavorite(song) ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                      color: player.isFavorite(song) ? AppTheme.accent : Colors.white70,
                    ),
                  ),
                  IconButton(
                    tooltip: player.isDownloaded(song) ? 'Saved offline' : 'Download',
                    onPressed: player.isDownloaded(song) || player.isDownloading
                        ? null
                        : () => _download(context, song),
                    icon: player.downloadProgressFor(song) != null
                        ? SizedBox(
                            width: 21,
                            height: 21,
                            child: CircularProgressIndicator(
                              value: player.downloadProgressFor(song) == 0
                                  ? null
                                  : player.downloadProgressFor(song),
                              strokeWidth: 2,
                            ),
                          )
                        : Icon(
                            player.isDownloaded(song)
                                ? Icons.download_done_rounded
                                : Icons.download_rounded,
                            color: player.isDownloaded(song) ? AppTheme.mint : Colors.white70,
                          ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Column(
                children: <Widget>[
                  Slider(
                    min: 0,
                    max: totalMs <= 0 ? 1 : totalMs.toDouble(),
                    value: totalMs <= 0 ? 0 : sliderValue,
                    onChanged: totalMs <= 0
                        ? null
                        : (value) => player.seek(Duration(milliseconds: value.toInt())),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        Text(_format(player.position), style: const TextStyle(fontSize: 11, color: Colors.white54)),
                        Text(_format(player.duration), style: const TextStyle(fontSize: 11, color: Colors.white54)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  IconButton(
                    tooltip: 'Shuffle',
                    onPressed: player.toggleShuffle,
                    icon: Icon(Icons.shuffle_rounded,
                        color: player.shuffleEnabled ? AppTheme.mint : Colors.white54),
                  ),
                  IconButton(
                    tooltip: 'Previous track',
                    onPressed: player.previous,
                    icon: const Icon(Icons.skip_previous_rounded, size: 34),
                  ),
                  SizedBox(
                    width: 68,
                    height: 68,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.accent,
                        foregroundColor: AppTheme.background,
                        shape: const CircleBorder(),
                        padding: EdgeInsets.zero,
                      ),
                      onPressed: player.togglePlayback,
                      child: player.isBuffering || player.isResolving
                          ? const SizedBox(
                              width: 25,
                              height: 25,
                              child: CircularProgressIndicator(strokeWidth: 2.5, color: AppTheme.background),
                            )
                          : Icon(
                              player.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                              size: 38,
                            ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Next track',
                    onPressed: player.next,
                    icon: const Icon(Icons.skip_next_rounded, size: 34),
                  ),
                  IconButton(
                    tooltip: 'Repeat mode: ${_repeatLabel(player.repeatMode)}',
                    onPressed: player.cycleRepeatMode,
                    icon: Icon(
                      player.repeatMode == LoopMode.one
                          ? Icons.repeat_one_rounded
                          : Icons.repeat_rounded,
                      color: player.repeatMode == LoopMode.off ? Colors.white54 : AppTheme.mint,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TextButton.icon(
                onPressed: () => setState(() => _showLyrics = !_showLyrics),
                icon: Icon(_showLyrics ? Icons.album_rounded : Icons.lyrics_outlined, size: 18),
                label: Text(_showLyrics ? 'Show artwork' : 'Lyrics'),
                style: TextButton.styleFrom(foregroundColor: AppTheme.accent),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _download(BuildContext context, SongModel song) async {
    try {
      await context.read<PlayerController>().downloadSong(song);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed: $error')),
        );
      }
    }
  }

  Future<void> _showQueue(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      showDragHandle: true,
      builder: (_) => const _QueueSheet(),
    );
  }

  String _format(Duration value) {
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    final hours = value.inHours;
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  static String _repeatLabel(LoopMode mode) => switch (mode) {
        LoopMode.off => 'off',
        LoopMode.all => 'all',
        LoopMode.one => 'one',
      };
}

class _ArtworkPanel extends StatelessWidget {
  const _ArtworkPanel({required this.song, super.key});
  final SongModel song;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final dimension = (constraints.biggest.shortestSide - 28).clamp(0.0, 420.0).toDouble();
        return Center(
          child: SizedBox.square(
            dimension: dimension,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                boxShadow: <BoxShadow>[
                  BoxShadow(color: AppTheme.accent.withValues(alpha: 0.12), blurRadius: 42, spreadRadius: 2),
                ],
              ),
              child: CoverArt(song: song, size: dimension, radius: 28),
            ),
          ),
        );
      },
    );
  }
}

class _LyricsPanel extends StatefulWidget {
  const _LyricsPanel({required this.song, required this.position, super.key});
  final SongModel song;
  final Duration position;

  @override
  State<_LyricsPanel> createState() => _LyricsPanelState();
}

class _LyricsPanelState extends State<_LyricsPanel> {
  late Future<LyricsModel> _lyrics;

  @override
  void initState() {
    super.initState();
    _lyrics = context.read<MusicApiService>().fetchLyrics(widget.song);
  }

  @override
  void didUpdateWidget(covariant _LyricsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.song.id != widget.song.id) {
      _lyrics = context.read<MusicApiService>().fetchLyrics(widget.song);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<LyricsModel>(
      future: _lyrics,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return const Center(child: Text('Lyrics are unavailable right now.', style: TextStyle(color: Colors.white54)));
        }
        final lyrics = snapshot.data ?? const LyricsModel();
        if (lyrics.syncedLines.isNotEmpty) {
          final active = _activeLine(lyrics.syncedLines, widget.position);
          return ListView.builder(
            key: PageStorageKey<String>('synced-${widget.song.id}'),
            padding: const EdgeInsets.fromLTRB(28, 22, 28, 28),
            itemCount: lyrics.syncedLines.length,
            itemBuilder: (context, index) => AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 180),
              style: TextStyle(
                fontSize: index == active ? 22 : 17,
                height: 1.45,
                fontWeight: index == active ? FontWeight.w800 : FontWeight.w500,
                color: index == active ? AppTheme.accent : Colors.white38,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(lyrics.syncedLines[index].text, textAlign: TextAlign.center),
              ),
            ),
          );
        }
        if (lyrics.plainLyrics.trim().isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(28),
              child: Text('No lyrics found for this track.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white54)),
            ),
          );
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 22, 28, 28),
          child: Text(
            lyrics.plainLyrics,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 17, height: 1.75, color: Colors.white70),
          ),
        );
      },
    );
  }

  int _activeLine(List<LyricLine> lines, Duration position) {
    var active = 0;
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].time <= position) {
        active = i;
      } else {
        break;
      }
    }
    return active;
  }
}

class _QueueSheet extends StatelessWidget {
  const _QueueSheet();

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.72,
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 2, 12, 12),
              child: Row(
                children: <Widget>[
                  const Expanded(
                    child: Text('Up next', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                  ),
                  Text('${player.queue.length} tracks', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: player.queue.length <= 1 ? null : player.clearUpNext,
                    child: const Text('Clear up next'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: player.queue.isEmpty
                  ? const Center(child: Text('Queue is empty.', style: TextStyle(color: Colors.white54)))
                  : ReorderableListView.builder(
                      itemCount: player.queue.length,
                      onReorder: (oldIndex, newIndex) {
                        if (newIndex > oldIndex) newIndex--;
                        player.reorderQueue(oldIndex, newIndex);
                      },
                      itemBuilder: (context, index) {
                        final song = player.queue[index];
                        final active = index == player.currentIndex;
                        return ListTile(
                          key: ValueKey<String>('$index-${song.id}'),
                          leading: CoverArt(song: song, size: 44, radius: 12),
                          title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(song.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
                          titleTextStyle: TextStyle(color: active ? AppTheme.accent : Colors.white, fontWeight: active ? FontWeight.w700 : FontWeight.w500),
                          trailing: ReorderableDragStartListener(
                            index: index,
                            child: const Icon(Icons.drag_handle_rounded, color: Colors.white38),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
