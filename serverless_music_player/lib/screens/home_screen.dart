import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_info.dart';
import '../models/song_model.dart';
import '../providers/player_controller.dart';
import '../services/app_settings_service.dart';
import '../services/discover_options.dart';
import '../services/library_service.dart';
import '../services/lossless_radio_service.dart';
import '../services/music_api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/cover_art.dart';
import '../widgets/song_tile.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _queryController = TextEditingController();

  List<SongModel> _results = <SongModel>[];
  List<AlbumSummary> _albums = <AlbumSummary>[];
  final Map<String, List<SongModel>> _trendingByLanguage =
      <String, List<SongModel>>{};
  SearchSource _source = SearchSource.automatic;
  bool _loading = false;
  bool _searching = false;
  String _lastQuery = '';
  String _languageSignature = '';

  @override
  void initState() {
    super.initState();
    unawaited(_loadTrending());
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _loadTrending() async {
    final api = context.read<MusicApiService>();
    final settings = context.read<AppSettingsService>();
    final languages = settings.languages.isEmpty
        ? const <String>['english']
        : settings.languages;
    for (final code in languages) {
      final songs = await api.fetchTrending(limit: 20, language: code);
      if (!mounted) return;
      if (songs.isEmpty) continue;
      setState(() => _trendingByLanguage[code] = songs);
    }
  }

  Future<void> _search([String? query]) async {
    final text = (query ?? _queryController.text).trim();
    if (text.isEmpty) {
      setState(() {
        _results = <SongModel>[];
        _albums = <AlbumSummary>[];
        _searching = false;
        _lastQuery = '';
      });
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _searching = true;
      _lastQuery = text;
    });
    final api = context.read<MusicApiService>();
    try {
      final songs = await api.search(text, source: _source, limit: 30);
      final albums = _source == SearchSource.youtube
          ? const <AlbumSummary>[]
          : await api.searchAlbums(text, limit: 10);
      if (!mounted) return;
      setState(() {
        _results = songs;
        _albums = albums;
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Search failed: $error')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _play(List<SongModel> songs, int index) async {
    try {
      await context.read<PlayerController>().playQueue(songs, initialIndex: index);
    } catch (error) {
      if (!mounted) return;
      final message = error is StateError ? error.message : '$error';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not start playback: $message')),
      );
    }
  }

  Future<void> _openAlbum(AlbumSummary album) async {
    final api = context.read<MusicApiService>();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.palette.surface,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => _AlbumSheet(
        album: album,
        songsFuture: api.fetchAlbumSongs(album.id),
        onPlay: (songs, index) {
          Navigator.pop(sheetContext);
          unawaited(_play(songs, index));
        },
      ),
    );
  }

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    if (hour < 21) return 'Good evening';
    return 'Good night';
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final library = context.watch<LibraryService>();
    final appSettings = context.watch<AppSettingsService>();
    // Reload recommendation shelves when the user changes languages.
    final signature = appSettings.languages.join(',');
    if (signature != _languageSignature) {
      _languageSignature = signature;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_loadTrending());
      });
    }
    final recent = library.recentSongs;
    final favorites = library.favoriteSongs;
    final playlists = library.playlists;

    return RefreshIndicator(
      onRefresh: _loadTrending,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 28),
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 14, 6),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        '$_greeting · ${AppInfo.displayName}',
                        style: TextStyle(
                          fontSize: 12,
                          color: palette.textMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _searching ? 'Search results' : 'Listen your way',
                        style: const TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_searching)
                  IconButton(
                    tooltip: 'Clear search',
                    onPressed: () {
                      _queryController.clear();
                      setState(() {
                        _searching = false;
                        _results = <SongModel>[];
                        _albums = <AlbumSummary>[];
                        _lastQuery = '';
                      });
                    },
                    icon: const Icon(Icons.close_rounded),
                  ),
                IconButton.filledTonal(
                  tooltip: 'Settings',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SettingsScreen(),
                    ),
                  ),
                  icon: const Icon(Icons.tune_rounded),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
            child: TextField(
              controller: _queryController,
              textInputAction: TextInputAction.search,
              onSubmitted: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                prefixIcon: Icon(Icons.search_rounded, color: palette.accent),
                hintText: 'Songs, albums, artists',
                suffixIcon: _queryController.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Search',
                        onPressed: () => _search(),
                        icon: const Icon(Icons.arrow_forward_rounded),
                      ),
              ),
            ),
          ),
          if (!_searching)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 2),
              child: Row(
                children: <Widget>[
                  _sourceChip(SearchSource.automatic, 'Auto'),
                  const SizedBox(width: 7),
                  _sourceChip(SearchSource.jioSaavn, 'JioSaavn'),
                  const SizedBox(width: 7),
                  _sourceChip(SearchSource.youtube, 'YouTube'),
                ],
              ),
            ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (!_searching) ..._browseShelves(recent, favorites, playlists),
          if (_searching) ..._searchResults(),
        ],
      ),
    );
  }

  List<Widget> _browseShelves(
    List<SongModel> recent,
    List<SongModel> favorites,
    List<PlaylistModel> playlists,
  ) {
    return <Widget>[
      if (recent.isNotEmpty)
        _SongShelf(
          title: 'Recently played',
          subtitle: 'Pick up where you left off',
          songs: recent,
          onPlay: (index) => _play(recent, index),
        ),
      if (favorites.isNotEmpty)
        _SongShelf(
          title: 'Liked songs',
          subtitle: '${favorites.length} tracks you loved',
          songs: favorites,
          onPlay: (index) => _play(favorites, index),
        ),
      for (final entry in _trendingByLanguage.entries)
        if (entry.value.isNotEmpty)
          _SongShelf(
            title: 'Trending in ${kDiscoverLanguageLabel[entry.key] ?? entry.key}',
            subtitle: 'Popular on JioSaavn',
            songs: entry.value,
            onPlay: (index) => _play(entry.value, index),
          ),
      _LosslessRadioShelf(onPlay: (station) => _play(<SongModel>[station.toSong()], 0)),
      if (playlists.isNotEmpty)
        _ShelfHeader(
          title: 'Your playlists',
          subtitle: '${playlists.length} collections',
        ),
      if (playlists.isNotEmpty)
        SizedBox(
          height: 56,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 0),
            scrollDirection: Axis.horizontal,
            itemCount: playlists.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final playlist = playlists[index];
              return ActionChip(
                avatar: const Icon(Icons.queue_music_rounded, size: 16),
                label: Text('${playlist.name} · ${playlist.songs.length}'),
                onPressed: () {
                  if (playlist.songs.isNotEmpty) _play(playlist.songs, 0);
                },
              );
            },
          ),
        ),
    ];
  }

  List<Widget> _searchResults() {
    final palette = context.palette;
    if (_results.isEmpty && _albums.isEmpty && !_loading) {
      return <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 44, 20, 20),
          child: Column(
            children: <Widget>[
              Icon(Icons.search_off_rounded, size: 44, color: palette.textMuted),
              const SizedBox(height: 14),
              Text(
                'No results for "$_lastQuery"',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                'Check the spelling or try the YouTube source.',
                textAlign: TextAlign.center,
                style: TextStyle(color: palette.textMuted, fontSize: 12),
              ),
            ],
          ),
        ),
      ];
    }

    final top = _results.isNotEmpty ? _results.first : null;
    return <Widget>[
      if (top != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 4),
          child: _TopResultCard(song: top, onPlay: () => _play(_results, 0)),
        ),
      if (_albums.isNotEmpty) ...<Widget>[
        const _ShelfHeader(title: 'Albums', subtitle: 'Full releases'),
        SizedBox(
          height: 168,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 0),
            scrollDirection: Axis.horizontal,
            itemCount: _albums.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) => _AlbumCard(
              album: _albums[index],
              onTap: () => _openAlbum(_albums[index]),
            ),
          ),
        ),
      ],
      _ShelfHeader(
        title: 'Songs',
        subtitle: '${_results.length} results',
      ),
      for (var index = 0; index < _results.length; index++)
        SongTile(
          song: _results[index],
          onTap: () => _play(_results, index),
        ),
    ];
  }

  Widget _sourceChip(SearchSource source, String label) {
    final palette = context.palette;
    final selected = _source == source;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      selected: selected,
      onSelected: (_) {
        setState(() => _source = source);
        if (_searching) unawaited(_search(_lastQuery));
      },
      visualDensity: VisualDensity.compact,
      selectedColor: palette.accent.withValues(alpha: 0.18),
      labelStyle: TextStyle(
        color: selected ? palette.accent : palette.textSecondary,
        fontWeight: FontWeight.w600,
      ),
      side: BorderSide(color: palette.outline.withValues(alpha: 0.6)),
    );
  }
}

class _ShelfHeader extends StatelessWidget {
  const _ShelfHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
          ),
          Text(subtitle, style: TextStyle(color: palette.textMuted, fontSize: 10.5)),
        ],
      ),
    );
  }
}

class _SongShelf extends StatelessWidget {
  const _SongShelf({
    required this.title,
    required this.subtitle,
    required this.songs,
    required this.onPlay,
  });

  final String title;
  final String subtitle;
  final List<SongModel> songs;
  final void Function(int index) onPlay;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _ShelfHeader(title: title, subtitle: subtitle),
        SizedBox(
          height: 186,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
            scrollDirection: Axis.horizontal,
            itemCount: songs.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final song = songs[index];
              return _SongCard(song: song, onTap: () => onPlay(index));
            },
          ),
        ),
      ],
    );
  }
}

class _SongCard extends StatelessWidget {
  const _SongCard({required this.song, required this.onTap});

  final SongModel song;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SizedBox(
      width: 132,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // Keep the art square but let it shrink when the labels need more
            // room (larger system font) instead of overflowing the shelf.
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  const max = 132.0;
                  final side =
                      constraints.maxHeight < max ? constraints.maxHeight : max;
                  return Align(
                    alignment: Alignment.topLeft,
                    child: CoverArt(song: song, size: side, radius: 16),
                  );
                },
              ),
            ),
            const SizedBox(height: 7),
            Text(
              song.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            Text(
              song.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10.5, color: palette.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlbumCard extends StatelessWidget {
  const _AlbumCard({required this.album, required this.onTap});

  final AlbumSummary album;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SizedBox(
      width: 128,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // The art takes whatever the shelf leaves after the two labels, so
            // a larger system font shrinks the artwork instead of overflowing
            // the fixed-height shelf.
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SizedBox.expand(
                  child: album.imageUrl == null
                      ? Container(color: palette.surfaceRaised)
                      : Image.network(
                          album.imageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              Container(color: palette.surfaceRaised),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 7),
            Text(
              album.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            Text(
              album.songCount == null
                  ? album.artist
                  : '${album.songCount} songs · ${album.artist}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10.5, color: palette.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopResultCard extends StatelessWidget {
  const _TopResultCard({required this.song, required this.onPlay});

  final SongModel song;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onPlay,
      child: Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: palette.outline.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: <Widget>[
            CoverArt(song: song, size: 64, radius: 13),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('TOP RESULT',
                      style: TextStyle(
                        fontSize: 9,
                        letterSpacing: 1.4,
                        fontWeight: FontWeight.w800,
                        color: palette.accent,
                      )),
                  const SizedBox(height: 4),
                  Text(song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(song.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: palette.textMuted)),
                ],
              ),
            ),
            Icon(Icons.play_circle_fill_rounded,
                color: palette.accent, size: 36),
          ],
        ),
      ),
    );
  }
}

class _LosslessRadioShelf extends StatelessWidget {
  const _LosslessRadioShelf({required this.onPlay});

  final void Function(RadioStation station) onPlay;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const _ShelfHeader(title: 'Lossless radio', subtitle: 'FLAC · live'),
        SizedBox(
          height: 62,
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
            scrollDirection: Axis.horizontal,
            itemCount: LosslessRadioService.stations.length,
            itemBuilder: (context, index) => Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _RadioStationChip(
                station: LosslessRadioService.stations[index],
                onTap: () => onPlay(LosslessRadioService.stations[index]),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AlbumSheet extends StatelessWidget {
  const _AlbumSheet({
    required this.album,
    required this.songsFuture,
    required this.onPlay,
  });

  final AlbumSummary album;
  final Future<List<SongModel>> songsFuture;
  final void Function(List<SongModel> songs, int index) onPlay;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        maxChildSize: 0.92,
        builder: (context, scrollController) => FutureBuilder<List<SongModel>>(
          future: songsFuture,
          builder: (context, snapshot) {
            final songs = snapshot.data ?? const <SongModel>[];
            return ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
              children: <Widget>[
                Text(album.title,
                    style: const TextStyle(
                        fontSize: 19, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(
                  <String>[
                    if (album.artist.isNotEmpty) album.artist,
                    if (album.year != null) album.year!,
                    if (album.songCount != null) '${album.songCount} songs',
                  ].join(' · '),
                  style: TextStyle(color: palette.textMuted, fontSize: 12),
                ),
                const SizedBox(height: 14),
                if (snapshot.connectionState != ConnectionState.done)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                if (snapshot.connectionState == ConnectionState.done && songs.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text('No playable songs found for this album.',
                        style: TextStyle(color: palette.textMuted)),
                  ),
                for (var index = 0; index < songs.length; index++)
                  SongTile(
                    song: songs[index],
                    onTap: () => onPlay(songs, index),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _RadioStationChip extends StatelessWidget {
  const _RadioStationChip({required this.station, required this.onTap});

  final RadioStation station;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Material(
      color: palette.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 14, 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: palette.outline.withValues(alpha: 0.55)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.podcasts_rounded, color: palette.mint, size: 20),
              const SizedBox(width: 9),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    station.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'FLAC · lossless radio',
                    style: TextStyle(fontSize: 9.5, color: palette.mint),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
