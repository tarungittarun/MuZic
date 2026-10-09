import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/lyrics_model.dart';
import '../models/song_model.dart';
import '../providers/player_controller.dart';
import '../services/library_service.dart';
import '../services/music_api_service.dart';
import '../services/usage_service.dart';
import '../theme/app_theme.dart';
import 'cover_art.dart';

class SongTile extends StatefulWidget {
  const SongTile({
    required this.song,
    required this.onTap,
    this.showActions = true,
    this.showDetails = false,
    super.key,
  });

  final SongModel song;
  final VoidCallback onTap;
  final bool showActions;
  final bool showDetails;

  @override
  State<SongTile> createState() => _SongTileState();
}

class _SongTileState extends State<SongTile> {
  bool _expanded = false;
  Future<LyricsModel>? _lyricsFuture;

  @override
  void didUpdateWidget(covariant SongTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.song.id != widget.song.id) {
      _expanded = false;
      _lyricsFuture = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    final palette = context.palette;
    final song = widget.song;
    final downloaded = player.isDownloaded(song);
    final progress = player.downloadProgressFor(song);
    final isCurrent = player.currentSong?.id == song.id;
    final quickMeta = <String>[
      if (song.duration != null) _formatDuration(song.duration!),
      if (_releaseLabel(song.releaseDate) != null) _releaseLabel(song.releaseDate)!,
    ];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: isCurrent ? palette.surfaceRaised : Colors.transparent,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: <Widget>[
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: widget.onTap,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(9, 8, 4, 8),
                child: Row(
                  children: <Widget>[
                    CoverArt(song: song, size: 54, radius: 14),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            song.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: isCurrent ? palette.accent : palette.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            song.artist.isEmpty ? 'Unknown artist' : song.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, color: palette.textSecondary),
                          ),
                          if (quickMeta.isNotEmpty) ...<Widget>[
                            const SizedBox(height: 3),
                            Text(
                              quickMeta.join('  ·  '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 10, color: palette.textMuted),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (widget.showDetails)
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints.tightFor(width: 34, height: 38),
                        padding: EdgeInsets.zero,
                        tooltip: _expanded ? 'Hide track details' : 'Track details',
                        onPressed: _toggleDetails,
                        icon: Icon(
                          _expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                          color: palette.textMuted,
                        ),
                      ),
                    if (widget.showActions) ...<Widget>[
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints.tightFor(width: 36, height: 38),
                        padding: EdgeInsets.zero,
                        tooltip: player.isFavorite(song) ? 'Unlike' : 'Like',
                        onPressed: () => player.toggleFavorite(song),
                        icon: Icon(
                          player.isFavorite(song)
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          color: player.isFavorite(song) ? palette.accent : palette.textMuted,
                          size: 19,
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints.tightFor(width: 36, height: 38),
                        padding: EdgeInsets.zero,
                        tooltip: downloaded ? 'Saved offline' : 'Download',
                        onPressed: downloaded || progress != null
                            ? null
                            : () => _download(context),
                        icon: progress != null
                            ? SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  value: progress == 0 ? null : progress,
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(
                                downloaded
                                    ? Icons.download_done_rounded
                                    : Icons.download_rounded,
                                color: downloaded ? palette.mint : palette.textMuted,
                                size: 19,
                              ),
                      ),
                      PopupMenuButton<String>(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                        tooltip: 'More actions',
                        onSelected: (value) => _handleMenu(context, value),
                        itemBuilder: (_) => <PopupMenuEntry<String>>[
                          const PopupMenuItem(
                            value: 'queue',
                            child: _MenuLabel(icon: Icons.playlist_add_rounded, text: 'Add to queue'),
                          ),
                          const PopupMenuItem(
                            value: 'playlist',
                            child: _MenuLabel(icon: Icons.library_add_rounded, text: 'Add to playlist'),
                          ),
                          if (downloaded)
                            const PopupMenuItem(
                              value: 'remove',
                              child: _MenuLabel(icon: Icons.delete_outline_rounded, text: 'Remove download'),
                            ),
                        ],
                        icon: Icon(Icons.more_vert_rounded, color: palette.textMuted, size: 19),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(76, 0, 14, 13),
              child: _TrackDetails(
                song: song,
                lyricsFuture: _lyricsFuture,
                onRetryLyrics: _retryLyrics,
              ),
            ),
        ],
      ),
    );
  }

  void _toggleDetails() {
    setState(() {
      _expanded = !_expanded;
      if (_expanded && _lyricsFuture == null) {
        unawaited(context.read<UsageService>().recordSongEvent('lyrics_check', widget.song));
        _lyricsFuture = context.read<MusicApiService>().fetchLyrics(widget.song);
      }
    });
  }

  void _retryLyrics() {
    unawaited(context.read<UsageService>().recordSongEvent('lyrics_check', widget.song));
    setState(() {
      _lyricsFuture = context.read<MusicApiService>().fetchLyrics(widget.song);
    });
  }

  Future<void> _download(BuildContext context) async {
    try {
      await context.read<PlayerController>().downloadSong(widget.song);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved “${widget.song.title}” for offline listening.')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed: $error')),
        );
      }
    }
  }

  Future<void> _handleMenu(BuildContext context, String action) async {
    final player = context.read<PlayerController>();
    try {
      if (action == 'queue') {
        await player.addToQueue(widget.song);
      } else if (action == 'remove') {
        await player.removeDownload(widget.song);
      } else if (action == 'playlist') {
        await _choosePlaylist(context);
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not complete that action: $error')),
        );
      }
    }
  }

  Future<void> _choosePlaylist(BuildContext context) async {
    final library = context.read<LibraryService>();
    final playlists = library.playlists;
    if (playlists.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Create a playlist from the Library tab first.')),
      );
      return;
    }
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: context.palette.surface,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Text('Add to playlist', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
            ),
            ...playlists.map((playlist) => ListTile(
                  leading: Icon(Icons.queue_music_rounded, color: context.palette.accent),
                  title: Text(playlist.name),
                  subtitle: Text('${playlist.songs.length} tracks'),
                  onTap: () => Navigator.pop(sheetContext, playlist.id),
                )),
          ],
        ),
      ),
    );
    if (selected != null && context.mounted) {
      final playlist = playlists.firstWhere((item) => item.id == selected);
      final wasAlreadyPresent = playlist.songs.any((item) => item.id == widget.song.id);
      await library.addToPlaylist(selected, widget.song);
      if (!context.mounted) return;
      if (!wasAlreadyPresent) {
        await context.read<UsageService>().recordSongEvent(
              'playlist_add',
              widget.song,
              detail: playlist.name,
            );
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(wasAlreadyPresent ? 'Already in “${playlist.name}”.' : 'Added to playlist.')),
        );
      }
    }
  }
}

class _TrackDetails extends StatelessWidget {
  const _TrackDetails({
    required this.song,
    required this.lyricsFuture,
    required this.onRetryLyrics,
  });

  final SongModel song;
  final Future<LyricsModel>? lyricsFuture;
  final VoidCallback onRetryLyrics;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Divider(height: 1, color: palette.outline),
        const SizedBox(height: 10),
        _InfoRow(label: 'Duration', value: song.duration == null ? null : _durationWithSeconds(song.duration!)),
        _InfoRow(label: 'Released', value: _releaseLabel(song.releaseDate)),
        _InfoRow(label: 'Album', value: song.album),
        _InfoRow(label: 'Artist / author', value: song.artist),
        _InfoRow(label: 'Featured artists', value: song.featuredArtists.join(', ')),
        _InfoRow(label: 'Composer / music', value: song.composer),
        _InfoRow(label: 'Language', value: song.language),
        _InfoRow(label: 'Label', value: song.label),
        _InfoRow(label: 'Play count', value: song.playCount == null ? null : _formatCount(song.playCount!)),
        _InfoRow(label: 'Copyright', value: song.copyright),
        _InfoRow(label: 'Source', value: _sourceLabel(song.source)),
        if (song.isExplicit != null)
          _InfoRow(label: 'Content', value: song.isExplicit! ? 'Explicit' : 'Clean'),
        if (song.hasLyrics != null)
          _InfoRow(label: 'JioSaavn lyrics flag', value: song.hasLyrics! ? 'Listed' : 'Not listed'),
        _LyricsAvailability(future: lyricsFuture, onRetry: onRetryLyrics),
      ],
    );
  }
}

class _LyricsAvailability extends StatelessWidget {
  const _LyricsAvailability({required this.future, required this.onRetry});

  final Future<LyricsModel>? future;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    if (future == null) return const SizedBox.shrink();
    return FutureBuilder<LyricsModel>(
      future: future,
      builder: (context, snapshot) {
        final String value;
        final Color color;
        if (snapshot.connectionState == ConnectionState.waiting) {
          value = 'Checking LRCLIB…';
          color = palette.textMuted;
        } else if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: <Widget>[
                SizedBox(
                  width: 105,
                  child: Text('Lyrics', style: TextStyle(color: palette.textMuted, fontSize: 10)),
                ),
                Expanded(
                  child: Text(
                    'Could not check right now',
                    style: TextStyle(color: palette.textMuted, fontSize: 10),
                  ),
                ),
                TextButton(onPressed: onRetry, child: const Text('Retry')),
              ],
            ),
          );
        } else if (snapshot.data?.isEmpty == false) {
          value = 'Available on LRCLIB';
          color = palette.mint;
        } else {
          value = 'Not found on LRCLIB';
          color = palette.textMuted;
        }
        return _InfoRow(label: 'Lyrics', value: value, valueColor: color);
      },
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, this.valueColor});

  final String label;
  final String? value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    if (value == null || value!.trim().isEmpty) return const SizedBox.shrink();
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 105,
            child: Text(label, style: TextStyle(color: palette.textMuted, fontSize: 10)),
          ),
          Expanded(
            child: Text(
              value!,
              style: TextStyle(color: valueColor ?? palette.textSecondary, fontSize: 10, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuLabel extends StatelessWidget {
  const _MenuLabel({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
        children: <Widget>[
          Icon(icon, size: 19),
          const SizedBox(width: 12),
          Text(text),
        ],
      );
}

String _formatDuration(Duration value) {
  final minutes = value.inMinutes;
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

String _durationWithSeconds(Duration value) =>
    '${_formatDuration(value)}  ·  ${value.inSeconds} sec';

String? _releaseLabel(String? raw) {
  final value = raw?.trim() ?? '';
  if (value.isEmpty) return null;
  final date = DateTime.tryParse(value);
  if (date == null) return value;
  if (date.month == 1 && date.day == 1) return '${date.year}';
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

String _formatCount(int value) {
  if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
  if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}K';
  return '$value';
}

String _sourceLabel(SongSource source) => switch (source) {
      SongSource.jioSaavn => 'JioSaavn',
      SongSource.youtube => 'YouTube',
    };
