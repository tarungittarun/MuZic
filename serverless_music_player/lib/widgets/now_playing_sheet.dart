import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../app_info.dart';
import '../models/audio_quality.dart';
import '../models/lyrics_model.dart';
import '../models/song_model.dart';
import '../providers/player_controller.dart';
import '../services/app_settings_service.dart';
import '../services/app_log.dart';
import '../services/audio_player_service.dart';
import '../services/download_service.dart';
import '../services/video_export_manager.dart';
import '../services/video_library_service.dart';
import '../services/lyrics_language.dart';
import '../services/music_api_service.dart';
import '../services/usage_service.dart';
import '../services/visualizer_service.dart';
import '../theme/app_theme.dart';
import 'cover_art.dart';
import 'visualizer_bars.dart';

class NowPlayingSheet extends StatefulWidget {
  const NowPlayingSheet({super.key});

  @override
  State<NowPlayingSheet> createState() => _NowPlayingSheetState();
}

class _NowPlayingSheetState extends State<NowPlayingSheet> {
  bool _showLyrics = false;
  bool _showVisualizer = false;

  final VisualizerService _visualizer = VisualizerService();

  @override
  void dispose() {
    _visualizer.dispose();
    super.dispose();
  }

  Future<void> _toggleVisualizer(PlayerController player) async {
    if (_showVisualizer) {
      await _visualizer.stop();
      if (mounted) setState(() => _showVisualizer = false);
      return;
    }
    final granted = await _ensureMicrophonePermission();
    if (!mounted) return;
    if (!granted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Android only exposes the live waveform to apps with microphone '
            'access. Grant it to see the visualizer.',
          ),
        ),
      );
      return;
    }
    final sessionId = context.read<AudioPlayerService>().player.androidAudioSessionId;
    _visualizer.start(sessionId);
    setState(() => _showVisualizer = true);
  }

  /// Starts (or stops) the lyric-video render.
  ///
  /// The render itself belongs to [VideoExportManager], so it keeps running
  /// when this sheet is closed and the percentage stays on the export button.
  Future<void> _exportVideo(SongModel song) async {
    final manager = context.read<VideoExportManager>();
    if (manager.isBusy) {
      await _confirmStopExport(manager);
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final player = context.read<PlayerController>();
    final downloads = context.read<DownloadService>();
    final api = context.read<MusicApiService>();
    final settings = context.read<AppSettingsService>();
    final videoLibrary = context.read<VideoLibraryService>();

    try {
      if (!player.isDownloaded(song)) {
        messenger.showSnackBar(
          SnackBar(content: Text('Downloading “${song.title}” for export…')),
        );
        await player.downloadSong(song);
      }
      final audioPath = await downloads.localPathFor(song.id);
      if (audioPath == null) {
        throw StateError('The audio file is not saved on this device yet.');
      }
      LyricsModel? lyrics;
      try {
        final bundle = await api.fetchLyricsVariants(song);
        lyrics = selectLyricsVariant(
          variants: bundle.variants,
          song: song,
          preference: settings.lyricsLanguage,
          override: settings.lyricsLanguageOverrideFor(song.id),
        );
        if (lyrics == null || !lyrics.hasSynced) {
          final synced = bundle.variants.where((v) => v.hasSynced).toList();
          lyrics = synced.isEmpty ? null : synced.first;
        }
      } catch (error) {
        logWarn('video', 'lyrics unavailable for export', <String, Object?>{
          'error': '$error',
        });
      }
      if (!mounted) return;

      // No modal dialog: the job is owned by the manager and its percentage is
      // shown on the export button, so the app stays usable while it renders.
      unawaited(manager.start(song: song, audioPath: audioPath, lyrics: lyrics)
          .then((result) async {
        if (result == null) {
          if (manager.state == VideoExportState.idle && manager.error == null) {
            messenger.showSnackBar(
              const SnackBar(content: Text('Export stopped.')),
            );
          } else if (manager.error != null) {
            messenger.showSnackBar(
              SnackBar(content: Text('Could not export the video: ${manager.error}')),
            );
          }
          return;
        }
        // Remember it so Downloads can show lyric videos separately from
        // ordinary offline audio.
        await videoLibrary.add(
          songId: song.id,
          title: song.title,
          artist: song.artist,
          path: result.path,
          artworkPath: song.localArtworkPath,
          durationMs: song.duration?.inMilliseconds,
        );
        final location = result.path.startsWith('content://')
            ? 'Movies/MuZic'
            : result.path;
        messenger.showSnackBar(
          SnackBar(
            content: Text('Lyric video saved to $location'),
            duration: const Duration(seconds: 8),
          ),
        );
      }));
    } catch (error) {
      final message = error is StateError ? error.message : '$error';
      messenger.showSnackBar(
        SnackBar(content: Text('Could not export the video: $message')),
      );
    }
  }

  /// Tapping the percentage asks whether to stop the render.
  Future<void> _confirmStopExport(VideoExportManager manager) =>
      showExportProgress(context);

  Future<bool> _ensureMicrophonePermission() async {
    try {
      final status = await Permission.microphone.status;
      if (status.isGranted) return true;
      final result = await Permission.microphone.request();
      return result.isGranted;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    final palette = context.palette;
    final song = player.currentSong;
    if (song == null) return const SizedBox.shrink();
    final screenHeight = MediaQuery.sizeOf(context).height;
    final totalMs = player.duration.inMilliseconds;
    final sliderValue = totalMs <= 0
        ? 0.0
        : player.position.inMilliseconds.clamp(0, totalMs).toDouble();

    return Container(
      height: screenHeight * 0.94,
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
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
                color: palette.outline,
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
                  Expanded(
                    child: Column(
                      children: <Widget>[
                        Text('NOW PLAYING',
                            style: TextStyle(
                              fontSize: 10,
                              letterSpacing: 2,
                              color: palette.textMuted,
                              fontWeight: FontWeight.w700,
                            )),
                        const SizedBox(height: 3),
                        const Text(AppInfo.displayName, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  Consumer<VideoExportManager>(
                    builder: (context, export, _) {
                      if (!export.isBusy) {
                        return IconButton(
                          tooltip: 'Export lyric video',
                          onPressed: () => _exportVideo(song),
                          icon: const Icon(Icons.movie_creation_outlined),
                        );
                      }
                      final percent = export.percent;
                      return Tooltip(
                        message: 'Rendering $percent% — tap to stop',
                        child: InkWell(
                          borderRadius: BorderRadius.circular(24),
                          onTap: () => _confirmStopExport(export),
                          child: SizedBox(
                            width: 48,
                            height: 48,
                            child: Stack(
                              alignment: Alignment.center,
                              children: <Widget>[
                                SizedBox(
                                  width: 34,
                                  height: 34,
                                  child: CircularProgressIndicator(
                                    value: percent == 0 ? null : export.progress,
                                    strokeWidth: 2.5,
                                  ),
                                ),
                                Text(
                                  '$percent%',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                    color: Theme.of(context).colorScheme.onSurface,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  IconButton(
                    tooltip: _showVisualizer
                        ? 'Hide visualizer'
                        : 'Show live visualizer',
                    onPressed: () => _toggleVisualizer(player),
                    icon: Icon(
                      _showVisualizer
                          ? Icons.bar_chart_rounded
                          : Icons.graphic_eq_rounded,
                      color: _showVisualizer ? palette.accent : null,
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
              child: Stack(
                children: <Widget>[
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: _showLyrics
                        ? _LyricsPanel(
                            key: ValueKey<String>('lyrics-${song.id}'),
                            song: song,
                            position: player.position,
                          )
                        : _ArtworkPanel(
                            key: ValueKey<String>('art-${song.id}'),
                            song: song,
                          ),
                  ),
                  if (_showVisualizer)
                    Positioned(
                      left: 24,
                      right: 24,
                      bottom: 12,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                        decoration: BoxDecoration(
                          color: palette.surface.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: palette.outline.withValues(alpha: 0.6),
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              'LIVE WAVEFORM',
                              style: TextStyle(
                                fontSize: 9,
                                letterSpacing: 1.6,
                                fontWeight: FontWeight.w800,
                                color: palette.textMuted,
                              ),
                            ),
                            const SizedBox(height: 8),
                            VisualizerBars(service: _visualizer),
                          ],
                        ),
                      ),
                    ),
                ],
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
                            style: TextStyle(color: palette.textSecondary, fontSize: 14)),
                        const SizedBox(height: 6),
                        _QualityChip(song: song),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: player.isFavorite(song) ? 'Unlike' : 'Like',
                    onPressed: () => player.toggleFavorite(song),
                    icon: Icon(
                      player.isFavorite(song) ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                      color: player.isFavorite(song) ? palette.accent : palette.textSecondary,
                    ),
                  ),
                  IconButton(
                    tooltip: player.isDownloaded(song) ? 'Saved offline' : 'Download',
                    onPressed: player.isDownloaded(song) || player.isDownloading || song.isLiveStream
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
                            color: player.isDownloaded(song) ? palette.mint : palette.textSecondary,
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
                        Text(_format(player.position), style: TextStyle(fontSize: 11, color: palette.textMuted)),
                        Text(_format(player.duration), style: TextStyle(fontSize: 11, color: palette.textMuted)),
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
                        color: player.shuffleEnabled ? palette.mint : palette.textMuted),
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
                        backgroundColor: palette.accent,
                        foregroundColor: palette.background,
                        shape: const CircleBorder(),
                        padding: EdgeInsets.zero,
                      ),
                      onPressed: player.togglePlayback,
                      child: player.isBuffering || player.isResolving
                          ? SizedBox(
                              width: 25,
                              height: 25,
                              child: CircularProgressIndicator(strokeWidth: 2.5, color: palette.background),
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
                      color: player.repeatMode == LoopMode.off ? palette.textMuted : palette.mint,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TextButton.icon(
                onPressed: () {
                  final showLyrics = !_showLyrics;
                  if (showLyrics) {
                    unawaited(context.read<UsageService>().recordSongEvent('lyrics_check', song));
                  }
                  setState(() => _showLyrics = showLyrics);
                },
                icon: Icon(_showLyrics ? Icons.album_rounded : Icons.lyrics_outlined, size: 18),
                label: Text(_showLyrics ? 'Show artwork' : 'Lyrics'),
                style: TextButton.styleFrom(foregroundColor: palette.accent),
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
      backgroundColor: context.palette.surface,
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

class _QualityChip extends StatelessWidget {
  const _QualityChip({required this.song});

  final SongModel song;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final quality = describeAudio(song);
    return GestureDetector(
      onTap: () => _showQualitySheet(context, song, quality),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: (quality.isLossless ? palette.mint : palette.accent)
              .withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: (quality.isLossless ? palette.mint : palette.accent)
                .withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              quality.isLossless
                  ? Icons.workspace_premium_rounded
                  : Icons.graphic_eq_rounded,
              size: 11,
              color: quality.isLossless ? palette.mint : palette.accent,
            ),
            const SizedBox(width: 4),
            Text(
              quality.label,
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                color: quality.isLossless ? palette.mint : palette.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showQualitySheet(
    BuildContext context,
    SongModel song,
    AudioQualityInfo quality,
  ) {
    final palette = context.palette;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: palette.surface,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 4, 22, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'Audio quality & signal path',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
              ),
              const SizedBox(height: 14),
              _PathRow('Quality', quality.label),
              _PathRow('Fidelity', quality.detail),
              _PathRow('Source', _sourceName(song)),
              if (song.streamUrl != null)
                _PathRow('Stream host', Uri.tryParse(song.streamUrl!)?.host ?? '—'),
              const SizedBox(height: 10),
              Text(
                'Signal path: stream → device decoder → Android audio mixer. '
                'Note: Android may resample audio to 48 kHz unless a USB DAC '
                'with exclusive output is used.',
                style: TextStyle(color: palette.textMuted, fontSize: 11.5, height: 1.5),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _sourceName(SongModel song) => switch (song.source) {
        SongSource.jioSaavn => 'JioSaavn',
        SongSource.youtube => 'YouTube',
        SongSource.radio => 'Lossless radio',
        SongSource.local => 'Local file',
      };
}

class _PathRow extends StatelessWidget {
  const _PathRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 105,
            child: Text(label,
                style: TextStyle(color: palette.textMuted, fontSize: 11)),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(color: palette.textSecondary, fontSize: 11)),
          ),
        ],
      ),
    );
  }
}

class _ArtworkPanel extends StatelessWidget {
  const _ArtworkPanel({required this.song, super.key});
  final SongModel song;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
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
                  BoxShadow(color: palette.accent.withValues(alpha: 0.12), blurRadius: 42, spreadRadius: 2),
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
  late Future<LyricsBundle> _bundle;

  @override
  void initState() {
    super.initState();
    _bundle = context.read<MusicApiService>().fetchLyricsVariants(widget.song);
  }

  @override
  void didUpdateWidget(covariant _LyricsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.song.id != widget.song.id) {
      _bundle = context.read<MusicApiService>().fetchLyricsVariants(widget.song);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final settings = context.watch<AppSettingsService>();
    final override = settings.lyricsLanguageOverrideFor(widget.song.id);
    return FutureBuilder<LyricsBundle>(
      future: _bundle,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Lyrics are unavailable right now.',
              style: TextStyle(color: palette.textMuted),
            ),
          );
        }
        final variants =
            snapshot.data?.variants ?? const <LyricsModel>[];
        final selected = selectLyricsVariant(
          variants: variants,
          song: widget.song,
          preference: settings.lyricsLanguage,
          override: override.isEmpty ? null : override,
        );
        final languageLabel = selected == null
            ? lyricsLanguageLabel(
                override.isEmpty ? settings.lyricsLanguage : override)
            : selected.languageLabel;
        return Stack(
          children: <Widget>[
            if (selected == null || selected.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Text(
                    'No lyrics available in “$languageLabel” for this track.\n'
                    'Tap the language button to try another one.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: palette.textMuted, height: 1.5),
                  ),
                ),
              )
            else if (selected.hasSynced)
              _SyncedLyricsView(
                lyrics: selected,
                song: widget.song,
                position: widget.position,
              )
            else
              SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(28, 56, 28, 28),
                child: Text(
                  selected.plainLyrics,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 17,
                    height: 1.75,
                    color: palette.textSecondary,
                  ),
                ),
              ),
            Positioned(
              top: 4,
              right: 12,
              child: TextButton.icon(
                onPressed: () => _pickLanguage(context, variants, settings),
                icon: const Icon(Icons.translate_rounded, size: 17),
                label: Text(languageLabel),
                style: TextButton.styleFrom(
                  foregroundColor: palette.accent,
                  backgroundColor: palette.surface.withValues(alpha: 0.85),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _pickLanguage(
    BuildContext context,
    List<LyricsModel> variants,
    AppSettingsService settings,
  ) async {
    final usage = context.read<UsageService>();
    final usable =
        variants.where((variant) => !variant.isEmpty).toList(growable: false);
    final availableLanguages = <String>{
      for (final variant in usable)
        if (!variant.isRomanized) variant.language.toLowerCase(),
    };
    final availableCodes = <String>{
      for (final variant in usable)
        variant.isRomanized ? 'romanized' : variant.language.toLowerCase(),
    };
    final override = settings.lyricsLanguageOverrideFor(widget.song.id);
    final current = override.isEmpty ? settings.lyricsLanguage : override;
    const languageCodes = <String>[
      'english',
      'hindi',
      'telugu',
      'tamil',
      'kannada',
      'malayalam',
      'bengali',
      'punjabi',
      'gujarati',
      'marathi',
      'urdu',
    ];
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: context.palette.surface,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.62,
          maxChildSize: 0.9,
          builder: (sheetContext, scrollController) => ListView(
            controller: scrollController,
            children: <Widget>[
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 4, 20, 2),
                child: Text(
                  'Lyrics language',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: Text(
                  'Choose the script or language this song\'s lyrics should use. '
                  'Available versions play instantly; others fall back to the '
                  'original or a romanized version.',
                  style: TextStyle(
                    color: sheetContext.palette.textMuted,
                    fontSize: 11.5,
                    height: 1.4,
                  ),
                ),
              ),
              const _LanguageSectionLabel(text: 'AVAILABLE FOR THIS TRACK'),
              ListTile(
                leading: const Icon(Icons.tune_rounded),
                title: const Text('Follow default setting'),
                subtitle: Text(lyricsLanguageLabel(settings.lyricsLanguage)),
                trailing: current == settings.lyricsLanguage
                    ? Icon(Icons.check_rounded,
                        color: sheetContext.palette.accent)
                    : null,
                onTap: () => Navigator.pop(sheetContext, '__default__'),
              ),
              for (final variant in usable)
                ListTile(
                  leading: Icon(
                    variant.hasSynced
                        ? Icons.lyrics_rounded
                        : Icons.notes_rounded,
                  ),
                  title: Text(variant.languageLabel),
                  subtitle: Text(variant.displayLabel),
                  trailing: current ==
                          (variant.isRomanized
                              ? 'romanized'
                              : variant.language.toLowerCase())
                      ? Icon(Icons.check_rounded,
                          color: sheetContext.palette.accent)
                      : null,
                  onTap: () => Navigator.pop(
                    sheetContext,
                    variant.isRomanized ? 'romanized' : variant.language,
                  ),
                ),
              const Divider(height: 18),
              _LanguageSectionLabel(text: 'ALL LANGUAGES'),
              ListTile(
                leading: const Icon(Icons.abc_rounded),
                title: const Text('Romanized (Latin letters)'),
                subtitle: Text(
                  availableCodes.contains('romanized')
                      ? 'Provided by the source'
                      : 'Generated from the original script',
                  style: TextStyle(
                    color: sheetContext.palette.textMuted,
                    fontSize: 11.5,
                  ),
                ),
                trailing: current == 'romanized'
                    ? Icon(Icons.check_rounded,
                        color: sheetContext.palette.accent)
                    : null,
                onTap: () => Navigator.pop(sheetContext, 'romanized'),
              ),
              ListTile(
                leading: const Icon(Icons.music_note_rounded),
                title: const Text('Original language'),
                trailing: current == 'original'
                    ? Icon(Icons.check_rounded,
                        color: sheetContext.palette.accent)
                    : null,
                onTap: () => Navigator.pop(sheetContext, 'original'),
              ),
              for (final code in languageCodes)
                ListTile(
                  leading: Icon(
                    availableLanguages.contains(code)
                        ? Icons.check_circle_outline_rounded
                        : Icons.language_rounded,
                    color: availableLanguages.contains(code)
                        ? sheetContext.palette.mint
                        : null,
                  ),
                  title: Text(lyricsLanguageLabel(code)),
                  subtitle: availableLanguages.contains(code)
                      ? Text(
                          'Available for this song',
                          style: TextStyle(
                            color: sheetContext.palette.mint,
                            fontSize: 11,
                          ),
                        )
                      : Text(
                          'Not available — shows original/romanized',
                          style: TextStyle(
                            color: sheetContext.palette.textMuted,
                            fontSize: 11,
                          ),
                        ),
                  trailing: current == code
                      ? Icon(Icons.check_rounded,
                          color: sheetContext.palette.accent)
                      : null,
                  onTap: () => Navigator.pop(sheetContext, code),
                ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
    if (selected == null) return;
    if (selected == '__default__') {
      await settings.setLyricsLanguageOverride(widget.song.id, null);
    } else {
      await settings.setLyricsLanguageOverride(widget.song.id, selected);
      unawaited(
          usage.recordSongEvent('lyrics_check', widget.song, detail: selected));
    }
  }
}

class _LanguageSectionLabel extends StatelessWidget {
  const _LanguageSectionLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Text(
        text,
        style: TextStyle(
          color: context.palette.textMuted,
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.5,
        ),
      ),
    );
  }
}

class _SyncedLyricsView extends StatefulWidget {
  const _SyncedLyricsView({
    required this.lyrics,
    required this.song,
    required this.position,
  });

  final LyricsModel lyrics;
  final SongModel song;
  final Duration position;

  @override
  State<_SyncedLyricsView> createState() => _SyncedLyricsViewState();
}

class _SyncedLyricsViewState extends State<_SyncedLyricsView> {
  /// Fixed row height keeps scroll offsets exact, which is what makes the
  /// auto-scroll smooth (no measuring, no jumping).
  static const double _rowHeight = 62;

  final ScrollController _controller = ScrollController();
  Timer? _resumeTimer;
  bool _userScrolling = false;
  int _lastIndex = -1;

  @override
  void initState() {
    super.initState();
    _lastIndex = _activeIndex(widget.lyrics.syncedLines, widget.position);
    WidgetsBinding.instance.addPostFrameCallback((_) => _animateTo(_lastIndex));
  }

  @override
  void didUpdateWidget(covariant _SyncedLyricsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final index = _activeIndex(widget.lyrics.syncedLines, widget.position);
    if (index != _lastIndex) {
      _lastIndex = index;
      _animateTo(index);
    }
  }

  /// The user takes control the moment they drag; auto-scroll resumes by
  /// itself after a short pause (like most music apps) or instantly on tap.
  bool _onUserScroll(ScrollNotification notification) {
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      setState(() => _userScrolling = true);
      _resumeTimer?.cancel();
    } else if (notification is ScrollEndNotification && _userScrolling) {
      _resumeTimer?.cancel();
      _resumeTimer = Timer(const Duration(seconds: 5), () {
        if (!mounted) return;
        setState(() => _userScrolling = false);
        _animateTo(
          _activeIndex(widget.lyrics.syncedLines, widget.position),
          immediate: true,
        );
      });
    }
    return false;
  }

  void _resumeNow() {
    _resumeTimer?.cancel();
    setState(() => _userScrolling = false);
    _animateTo(
      _activeIndex(widget.lyrics.syncedLines, widget.position),
      immediate: true,
    );
  }

  void _animateTo(int index, {bool immediate = false}) {
    if (!_controller.hasClients || index < 0) return;
    final position = _controller.position;
    final viewport = position.viewportDimension;
    final target = (index * _rowHeight) - (viewport * 0.38) + (_rowHeight / 2);
    final clamped = target.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((position.pixels - clamped).abs() < 2) return;
    _controller.animateTo(
      clamped,
      duration: Duration(milliseconds: immediate ? 260 : 420),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _resumeTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final lines = widget.lyrics.syncedLines;
    final active = _activeIndex(lines, widget.position);
    return Stack(
      children: <Widget>[
        NotificationListener<ScrollNotification>(
          onNotification: _onUserScroll,
          child: ListView.builder(
            controller: _controller,
            padding: const EdgeInsets.fromLTRB(24, 40, 24, 40),
            itemExtent: _rowHeight,
            itemCount: lines.length,
            itemBuilder: (context, index) {
              final isActive = index == active;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  if (_userScrolling) _resumeNow();
                },
                child: Center(
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeOut,
                    style: TextStyle(
                      fontSize: isActive ? 21 : 16.5,
                      height: 1.3,
                      fontWeight:
                          isActive ? FontWeight.w800 : FontWeight.w500,
                      color: isActive
                          ? palette.accent
                          : palette.textMuted.withValues(alpha: 0.5),
                    ),
                    child: Text(
                      lines[index].text,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (_userScrolling)
          Positioned(
            bottom: 10,
            right: 18,
            child: FilledButton.tonalIcon(
              onPressed: _resumeNow,
              icon: const Icon(Icons.sync_rounded, size: 16),
              label: const Text('Resume auto-scroll'),
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                textStyle: const TextStyle(fontSize: 11),
              ),
            ),
          ),
      ],
    );
  }

  int _activeIndex(List<LyricLine> lines, Duration position) {
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
    final palette = context.palette;
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
                  Text('${player.queue.length} tracks', style: TextStyle(color: palette.textMuted, fontSize: 12)),
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
                  ? Center(child: Text('Queue is empty.', style: TextStyle(color: palette.textMuted)))
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
                          titleTextStyle: TextStyle(color: active ? palette.accent : palette.textPrimary, fontWeight: active ? FontWeight.w700 : FontWeight.w500),
                          trailing: ReorderableDragStartListener(
                            index: index,
                            child: Icon(Icons.drag_handle_rounded, color: palette.textMuted),
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


/// Bottom sheet that shows an in-flight lyric-video render and offers to stop
/// it. Reachable from the player's export button and from the mini player, so
/// the percentage is always one tap away even after closing the player.
Future<void> showExportProgress(BuildContext context) async {
  final manager = context.read<VideoExportManager>();
  final stop = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Text(
              'Rendering lyric video',
              style: Theme.of(sheetContext).textTheme.titleMedium,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: AnimatedBuilder(
              animation: manager,
              builder: (context, _) {
                if (!manager.isBusy) {
                  return const Text('Finished — check Downloads for the video.');
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    LinearProgressIndicator(
                      value: manager.percent == 0 ? null : manager.progress,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '${manager.percent}% complete · ${manager.songTitle ?? ''}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'It keeps rendering in the background while you use the app.',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.palette.textMuted,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          ListTile(
            leading: const Icon(Icons.stop_circle_outlined),
            title: const Text('Stop exporting'),
            subtitle: const Text('The partial file is discarded.'),
            onTap: () => Navigator.of(sheetContext).pop(true),
          ),
          ListTile(
            leading: const Icon(Icons.play_arrow_rounded),
            title: const Text('Keep rendering'),
            onTap: () => Navigator.of(sheetContext).pop(false),
          ),
          const SizedBox(height: 6),
        ],
      ),
    ),
  );
  if (stop == true) await manager.cancel();
}
