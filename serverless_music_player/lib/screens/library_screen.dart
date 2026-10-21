import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/song_model.dart';
import '../providers/player_controller.dart';
import '../services/library_service.dart';
import '../services/local_files_service.dart';
import '../services/usage_service.dart';
import '../services/video_library_service.dart';
import '../theme/app_theme.dart';
import '../widgets/empty_state.dart';
import '../widgets/song_tile.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryService>();
    final palette = context.palette;
    return DefaultTabController(
      length: 5,
      child: Builder(
        builder: (tabContext) => Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 16, 7),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text('YOUR SPACE', style: TextStyle(fontSize: 10, letterSpacing: 2, color: palette.textMuted, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        const Text('Library', style: TextStyle(fontSize: 27, fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: 'Import files from this device',
                    onPressed: () => _importLocalFiles(tabContext),
                    icon: const Icon(Icons.library_add_rounded),
                  ),
                  const SizedBox(width: 6),
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
                Tab(text: 'Local'),
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
                  const _DownloadsTab(),
                  _SongList(
                    songs: library.recentSongs,
                    emptyIcon: Icons.history_rounded,
                    emptyTitle: 'Your listening history starts here',
                    emptyMessage: 'Recently played tracks appear on this device only.',
                  ),
                  _PlaylistList(playlists: library.playlists),
                  _LocalList(songs: library.localSongs),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _importLocalFiles(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final library = context.read<LibraryService>();
    final files = await LocalFilesService().pickAudioFiles();
    if (files.isEmpty) return;
    var imported = 0;
    var lossless = 0;
    for (final file in files) {
      final song = SongModel(
        id: 'local:${file.path}',
        sourceId: file.path,
        title: file.title.isEmpty ? file.name : file.title,
        artist: 'Local file',
        album: 'Imported music',
        source: SongSource.local,
        localPath: file.path,
        streamUrl: file.path,
      );
      await library.saveLocalSong(song);
      imported++;
      if (file.isLosslessFormat) lossless++;
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          imported == 1
              ? 'Imported 1 track${lossless > 0 ? ' (lossless)' : ''}.'
              : 'Imported $imported tracks ($lossless lossless).',
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
    if (!context.mounted) return;
    if (id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Use a name that is not already in your library.')),
      );
    } else {
      await context.read<UsageService>().record(
            type: 'playlist_create',
            detail: name.trim(),
          );
      if (!context.mounted) return;
      DefaultTabController.of(context).animateTo(3);
    }
  }
}

class _LocalList extends StatelessWidget {
  const _LocalList({required this.songs});

  final List<SongModel> songs;

  @override
  Widget build(BuildContext context) {
    if (songs.isEmpty) {
      return const EmptyState(
        icon: Icons.folder_open_rounded,
        title: 'Bring your own FLACs',
        message:
            'Tap the import button above to add FLAC, WAV, AIFF or MP3 files '
            'from this device. They play losslessly, offline.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 14),
      itemCount: songs.length,
      itemBuilder: (context, index) {
        final song = songs[index];
        return SongTile(
          song: song,
          onTap: () => context
              .read<PlayerController>()
              .playQueue(songs, initialIndex: index),
        );
      },
    );
  }
}

/// Downloads, split by kind: offline audio you play in the app, and lyric
/// videos you exported (which live in Movies/MuZic and are meant for sharing).
class _DownloadsTab extends StatelessWidget {
  const _DownloadsTab();

  @override
  Widget build(BuildContext context) {
    final songs = context.watch<LibraryService>().downloadedSongs;
    final videos = context.watch<VideoLibraryService>().videos;
    if (songs.isEmpty && videos.isEmpty) {
      return const EmptyState(
        icon: Icons.download_for_offline_rounded,
        title: 'Nothing saved offline',
        message: 'Download a track and it will be available without a connection.',
      );
    }
    return ListView(
      padding: const EdgeInsets.only(top: 4, bottom: 18),
      children: <Widget>[
        _DownloadSectionHeader(
          icon: Icons.audio_file_rounded,
          title: 'Songs',
          count: songs.length,
          hint: 'Play offline in MuZic',
        ),
        if (songs.isEmpty)
          const _SectionEmpty(text: 'No songs downloaded yet.')
        else
          for (var index = 0; index < songs.length; index++)
            SongTile(
              song: songs[index],
              onTap: () => context
                  .read<PlayerController>()
                  .playQueue(songs, initialIndex: index),
            ),
        const SizedBox(height: 8),
        _DownloadSectionHeader(
          icon: Icons.movie_creation_outlined,
          title: 'Lyric videos',
          count: videos.length,
          hint: 'Saved to Movies/MuZic',
        ),
        if (videos.isEmpty)
          const _SectionEmpty(
            text: 'Export one from the player: the movie icon next to the '
                'visualizer button.',
          )
        else
          for (final video in videos) _LyricVideoTile(video: video),
      ],
    );
  }
}

class _DownloadSectionHeader extends StatelessWidget {
  const _DownloadSectionHeader({
    required this.icon,
    required this.title,
    required this.count,
    required this.hint,
  });

  final IconData icon;
  final String title;
  final int count;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 15, color: palette.accent),
          const SizedBox(width: 7),
          Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.5,
              color: palette.textMuted,
            ),
          ),
          const SizedBox(width: 7),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
            decoration: BoxDecoration(
              color: palette.surfaceRaised,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: palette.textMuted,
              ),
            ),
          ),
          const Spacer(),
          Text(
            hint,
            style: TextStyle(fontSize: 10, color: palette.textMuted),
          ),
        ],
      ),
    );
  }
}

class _SectionEmpty extends StatelessWidget {
  const _SectionEmpty({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 10),
      child: Text(
        text,
        style: TextStyle(fontSize: 12, color: palette.textMuted, height: 1.35),
      ),
    );
  }
}

/// A rendered lyric video: square thumbnail with a play/movie badge, the
/// duration and when it was made, plus the option to forget the entry.
class _LyricVideoTile extends StatelessWidget {
  const _LyricVideoTile({required this.video});

  final VideoExportRecord video;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final created = video.createdAt;
    final stamp = '${created.day.toString().padLeft(2, '0')}/'
        '${created.month.toString().padLeft(2, '0')}/${created.year}';
    final duration = video.durationMs == null
        ? null
        : Duration(milliseconds: video.durationMs!);
    final durationLabel = duration == null
        ? null
        : '${duration.inMinutes}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 3, 8, 3),
      child: Row(
        children: <Widget>[
          Stack(
            children: <Widget>[
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  width: 54,
                  height: 54,
                  child: (video.artworkPath != null &&
                          File(video.artworkPath!).existsSync())
                      ? Image.file(File(video.artworkPath!), fit: BoxFit.cover)
                      : Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: <Color>[
                                palette.accent.withValues(alpha: 0.35),
                                palette.mint.withValues(alpha: 0.25),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: const Icon(Icons.movie_rounded, size: 22),
                        ),
                ),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(6),
                      bottomRight: Radius.circular(14),
                    ),
                  ),
                  child: const Icon(Icons.play_arrow_rounded,
                      size: 11, color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  video.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  video.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: palette.textMuted),
                ),
                const SizedBox(height: 4),
                Row(
                  children: <Widget>[
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: palette.accent.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'MP4 · lyric video${durationLabel == null ? '' : ' · $durationLabel'}',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: palette.accent,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      stamp,
                      style: TextStyle(fontSize: 10, color: palette.textMuted),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Remove from library',
            icon: Icon(Icons.delete_outline_rounded,
                size: 19, color: palette.textMuted),
            onPressed: () => _confirmRemove(context, video),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmRemove(BuildContext context, VideoExportRecord video) async {
    final service = context.read<VideoLibraryService>();
    final remove = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove lyric video?'),
        content: const Text(
          'This only removes the entry from MuZic. The video stays in your '
          'phone\'s Movies/MuZic folder.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (remove == true) await service.remove(video.id);
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
    final palette = context.palette;
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
              decoration: BoxDecoration(color: palette.accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
              child: Icon(Icons.queue_music_rounded, color: palette.accent),
            ),
            title: Text(playlist.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('${playlist.songs.length} tracks'),
            trailing: PopupMenuButton<String>(
              onSelected: (value) async {
                if (value == 'delete') {
                  await context.read<LibraryService>().deletePlaylist(playlist.id);
                  if (!context.mounted) return;
                  await context.read<UsageService>().record(
                        type: 'playlist_delete',
                        detail: playlist.name,
                      );
                }
              },
              itemBuilder: (_) => const <PopupMenuEntry<String>>[
                PopupMenuItem(value: 'delete', child: Text('Delete playlist')),
              ],
            ),
            children: playlist.songs.isEmpty
                ? <Widget>[
                    Padding(
                      padding: const EdgeInsets.all(18),
                      child: Text('Add tracks from search using the ⋮ menu.', style: TextStyle(color: palette.textMuted)),
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
