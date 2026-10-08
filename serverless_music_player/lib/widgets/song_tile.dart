import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/song_model.dart';
import '../providers/player_controller.dart';
import '../services/library_service.dart';
import '../theme/app_theme.dart';
import 'cover_art.dart';

class SongTile extends StatelessWidget {
  const SongTile({
    required this.song,
    required this.onTap,
    this.showActions = true,
    super.key,
  });

  final SongModel song;
  final VoidCallback onTap;
  final bool showActions;

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    final downloaded = player.isDownloaded(song);
    final progress = player.downloadProgressFor(song);
    final isCurrent = player.currentSong?.id == song.id;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: isCurrent ? AppTheme.surfaceRaised : Colors.transparent,
        borderRadius: BorderRadius.circular(18),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
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
                    Text(song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: isCurrent ? AppTheme.accent : Colors.white,
                        )),
                    const SizedBox(height: 5),
                    Text(
                      song.artist.isEmpty ? 'Unknown artist' : song.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: Colors.white54),
                    ),
                  ],
                ),
              ),
              if (showActions) ...<Widget>[
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: player.isFavorite(song) ? 'Unlike' : 'Like',
                  onPressed: () => player.toggleFavorite(song),
                  icon: Icon(
                    player.isFavorite(song)
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    color: player.isFavorite(song) ? AppTheme.accent : Colors.white54,
                    size: 20,
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: downloaded ? 'Saved offline' : 'Download',
                  onPressed: downloaded || progress != null
                      ? null
                      : () => _download(context),
                  icon: progress != null
                      ? SizedBox(
                          width: 19,
                          height: 19,
                          child: CircularProgressIndicator(
                            value: progress == 0 ? null : progress,
                            strokeWidth: 2,
                          ),
                        )
                      : Icon(
                          downloaded ? Icons.download_done_rounded : Icons.download_rounded,
                          color: downloaded ? AppTheme.mint : Colors.white54,
                          size: 20,
                        ),
                ),
                PopupMenuButton<String>(
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
                  icon: const Icon(Icons.more_vert_rounded, color: Colors.white54, size: 20),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _download(BuildContext context) async {
    try {
      await context.read<PlayerController>().downloadSong(song);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved “${song.title}” for offline listening.')),
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
        await player.addToQueue(song);
      } else if (action == 'remove') {
        await player.removeDownload(song);
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
      backgroundColor: AppTheme.surface,
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
                  leading: const Icon(Icons.queue_music_rounded, color: AppTheme.accent),
                  title: Text(playlist.name),
                  subtitle: Text('${playlist.songs.length} tracks'),
                  onTap: () => Navigator.pop(sheetContext, playlist.id),
                )),
          ],
        ),
      ),
    );
    if (selected != null) {
      await library.addToPlaylist(selected, song);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Added to playlist.')),
        );
      }
    }
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
