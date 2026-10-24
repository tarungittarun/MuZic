import 'dart:async';
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
import 'lyric_video_player_screen.dart';
import '../widgets/empty_state.dart';
import '../widgets/muzic_home_button.dart';
import '../widgets/song_tile.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({this.onHome, super.key});

  final VoidCallback? onHome;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final PageController _pageController = PageController();
  int _sectionIndex = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goToSection(int index) {
    if (index == _sectionIndex) return;
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  int get _topTabIndex => switch (_sectionIndex) {
        0 => 0,
        1 || 2 => 1,
        3 => 2,
        4 => 3,
        _ => 4,
      };

  void _goToTopTab(int topIndex) {
    final target = switch (topIndex) {
      0 => 0,
      1 => _sectionIndex == 2 ? 2 : 1,
      2 => 3,
      3 => 4,
      _ => 5,
    };
    _goToSection(target);
  }

  /// The pre-1.5.37 Library header treatment: a classic top tab strip under
  /// the page title. The pages beneath it still swipe continuously through
  /// Downloads' inner sections.
  Widget _topTabBar(BuildContext context) {
    final palette = context.palette;
    const tabs = <String>['Liked', 'Downloads', 'Recent', 'Playlists', 'Local'];
    return SizedBox(
      height: 46,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(10, 2, 10, 0),
        itemCount: tabs.length,
        itemBuilder: (context, index) {
          final selected = index == _topTabIndex;
          return InkWell(
            onTap: () => _goToTopTab(index),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 13),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  Text(
                    tabs[index],
                    style: TextStyle(
                      color: selected ? palette.accent : palette.textMuted,
                      fontSize: 13.5,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: selected ? 28 : 0,
                    height: 3,
                    decoration: BoxDecoration(
                      color: palette.accent,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(height: 5),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Downloads keeps its familiar two-way pill from the previous design,
  /// but Songs and Lyric videos are neighbouring pages in the same swipe
  /// flow rather than a trapped nested tab view.
  Widget _downloadsSwitcher(BuildContext context) {
    final palette = context.palette;
    final songs = context.watch<LibraryService>().downloadedSongs;
    final videos = context.watch<VideoLibraryService>().videos;
    Widget segment(int page, IconData icon, String label, int count) {
      final selected = _sectionIndex == page;
      return Expanded(
        child: Material(
          color: selected
              ? palette.accent.withValues(alpha: 0.18)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _goToSection(page),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(
                    icon,
                    size: 16,
                    color: selected ? palette.accent : palette.textMuted,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      color: selected ? palette.accent : palette.textMuted,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 6),
                  _CountChip(count: count),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 3),
      child: Container(
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: palette.outline, width: 0.7),
        ),
        padding: const EdgeInsets.all(4),
        child: Row(
          children: <Widget>[
            segment(1, Icons.audio_file_rounded, 'Songs', songs.length),
            segment(2, Icons.movie_creation_outlined, 'Lyric videos', videos.length),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryService>();
    final palette = context.palette;
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 20, 16, 7),
          child: Row(
            children: <Widget>[
              MuZicHomeButton(onPressed: widget.onHome ?? () {}),
              const SizedBox(width: 12),
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
                onPressed: () => _importLocalFiles(context),
                icon: const Icon(Icons.library_add_rounded),
              ),
              const SizedBox(width: 6),
              IconButton.filledTonal(
                tooltip: 'Create playlist',
                onPressed: () => _createPlaylist(context),
                icon: const Icon(Icons.add_rounded),
              ),
            ],
          ),
        ),
        _topTabBar(context),
        if (_sectionIndex == 1 || _sectionIndex == 2)
          _downloadsSwitcher(context),
        Expanded(
          child: PageView(
            controller: _pageController,
            onPageChanged: (index) => setState(() => _sectionIndex = index),
            children: <Widget>[
              _SongList(
                songs: library.favoriteSongs,
                emptyIcon: Icons.favorite_border_rounded,
                emptyTitle: 'No liked songs yet',
                emptyMessage: 'Tap the heart on a track to keep it here.',
              ),
              const _DownloadedSongsPage(),
              const _LyricVideosPage(),
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
      if (context.mounted) _goToSection(4);
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

/// Downloaded songs are a first-class Library section (the swipe after
/// Liked), so horizontal navigation never gets trapped in a nested tab.
class _DownloadedSongsPage extends StatelessWidget {
  const _DownloadedSongsPage();

  @override
  Widget build(BuildContext context) {
    final songs = context.watch<LibraryService>().downloadedSongs;
    if (songs.isEmpty) {
      return const EmptyState(
        icon: Icons.download_for_offline_rounded,
        title: 'No songs downloaded yet',
        message:
            'Download a track and it will be available without '
            'a connection. Use its 3-dot menu to share the '
            'original file.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 18),
      itemCount: songs.length,
      itemBuilder: (context, index) => SongTile(
        song: songs[index],
        onTap: () => context
            .read<PlayerController>()
            .playQueue(songs, initialIndex: index),
      ),
    );
  }
}

/// Lyric videos continue the same swipe flow after Downloads · Songs.
class _LyricVideosPage extends StatelessWidget {
  const _LyricVideosPage();

  @override
  Widget build(BuildContext context) {
    final videos = context.watch<VideoLibraryService>().videos;
    if (videos.isEmpty) {
      return const EmptyState(
        icon: Icons.movie_creation_outlined,
        title: 'No lyric videos yet',
        message:
            'Export one from the player: the movie icon next to the waveform '
            'button. Your lyric videos appear here and play inside MuZic.',
      );
    }
    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 18),
      children: <Widget>[
        for (final video in videos) _LyricVideoTile(video: video),
      ],
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
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
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            final player = context.read<PlayerController>();
            if (player.isPlaying) unawaited(player.togglePlayback());
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => LyricVideoPlayerScreen(video: video),
              ),
            );
          },
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(6),
                          bottomRight: Radius.circular(14),
                        ),
                      ),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        size: 11,
                        color: Colors.white,
                      ),
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
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
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
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
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
                          style: TextStyle(
                            fontSize: 10,
                            color: palette.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Remove from library',
                icon: Icon(
                  Icons.delete_outline_rounded,
                  size: 19,
                  color: palette.textMuted,
                ),
                onPressed: () => _confirmRemove(context, video),
              ),
            ],
          ),
        ),
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
          'This removes the entry from MuZic. '
          'The video itself stays where it was saved.',
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
