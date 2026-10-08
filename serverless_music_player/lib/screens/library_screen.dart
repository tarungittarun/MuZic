import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/song_model.dart';
import '../providers/player_controller.dart';
import '../services/library_service.dart';
import '../theme/app_theme.dart';
import '../widgets/empty_state.dart';
import '../widgets/song_tile.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryService>();
    return DefaultTabController(
      length: 4,
      child: Builder(
        builder: (tabContext) => Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 16, 7),
              child: Row(
                children: <Widget>[
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text('YOUR SPACE', style: TextStyle(fontSize: 10, letterSpacing: 2, color: Colors.white54, fontWeight: FontWeight.w800)),
                        SizedBox(height: 4),
                        Text('Library', style: TextStyle(fontSize: 27, fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: 'Create playlist',
                    onPressed: () => _createPlaylist(tabContext),
                    icon: const Icon(Icons.add_rounded),
                  ),
                ],
              ),
            ),
            const TabBar(
              isScrollable: true,
              tabs: <Widget>[
                Tab(text: 'Liked'),
                Tab(text: 'Downloads'),
                Tab(text: 'Recent'),
                Tab(text: 'Playlists'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: <Widget>[
                  _SongList(
                    songs: library.favoriteSongs,
                    emptyIcon: Icons.favorite_border_rounded,
                    emptyTitle: 'No liked songs yet',
                    emptyMessage: 'Tap the heart on a track to keep it here.',
                  ),
                  _SongList(
                    songs: library.downloadedSongs,
                    emptyIcon: Icons.download_for_offline_rounded,
                    emptyTitle: 'Nothing saved offline',
                    emptyMessage: 'Download a track and it will be available without a connection.',
                  ),
                  _SongList(
                    songs: library.recentSongs,
                    emptyIcon: Icons.history_rounded,
                    emptyTitle: 'Your listening history starts here',
                    emptyMessage: 'Recently played tracks appear on this device only.',
                  ),
                  _PlaylistList(playlists: library.playlists),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createPlaylist(BuildContext context) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('New playlist'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Playlist name'),
          onSubmitted: (value) => Navigator.pop(dialogContext, value),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text), child: const Text('Create')),
        ],
      ),
    );
    controller.dispose();
    if (name == null || !context.mounted) return;
    final id = await context.read<LibraryService>().createPlaylist(name);
    if (id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Use a name that is not already in your library.')),
      );
    } else {
      DefaultTabController.of(context).animateTo(3);
    }
  }
}

class _SongList extends StatelessWidget {
  const _SongList({
    required this.songs,
    required this.emptyIcon,
    required this.emptyTitle,
    required this.emptyMessage,
  });

  final List<SongModel> songs;
  final IconData emptyIcon;
  final String emptyTitle;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    if (songs.isEmpty) {
      return EmptyState(icon: emptyIcon, title: emptyTitle, message: emptyMessage);
    }
    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 14),
      itemCount: songs.length,
      itemBuilder: (context, index) {
        final song = songs[index];
        return SongTile(
          song: song,
          onTap: () => context.read<PlayerController>().playQueue(songs, initialIndex: index),
        );
      },
    );
  }
}

class _PlaylistList extends StatelessWidget {
  const _PlaylistList({required this.playlists});

  final List<PlaylistModel> playlists;

  @override
  Widget build(BuildContext context) {
    if (playlists.isEmpty) {
      return const EmptyState(
        icon: Icons.queue_music_rounded,
        title: 'Make it yours',
        message: 'Create a playlist with the plus button and add tracks from search.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
      itemCount: playlists.length,
      itemBuilder: (context, index) {
        final playlist = playlists[index];
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 5),
          child: ExpansionTile(
            leading: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: AppTheme.accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
              child: const Icon(Icons.queue_music_rounded, color: AppTheme.accent),
            ),
            title: Text(playlist.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('${playlist.songs.length} tracks'),
            trailing: PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'delete') {
                  context.read<LibraryService>().deletePlaylist(playlist.id);
                }
              },
              itemBuilder: (_) => const <PopupMenuEntry<String>>[
                PopupMenuItem(value: 'delete', child: Text('Delete playlist')),
              ],
            ),
            children: playlist.songs.isEmpty
                ? const <Widget>[
                    Padding(
                      padding: EdgeInsets.all(18),
                      child: Text('Add tracks from search using the ⋮ menu.', style: TextStyle(color: Colors.white54)),
                    ),
                  ]
                : playlist.songs
                    .map<Widget>((song) => SongTile(
                          song: song,
                          onTap: () => context.read<PlayerController>().playQueue(playlist.songs, initialIndex: playlist.songs.indexOf(song)),
                        ))
                    .toList(),
          ),
        );
      },
    );
  }
}
