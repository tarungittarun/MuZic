import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/song_model.dart';
import '../providers/player_controller.dart';
import '../services/music_api_service.dart';
import '../services/usage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/empty_state.dart';
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
  SearchSource _source = SearchSource.automatic;
  bool _loading = false;
  bool _hasSearched = false;
  String? _error;
  int _requestNumber = 0;

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _search([String? submitted]) async {
    final query = (submitted ?? _queryController.text).trim();
    if (query.isEmpty) return;
    _queryController.text = query;
    final requestNumber = ++_requestNumber;
    final source = _source;
    final usage = context.read<UsageService>();
    setState(() {
      _loading = true;
      _error = null;
      _hasSearched = true;
    });
    try {
      final results = await context.read<MusicApiService>().search(
            query,
            source: source,
            limit: 10,
          );
      unawaited(usage.recordSearch(
        query: query,
        source: source.name,
        resultCount: results.length,
      ));
      if (!mounted || requestNumber != _requestNumber) return;
      setState(() => _results = results);
    } catch (error) {
      unawaited(usage.recordSearch(
        query: query,
        source: source.name,
        resultCount: 0,
      ));
      if (!mounted || requestNumber != _requestNumber) return;
      setState(() {
        _results = <SongModel>[];
        _error = error.toString();
      });
    } finally {
      if (mounted && requestNumber == _requestNumber) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
          child: Row(
            children: <Widget>[
              Container(
                width: 43,
                height: 43,
                decoration: BoxDecoration(
                  color: palette.surfaceRaised,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(Icons.graphic_eq_rounded, color: palette.mint),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'AURALIS',
                      style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 2.2,
                        color: palette.textMuted,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Listen your way.',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
              IconButton.filledTonal(
                tooltip: 'Settings and appearance',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
                ),
                icon: const Icon(Icons.tune_rounded),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: TextField(
            controller: _queryController,
            textInputAction: TextInputAction.search,
            onSubmitted: _search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              prefixIcon: Icon(Icons.search_rounded, color: palette.accent),
              hintText: 'Search songs, artists, albums',
              suffixIcon: _queryController.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Search',
                      onPressed: _search,
                      icon: const Icon(Icons.arrow_forward_rounded),
                    ),
            ),
          ),
        ),
        SizedBox(
          height: 54,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 4),
            scrollDirection: Axis.horizontal,
            children: <Widget>[
              _sourceChip(SearchSource.automatic, 'Auto fallback'),
              const SizedBox(width: 8),
              _sourceChip(SearchSource.jioSaavn, 'JioSaavn'),
              const SizedBox(width: 8),
              _sourceChip(SearchSource.youtube, 'YouTube'),
            ],
          ),
        ),
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: _results.isNotEmpty
              ? ListView.builder(
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.only(top: 8, bottom: 14),
                  itemCount: _results.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(22, 8, 22, 7),
                        child: Row(
                          children: <Widget>[
                            Text(
                              '${_results.length} tracks',
                              style: TextStyle(color: palette.textMuted, fontSize: 12),
                            ),
                            const Spacer(),
                            TextButton.icon(
                              onPressed: _loading ? null : () => _playResults(0),
                              icon: const Icon(Icons.play_arrow_rounded, size: 17),
                              label: const Text('Play all'),
                              style: TextButton.styleFrom(foregroundColor: palette.accent),
                            ),
                          ],
                        ),
                      );
                    }
                    final songIndex = index - 1;
                    final song = _results[songIndex];
                    return SongTile(
                      song: song,
                      showDetails: true,
                      onTap: () => _playResults(songIndex),
                    );
                  },
                )
              : _emptyContent(),
        ),
      ],
    );
  }

  Widget _sourceChip(SearchSource source, String label) {
    final palette = context.palette;
    final selected = _source == source;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      onSelected: (_) => setState(() => _source = source),
      labelStyle: TextStyle(
        color: selected ? palette.accent : palette.textSecondary,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
      side: BorderSide(color: selected ? palette.accent.withValues(alpha: 0.45) : palette.outline),
      backgroundColor: palette.surface,
      selectedColor: palette.accent.withValues(alpha: 0.12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
    );
  }

  Widget _emptyContent() {
    final palette = context.palette;
    if (_error != null) {
      return EmptyState(
        icon: Icons.wifi_off_rounded,
        title: 'Could not search right now',
        message: _error!,
      );
    }
    if (_loading) {
      return const EmptyState(
        icon: Icons.graphic_eq_rounded,
        title: 'Finding your next song',
        message: 'Searching directly from this device.',
      );
    }
    if (_hasSearched) {
      return const EmptyState(
        icon: Icons.search_off_rounded,
        title: 'No matches found',
        message: 'Try another title or artist, or switch the search source.',
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 18),
      child: Column(
        children: <Widget>[
          const SizedBox(height: 18),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Your music, your way.',
              style: TextStyle(color: palette.textPrimary, fontSize: 25, height: 1.1, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Search online, keep favorites and playlists on-device, and save tracks for offline listening.',
              style: TextStyle(color: palette.textSecondary, height: 1.5),
            ),
          ),
          const SizedBox(height: 22),
          _FeatureCard(
            icon: Icons.queue_music_rounded,
            title: 'A queue that stays yours',
            subtitle: 'Add, reorder, shuffle, and repeat.',
          ),
          const SizedBox(height: 10),
          _FeatureCard(
            icon: Icons.offline_bolt_rounded,
            title: 'Take music offline',
            subtitle: 'Downloads live in app-private storage.',
          ),
          const SizedBox(height: 10),
          _FeatureCard(
            icon: Icons.lyrics_rounded,
            title: 'Follow the words',
            subtitle: 'Synced lyrics when LRCLIB has them.',
          ),
        ],
      ),
    );
  }

  Future<void> _playResults(int index) async {
    try {
      await context.read<PlayerController>().playQueue(_results, initialIndex: index);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not start playback: $error')),
        );
      }
    }
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({required this.icon, required this.title, required this.subtitle});

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: palette.outline.withValues(alpha: 0.55)),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: palette.accent.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, size: 20, color: palette.accent),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                const SizedBox(height: 4),
                Text(subtitle, style: TextStyle(color: palette.textMuted, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
