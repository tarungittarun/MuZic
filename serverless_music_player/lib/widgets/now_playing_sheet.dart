import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'animated_rhythm_icon.dart';
import 'media_controller_card.dart';
import 'song_tile.dart';
import 'visualizer_bars.dart';

class NowPlayingSheet extends StatefulWidget {
  const NowPlayingSheet({super.key});

  @override
  State<NowPlayingSheet> createState() => _NowPlayingSheetState();
}

class _NowPlayingSheetState extends State<NowPlayingSheet>
    with TickerProviderStateMixin {
  static const double _playerMinExtent = 0.50;

  bool _showLyrics = false;
  bool _showVisualizer = false;
  bool _sheetDismissRequested = false;
  bool _controlActionTapped = false;
  int? _sheetPointer;
  Offset? _sheetPointerStartPosition;
  double? _sheetPointerStartExtent;
  bool _sheetPointerStartedAtScrollTop = false;
  ScrollController? _sheetScrollController;
  Timer? _controlResetTimer;

  final VisualizerService _visualizer = VisualizerService();
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();
  final ScrollController _controlStripController = ScrollController();
  late final AnimationController _controlReturnAnimation;

  @override
  void initState() {
    super.initState();
    _controlReturnAnimation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2300),
    );
    // The waveform choice is remembered: if it was on for the last song it
    // comes back on for this one (and every song after) until turned off.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (context.read<AppSettingsService>().liveVisualizerEnabled) {
        setState(() => _showVisualizer = true);
        unawaited(_startVisualizerCapture(requestPermission: false));
      }
    });
  }

  @override
  void dispose() {
    _controlResetTimer?.cancel();
    _controlReturnAnimation.dispose();
    _controlStripController.dispose();
    _sheetController.dispose();
    _visualizer.dispose();
    super.dispose();
  }

  bool _isScrollAtTop(ScrollController? controller) =>
      controller == null ||
      !controller.hasClients ||
      controller.position.extentBefore <= 0.5;

  void _handleSheetPointerDown(PointerDownEvent event) {
    _sheetPointer = event.pointer;
    _sheetPointerStartPosition = event.position;
    _sheetPointerStartExtent = _sheetController.isAttached
        ? _sheetController.size
        : null;
    _sheetPointerStartedAtScrollTop = _isScrollAtTop(_sheetScrollController);
    _sheetDismissRequested = false;
  }

  void _handleSheetPointerMove(PointerMoveEvent event) {
    if (_sheetPointer != event.pointer || _sheetDismissRequested) return;
    final start = _sheetPointerStartPosition;
    final startExtent = _sheetPointerStartExtent;
    if (start == null || startExtent == null) return;
    final movement = event.position - start;
    if (startExtent <= _playerMinExtent + 0.01 &&
        _sheetPointerStartedAtScrollTop &&
        movement.dy >= 72 &&
        movement.dy >= movement.dx.abs() * 1.2 &&
        _sheetController.isAttached &&
        _sheetController.size <= _playerMinExtent + 0.015 &&
        _isScrollAtTop(_sheetScrollController)) {
      _sheetDismissRequested = true;
      Navigator.of(context).pop();
    }
  }

  void _handleSheetPointerEnd(PointerEvent event) {
    if (_sheetPointer != event.pointer) return;
    _sheetPointer = null;
    _sheetPointerStartPosition = null;
    _sheetPointerStartExtent = null;
    _sheetDismissRequested = false;
  }

  bool _handleControlStripScroll(ScrollNotification notification) {
    if (notification.metrics.axis == Axis.horizontal &&
        notification is ScrollUpdateNotification &&
        notification.dragDetails != null) {
      _controlActionTapped = false;
      _stopControlReturnMotion();
      _scheduleControlStripReset();
    }
    return false;
  }

  void _stopControlReturnMotion() {
    _controlReturnAnimation.stop();
    _controlReturnAnimation.value = 0;
  }

  void _markControlActionTapped() {
    _controlActionTapped = true;
    _controlResetTimer?.cancel();
    _stopControlReturnMotion();
    if (_controlStripController.hasClients &&
        _controlStripController.position.isScrollingNotifier.value) {
      _controlStripController.jumpTo(_controlStripController.offset);
    }
  }

  void _scheduleControlStripReset() {
    _controlResetTimer?.cancel();
    _controlActionTapped = false;
    _controlResetTimer = Timer(const Duration(milliseconds: 2500), () {
      if (!mounted ||
          _controlActionTapped ||
          !_controlStripController.hasClients) {
        return;
      }
      final position = _controlStripController.position;
      final restingOffset = position.minScrollExtent;
      // Always return to the actual leading edge. Using the current pixel
      // offset as the target made the return work only from one side.
      if ((position.pixels - restingOffset).abs() < 1) return;
      unawaited(_controlReturnAnimation.forward(from: 0));
      unawaited(
        _controlStripController.animateTo(
          restingOffset,
          duration: const Duration(milliseconds: 2500),
          curve: Curves.easeInOutCubic,
        ),
      );
    });
  }

  Future<void> _startVisualizerCapture({
    required bool requestPermission,
  }) async {
    if (requestPermission) {
      final granted = await _ensureMicrophonePermission();
      if (!mounted) return;
      if (!granted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Live waveform capture needs microphone access on this device. '
              'Grant access to enable it.',
            ),
          ),
        );
        return;
      }
    } else {
      final status = await Permission.microphone.status;
      if (!mounted || !status.isGranted) return;
    }
    final sessionId = context
        .read<AudioPlayerService>()
        .player
        .androidAudioSessionId;
    _visualizer.start(sessionId);
  }

  Future<void> _toggleVisualizer(PlayerController player) async {
    final settings = context.read<AppSettingsService>();
    if (_showVisualizer) {
      await _visualizer.stop();
      await settings.setLiveVisualizerEnabled(false);
      if (mounted) setState(() => _showVisualizer = false);
      return;
    }
    await _startVisualizerCapture(requestPermission: true);
    if (!mounted) return;
    final status = await Permission.microphone.status;
    if (!status.isGranted) return;
    await settings.setLiveVisualizerEnabled(true);
    if (mounted) setState(() => _showVisualizer = true);
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
      unawaited(
        manager.start(song: song, audioPath: audioPath, lyrics: lyrics).then((
          result,
        ) async {
          if (result == null) {
            if (manager.state == VideoExportState.idle &&
                manager.error == null) {
              messenger.showSnackBar(
                const SnackBar(content: Text('Export stopped.')),
              );
            } else if (manager.error != null) {
              messenger.showSnackBar(
                const SnackBar(
                  content: Text(
                    'Could not export the video. Please try again.',
                  ),
                ),
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
        }),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Could not export the video. Please try again.'),
        ),
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
    final estimatedNonCardHeight =
        78.0 + (_showVisualizer ? 100.0 : 0.0) + 100.0 + 80.0 + 8.0;
    final availableCardHeight = screenHeight * 0.94 - estimatedNonCardHeight;
    // The artwork card used to consume every remaining pixel. Keep it about
    // one fifth smaller while reserving room for the controls below it.
    final cardHeight = (availableCardHeight * 0.80)
        .clamp(screenHeight * 0.30, screenHeight * 0.64)
        .toDouble();

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handleSheetPointerDown,
      onPointerMove: _handleSheetPointerMove,
      onPointerUp: _handleSheetPointerEnd,
      onPointerCancel: _handleSheetPointerEnd,
      child: _SheetSnapHaptics(
        stopExtents: const <double>[_playerMinExtent],
        child: DraggableScrollableSheet(
          controller: _sheetController,
          initialChildSize: 0.94,
          minChildSize: _playerMinExtent,
          maxChildSize: 0.94,
          snap: true,
          shouldCloseOnMinExtent: false,
          expand: false,
          builder: (context, scrollController) {
            _sheetScrollController = scrollController;
            return ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(30),
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: <Color>[
                      Color.alphaBlend(
                        palette.accent.withValues(alpha: 0.10),
                        palette.background,
                      ),
                      palette.background,
                      Color.alphaBlend(
                        palette.mint.withValues(alpha: 0.05),
                        palette.background,
                      ),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: CustomScrollView(
                    controller: scrollController,
                    physics: const AlwaysScrollableScrollPhysics(
                      parent: ClampingScrollPhysics(),
                    ),
                    slivers: <Widget>[
                      SliverToBoxAdapter(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
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
                                    icon: const Icon(
                                      Icons.keyboard_arrow_down_rounded,
                                      size: 30,
                                    ),
                                  ),
                                  Expanded(
                                    child: Column(
                                      children: <Widget>[
                                        Text(
                                          'NOW PLAYING',
                                          style: TextStyle(
                                            fontSize: 10,
                                            letterSpacing: 2,
                                            color: palette.textMuted,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        const Text(
                                          AppInfo.displayName,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  _buildDownloadButton(context, player, song),
                                  Consumer<VideoExportManager>(
                                    builder: (context, export, _) {
                                      if (!export.isBusy) {
                                        return IconButton(
                                          tooltip: 'Export lyric video',
                                          onPressed: () => _exportVideo(song),
                                          icon: const Icon(
                                            Icons.movie_creation_outlined,
                                          ),
                                        );
                                      }
                                      final percent = export.percent;
                                      return Tooltip(
                                        message:
                                            'Rendering $percent% — tap to stop',
                                        child: InkWell(
                                          borderRadius: BorderRadius.circular(
                                            24,
                                          ),
                                          onTap: () =>
                                              _confirmStopExport(export),
                                          child: SizedBox(
                                            width: 48,
                                            height: 48,
                                            child: Stack(
                                              alignment: Alignment.center,
                                              children: <Widget>[
                                                SizedBox(
                                                  width: 34,
                                                  height: 34,
                                                  child:
                                                      CircularProgressIndicator(
                                                        value: percent == 0
                                                            ? null
                                                            : export.progress,
                                                        strokeWidth: 2.5,
                                                      ),
                                                ),
                                                Text(
                                                  '$percent%',
                                                  style: TextStyle(
                                                    fontSize: 9,
                                                    fontWeight: FontWeight.w800,
                                                    color: Theme.of(
                                                      context,
                                                    ).colorScheme.onSurface,
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
                                        ? 'Hide live waveform'
                                        : 'Show live waveform',
                                    onPressed: () => _toggleVisualizer(player),
                                    icon: AnimatedRhythmIcon(
                                      active:
                                          _showVisualizer && player.isPlaying,
                                      color: _showVisualizer
                                          ? palette.accent
                                          : palette.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Column(
                          children: <Widget>[
                            Expanded(
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  final available = (constraints.maxHeight - 10)
                                      .clamp(0.0, double.infinity)
                                      .toDouble();
                                  final displayHeight = available < cardHeight
                                      ? available
                                      : cardHeight;
                                  final artworkOrLyrics = _showLyrics
                                      ? Stack(
                                          fit: StackFit.expand,
                                          children: <Widget>[
                                            _LyricsPanel(
                                              key: ValueKey<String>(
                                                'lyrics-${song.id}',
                                              ),
                                              song: song,
                                              position: player.position,
                                            ),
                                            Positioned(
                                              top: 8,
                                              left: 12,
                                              child: IconButton(
                                                tooltip: 'Show artwork',
                                                onPressed: () => setState(
                                                  () => _showLyrics = false,
                                                ),
                                                style: IconButton.styleFrom(
                                                  foregroundColor:
                                                      palette.accent,
                                                  backgroundColor: palette
                                                      .surface
                                                      .withValues(alpha: 0.88),
                                                ),
                                                icon: const Icon(
                                                  Icons.album_rounded,
                                                ),
                                              ),
                                            ),
                                          ],
                                        )
                                      : MediaArtworkCard(
                                          key: ValueKey<String>(
                                            'card-${song.id}',
                                          ),
                                          song: song,
                                          onLyricsTap: () =>
                                              _toggleLyrics(song),
                                        );
                                  return Center(
                                    child: SizedBox(
                                      width: double.infinity,
                                      height: displayHeight,
                                      child: Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                          16,
                                          4,
                                          16,
                                          6,
                                        ),
                                        child: AnimatedSwitcher(
                                          duration: const Duration(
                                            milliseconds: 220,
                                          ),
                                          child: KeyedSubtree(
                                            key: ValueKey<String>(
                                              _showLyrics
                                                  ? 'lyrics-${song.id}'
                                                  : 'card-${song.id}',
                                            ),
                                            child: artworkOrLyrics,
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                            if (_showVisualizer)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  24,
                                  4,
                                  24,
                                  6,
                                ),
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.fromLTRB(
                                    14,
                                    10,
                                    14,
                                    10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: palette.surface.withValues(
                                      alpha: 0.92,
                                    ),
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(
                                      color: palette.outline.withValues(
                                        alpha: 0.6,
                                      ),
                                    ),
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Row(
                                        children: <Widget>[
                                          AnimatedRhythmIcon(
                                            active: player.isPlaying,
                                            color: palette.accent,
                                            size: 16,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            'LIVE WAVEFORM',
                                            style: TextStyle(
                                              fontSize: 9,
                                              letterSpacing: 1.6,
                                              fontWeight: FontWeight.w800,
                                              color: palette.textMuted,
                                            ),
                                          ),
                                          const Spacer(),
                                          Text(
                                            'On for every song',
                                            style: TextStyle(
                                              fontSize: 9,
                                              color: palette.textMuted,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      VisualizerBars(
                                        bands: _visualizer.bands,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            MediaTransportControls(
                              leadingControl: _QualityChip(
                                song: song,
                                onBeforeTap: _markControlActionTapped,
                              ),
                              isPlaying: player.isPlaying,
                              isBusy:
                                  player.isBuffering || player.isResolving,
                              position: player.position,
                              duration: player.duration,
                              onPlayPause: player.togglePlayback,
                              onNext: player.next,
                              onPrevious: player.previous,
                              onSeek: player.seek,
                            ),
                            _buildControlStrip(context, player, song, palette),
                            const SizedBox(height: 8),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _staggerControl(Widget child, int index) => AnimatedBuilder(
    animation: _controlReturnAnimation,
    child: child,
    builder: (context, child) {
      final start = index * 0.09;
      final progress = Interval(
        start,
        start + 0.36,
        curve: Curves.easeInOutCubic,
      ).transform(_controlReturnAnimation.value);
      final pulse = 1 - (progress * 2 - 1).abs();
      return Transform.translate(
        offset: Offset(0, -4 * pulse),
        child: Transform.scale(scale: 1 + 0.03 * pulse, child: child),
      );
    },
  );

  Widget _buildControlStrip(
    BuildContext context,
    PlayerController player,
    SongModel song,
    AppPalette palette,
  ) {
    final favorite = player.isFavorite(song);
    final repeatEnabled = player.repeatMode != LoopMode.off;
    final repeatTooltip = 'Repeat mode: ${_repeatLabel(player.repeatMode)}';

    return SizedBox(
      height: 80,
      child: NotificationListener<ScrollNotification>(
        onNotification: _handleControlStripScroll,
        child: SingleChildScrollView(
          controller: _controlStripController,
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(
            children: <Widget>[
              _staggerControl(
                _PlayerActionButton(
                  icon: Icons.shuffle_rounded,
                  label: 'Shuffle',
                  tooltip: 'Shuffle ${player.shuffleEnabled ? 'on' : 'off'}',
                  selected: player.shuffleEnabled,
                  color: player.shuffleEnabled
                      ? palette.mint
                      : palette.textSecondary,
                  onTap: () {
                    _markControlActionTapped();
                    player.toggleShuffle();
                  },
                ),
                0,
              ),
              const SizedBox(width: 6),
              _staggerControl(
                _PlayerActionButton(
                  icon: player.repeatMode == LoopMode.one
                      ? Icons.repeat_one_rounded
                      : Icons.repeat_rounded,
                  label: player.repeatMode == LoopMode.one
                      ? 'Repeat 1'
                      : 'Repeat',
                  tooltip: repeatTooltip,
                  selected: repeatEnabled,
                  color: repeatEnabled ? palette.mint : palette.textSecondary,
                  onTap: () {
                    _markControlActionTapped();
                    player.cycleRepeatMode();
                  },
                ),
                1,
              ),
              const SizedBox(width: 6),
              _staggerControl(
                _PlayerActionButton(
                  icon: favorite
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  label: favorite ? 'Liked' : 'Like',
                  tooltip: favorite ? 'Unlike track' : 'Like track',
                  selected: favorite,
                  color: favorite ? palette.accent : palette.textSecondary,
                  onTap: () {
                    _markControlActionTapped();
                    player.toggleFavorite(song);
                  },
                ),
                2,
              ),
              const SizedBox(width: 6),
              _staggerControl(
                _PlayerActionButton(
                  icon: Icons.queue_music_rounded,
                  label: 'Up next',
                  tooltip: 'Open the upcoming queue',
                  selected: false,
                  color: palette.accent,
                  onTap: () {
                    _markControlActionTapped();
                    _showQueue(context);
                  },
                ),
                3,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDownloadButton(
    BuildContext context,
    PlayerController player,
    SongModel song,
  ) {
    final downloaded = player.isDownloaded(song);
    final progress = player.downloadProgressFor(song);
    final isDownloadingThisSong = progress != null;
    final canDownload =
        !downloaded && !player.isDownloading && !song.isLiveStream;
    final tooltip = downloaded
        ? 'Saved offline'
        : isDownloadingThisSong
        ? 'Downloading'
        : player.isDownloading
        ? 'Another download is in progress'
        : 'Download track';

    return IconButton(
      tooltip: tooltip,
      onPressed: canDownload
          ? () => unawaited(_download(context, song))
          : null,
      icon: progress == null
          ? Icon(
              downloaded ? Icons.download_done_rounded : Icons.download_rounded,
              color: downloaded ? context.palette.mint : null,
            )
          : SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                value: progress == 0 ? null : progress,
                strokeWidth: 2,
              ),
            ),
    );
  }

  void _toggleLyrics(SongModel song) {
    unawaited(
      context.read<UsageService>().recordSongEvent('lyrics_check', song),
    );
    setState(() => _showLyrics = true);
  }

  Future<void> _download(BuildContext context, SongModel song) async {
    try {
      await context.read<PlayerController>().downloadSong(song);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Download failed. Please try again.')),
        );
      }
    }
  }

  Future<void> _showQueue(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      enableDrag: false,
      barrierColor: Colors.black.withValues(alpha: 0.28),
      backgroundColor: Colors.transparent,
      builder: (_) => const _QueueSheet(),
    );
  }

  static String _repeatLabel(LoopMode mode) => switch (mode) {
    LoopMode.off => 'off',
    LoopMode.all => 'all',
    LoopMode.one => 'one',
  };
}

class _PlayerActionButton extends StatelessWidget {
  const _PlayerActionButton({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.color,
    required this.onTap,
    this.selected = false,
    this.enabled = true,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;
  final bool selected;
  final bool enabled;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final tint = enabled ? color : color.withValues(alpha: 0.42);
    return SizedBox(
      width: 84,
      height: 68,
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: selected ? color.withValues(alpha: 0.10) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                trailing ?? Icon(icon, size: 21, color: tint),
                const SizedBox(height: 3),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tint,
                    fontSize: 9.5,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QualityChip extends StatelessWidget {
  const _QualityChip({required this.song, required this.onBeforeTap});

  final SongModel song;
  final VoidCallback onBeforeTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final quality = describeAudio(song);
    final qualityColor = quality.isLossless ? palette.mint : palette.accent;
    return SizedBox(
      width: 82,
      height: 68,
      child: Tooltip(
        message: '${quality.label} · ${quality.detail}',
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () {
              onBeforeTap();
              _showQualitySheet(context, song, quality);
            },
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: qualityColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: qualityColor.withValues(alpha: 0.35),
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
                        color: qualityColor,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          quality.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: qualityColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Quality',
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
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
              _PathRow(
                'Delivery',
                song.source == SongSource.local
                    ? 'Local file'
                    : 'Network stream',
              ),
              const SizedBox(height: 10),
              Text(
                'Signal path: stream → device decoder → audio mixer. '
                'The device may resample audio to 48 kHz unless a USB DAC '
                'with exclusive output is used.',
                style: TextStyle(
                  color: palette.textMuted,
                  fontSize: 11.5,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _sourceName(SongModel song) => switch (song.source) {
    SongSource.jioSaavn => 'Source A',
    SongSource.youtube => 'Source B',
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
            child: Text(
              label,
              style: TextStyle(color: palette.textMuted, fontSize: 11),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(color: palette.textSecondary, fontSize: 11),
            ),
          ),
        ],
      ),
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
  LyricsModel? _primary;
  List<LyricsModel> _variants = const <LyricsModel>[];
  bool _loading = true;
  bool _failed = false;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _load(widget.song);
  }

  @override
  void didUpdateWidget(covariant _LyricsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.song.id != widget.song.id) {
      _primary = null;
      _variants = const <LyricsModel>[];
      _loading = true;
      _failed = false;
      _load(widget.song);
    }
  }

  Future<void> _load(SongModel song) async {
    final generation = ++_loadGeneration;
    final api = context.read<MusicApiService>();

    bool stillCurrent() =>
        mounted && generation == _loadGeneration && song.id == widget.song.id;

    LyricsModel? primary;
    try {
      primary = await api.fetchLyrics(song);
      if (!stillCurrent()) return;
      setState(() {
        _primary = primary;
        if (primary != null && !primary.isEmpty) _loading = false;
      });
    } catch (_) {
      // The full variant fetch below can still recover through catalogue or
      // Source A fallbacks, so do not show an error yet.
    }

    try {
      final bundle = await api.fetchLyricsVariants(song);
      if (!stillCurrent()) return;
      setState(() {
        _variants = bundle.variants;
        _loading = false;
        _failed = bundle.isEmpty && (primary?.isEmpty ?? true);
      });
    } catch (_) {
      if (!stillCurrent()) return;
      setState(() {
        _loading = false;
        _failed = _primary?.isEmpty ?? true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final settings = context.watch<AppSettingsService>();
    final override = settings.lyricsLanguageOverrideFor(widget.song.id);
    final loadedVariants = _variants
        .where((variant) => !variant.isEmpty)
        .toList(growable: false);
    final variants = loadedVariants.isNotEmpty
        ? loadedVariants
        : (_primary != null && !_primary!.isEmpty
              ? <LyricsModel>[_primary!]
              : const <LyricsModel>[]);
    if (_loading && variants.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_failed && variants.isEmpty) {
      return Center(
        child: Text(
          'Lyrics are unavailable right now.',
          style: TextStyle(color: palette.textMuted),
        ),
      );
    }
    {
      final selected = selectLyricsVariant(
        variants: variants,
        song: widget.song,
        preference: settings.lyricsLanguage,
        override: override.isEmpty ? null : override,
      );
      final languageLabel = selected == null
          ? lyricsLanguageLabel(
              override.isEmpty ? settings.lyricsLanguage : override,
            )
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
    }
  }

  Future<void> _pickLanguage(
    BuildContext context,
    List<LyricsModel> variants,
    AppSettingsService settings,
  ) async {
    final usage = context.read<UsageService>();
    final usable = variants
        .where((variant) => !variant.isEmpty)
        .toList(growable: false);
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
                    ? Icon(
                        Icons.check_rounded,
                        color: sheetContext.palette.accent,
                      )
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
                  trailing:
                      current ==
                          (variant.isRomanized
                              ? 'romanized'
                              : variant.language.toLowerCase())
                      ? Icon(
                          Icons.check_rounded,
                          color: sheetContext.palette.accent,
                        )
                      : null,
                  onTap: () => Navigator.pop(
                    sheetContext,
                    variant.isRomanized ? 'romanized' : variant.language,
                  ),
                ),
              const Divider(height: 18),
              const _LanguageSectionLabel(text: 'ALL LANGUAGES'),
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
                    ? Icon(
                        Icons.check_rounded,
                        color: sheetContext.palette.accent,
                      )
                    : null,
                onTap: () => Navigator.pop(sheetContext, 'romanized'),
              ),
              ListTile(
                leading: const Icon(Icons.music_note_rounded),
                title: const Text('Original language'),
                trailing: current == 'original'
                    ? Icon(
                        Icons.check_rounded,
                        color: sheetContext.palette.accent,
                      )
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
                      ? Icon(
                          Icons.check_rounded,
                          color: sheetContext.palette.accent,
                        )
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
        usage.recordSongEvent('lyrics_check', widget.song, detail: selected),
      );
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
                      fontWeight: isActive ? FontWeight.w800 : FontWeight.w500,
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

class _QueueSheet extends StatefulWidget {
  const _QueueSheet();

  @override
  State<_QueueSheet> createState() => _QueueSheetState();
}

class _QueueSheetState extends State<_QueueSheet> {
  static const double _minExtent = 0.30;
  static const double _maxExtent = 0.80;

  final DraggableScrollableController _sheetController =
      DraggableScrollableController();
  ScrollController? _queueScrollController;
  Offset? _pointerStart;
  int? _pointerId;
  double? _pointerStartExtent;
  bool _pointerStartedAtListTop = false;
  double? _headerStartExtent;
  double _headerDragDistance = 0;
  bool _dismissRequested = false;

  @override
  void dispose() {
    _sheetController.dispose();
    super.dispose();
  }

  bool _queueIsAtTop() =>
      _queueScrollController == null ||
      !_queueScrollController!.hasClients ||
      _queueScrollController!.position.extentBefore <= 0.5;

  void _handlePointerDown(PointerDownEvent event) {
    _pointerId = event.pointer;
    _pointerStart = event.position;
    _pointerStartExtent = _sheetController.isAttached
        ? _sheetController.size
        : null;
    _pointerStartedAtListTop = _queueIsAtTop();
    _dismissRequested = false;
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (_pointerId != event.pointer || _dismissRequested) return;
    final start = _pointerStart;
    final startExtent = _pointerStartExtent;
    if (start == null || startExtent == null || !_sheetController.isAttached) {
      return;
    }
    final movement = event.position - start;
    if (startExtent <= _minExtent + 0.01 &&
        _pointerStartedAtListTop &&
        movement.dy >= 72 &&
        movement.dy >= movement.dx.abs() * 1.2 &&
        _sheetController.size <= _minExtent + 0.015 &&
        _queueIsAtTop()) {
      // The first downward gesture settles at the 30% detent. Only a fresh
      // downward gesture, started from that detent, dismisses the queue.
      _dismissRequested = true;
      Navigator.of(context).pop();
    }
  }

  void _handlePointerEnd(PointerEvent event) {
    if (_pointerId != event.pointer) return;
    _pointerId = null;
    _pointerStart = null;
    _pointerStartExtent = null;
    _dismissRequested = false;
  }

  void _startHeaderDrag(DragStartDetails details) {
    _headerStartExtent = _sheetController.isAttached
        ? _sheetController.size
        : null;
    _headerDragDistance = 0;
  }

  void _updateHeaderDrag(DragUpdateDetails details) {
    if (!_sheetController.isAttached) return;
    _headerDragDistance += details.delta.dy;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final next = (_sheetController.size - details.delta.dy / screenHeight)
        .clamp(_minExtent, _maxExtent)
        .toDouble();
    _sheetController.jumpTo(next);
  }

  void _settleHeaderDrag(DragEndDetails details) {
    if (!mounted ||
        _dismissRequested ||
        !_sheetController.isAttached ||
        _headerStartExtent == null) {
      return;
    }
    final velocity = details.primaryVelocity ?? 0;
    final current = _sheetController.size;
    final double target;
    if (velocity > 520 || _headerDragDistance > 38) {
      target = _minExtent;
    } else if (velocity < -520 || _headerDragDistance < -38) {
      target = _maxExtent;
    } else {
      target = current < (_minExtent + _maxExtent) / 2
          ? _minExtent
          : _maxExtent;
    }
    unawaited(
      _sheetController.animateTo(
        target,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final player = context.watch<PlayerController>();
    final queue = player.queue;
    final currentIndex = player.currentIndex ?? -1;
    final upcomingStart = (currentIndex + 1).clamp(0, queue.length).toInt();
    final upcoming = upcomingStart >= queue.length
        ? const <SongModel>[]
        : queue.sublist(upcomingStart);

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerEnd,
      onPointerCancel: _handlePointerEnd,
      child: _SheetSnapHaptics(
        stopExtents: const <double>[_minExtent],
        child: DraggableScrollableSheet(
          controller: _sheetController,
          initialChildSize: _maxExtent,
          minChildSize: _minExtent,
          maxChildSize: _maxExtent,
          snap: true,
          shouldCloseOnMinExtent: false,
          expand: false,
          builder: (context, scrollController) {
            _queueScrollController = scrollController;
            return DecoratedBox(
              decoration: BoxDecoration(
                color: palette.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
                border: Border.all(
                  color: palette.outline.withValues(alpha: 0.75),
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.22),
                    blurRadius: 22,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
                child: SafeArea(
                  top: false,
                  child: Column(
                    children: <Widget>[
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onVerticalDragStart: _startHeaderDrag,
                        onVerticalDragUpdate: _updateHeaderDrag,
                        onVerticalDragEnd: _settleHeaderDrag,
                        child: Column(
                          children: <Widget>[
                            const SizedBox(height: 10),
                            Container(
                              width: 40,
                              height: 4,
                              decoration: BoxDecoration(
                                color: palette.outline,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 7, 4, 8),
                              child: Row(
                                children: <Widget>[
                                  const Expanded(
                                    child: Text(
                                      'Up next',
                                      style: TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    upcoming.isEmpty
                                        ? 'Nothing queued'
                                        : '${upcoming.length} next',
                                    style: TextStyle(
                                      color: palette.textMuted,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  TextButton.icon(
                                    onPressed: upcoming.isEmpty
                                        ? null
                                        : () => player.clearUpNext(),
                                    icon: const Icon(
                                      Icons.clear_all_rounded,
                                      size: 18,
                                    ),
                                    label: const Text('Clear'),
                                  ),
                                  IconButton(
                                    tooltip: 'Close queue',
                                    onPressed: () => Navigator.pop(context),
                                    icon: const Icon(Icons.close_rounded),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: upcoming.isEmpty
                            ? ListView(
                                controller: scrollController,
                                physics: const AlwaysScrollableScrollPhysics(
                                  parent: ClampingScrollPhysics(),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 28,
                                ),
                                children: const <Widget>[
                                  SizedBox(height: 220, child: _EmptyUpNext()),
                                ],
                              )
                            : ReorderableListView.builder(
                                scrollController: scrollController,
                                physics: const AlwaysScrollableScrollPhysics(
                                  parent: ClampingScrollPhysics(),
                                ),
                                buildDefaultDragHandles: false,
                                itemCount: upcoming.length,
                                // onReorderItem already reports the final
                                // index after removing the dragged row.
                                onReorderItem: (oldIndex, newIndex) {
                                  player.reorderQueue(
                                    upcomingStart + oldIndex,
                                    upcomingStart + newIndex,
                                  );
                                },
                                itemBuilder: (context, index) {
                                  final song = upcoming[index];
                                  final globalIndex = upcomingStart + index;
                                  final recommended = player.recommendationIds
                                      .contains(song.id);
                                  final reason = recommended
                                      ? player.recommendationReasonFor(song)
                                      : '';
                                  return ReorderableDelayedDragStartListener(
                                    key: ValueKey<String>('up-next-${song.id}'),
                                    index: index,
                                    child: SongTile(
                                      song: song,
                                      subtitleOverride: recommended
                                          ? <String>[
                                              'Recommended',
                                              if (reason.isNotEmpty) reason,
                                            ].join(' • ')
                                          : null,
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: <Widget>[
                                          if (recommended)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                right: 2,
                                              ),
                                              child: Icon(
                                                Icons.auto_awesome_rounded,
                                                size: 16,
                                                color: palette.accent,
                                              ),
                                            ),
                                          const Icon(Icons.drag_handle_rounded),
                                        ],
                                      ),
                                      onTap: () =>
                                          player.playAtQueueIndex(globalIndex),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SheetSnapHaptics extends StatefulWidget {
  const _SheetSnapHaptics({required this.stopExtents, required this.child});

  final List<double> stopExtents;
  final Widget child;

  @override
  State<_SheetSnapHaptics> createState() => _SheetSnapHapticsState();
}

class _SheetSnapHapticsState extends State<_SheetSnapHaptics> {
  static const double _tolerance = 0.012;
  static const Duration _settleDelay = Duration(milliseconds: 110);

  Timer? _settleTimer;
  double? _pendingStop;

  @override
  void dispose() {
    _settleTimer?.cancel();
    super.dispose();
  }

  bool _handleExtent(DraggableScrollableNotification notification) {
    double? stop;
    for (final candidate in widget.stopExtents) {
      if ((notification.extent - candidate).abs() <= _tolerance) {
        stop = candidate;
        break;
      }
    }
    if (stop == null) {
      _pendingStop = null;
      _settleTimer?.cancel();
      return false;
    }
    if (_pendingStop == stop) return false;
    _pendingStop = stop;
    _settleTimer?.cancel();
    _settleTimer = Timer(_settleDelay, () {
      if (mounted && _pendingStop == stop) {
        unawaited(HapticFeedback.mediumImpact());
      }
    });
    return false;
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<DraggableScrollableNotification>(
        onNotification: _handleExtent,
        child: widget.child,
      );
}

class _EmptyUpNext extends StatelessWidget {
  const _EmptyUpNext();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Icon(Icons.queue_music_rounded, size: 46, color: palette.textMuted),
        const SizedBox(height: 12),
        const Text(
          'Nothing is queued next',
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        const SizedBox(height: 6),
        Text(
          'Songs you queue—and recommendations when autoplay is on—will '
          'play from this list in this exact order.',
          textAlign: TextAlign.center,
          style: TextStyle(color: palette.textMuted, height: 1.4),
        ),
      ],
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
                  return const Text(
                    'Finished — check Downloads for the video.',
                  );
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
