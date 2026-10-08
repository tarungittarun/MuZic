import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/song_model.dart';
import '../providers/player_controller.dart';
import '../services/music_api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/empty_state.dart';
import '../widgets/song_tile.dart';

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
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await context.read<MusicApiService>().search(
            query,
            source: _source,
            limit: 10,
          );
      if (!mounted || requestNumber != _requestNumber) return;
      setState(() => _results = results);
    } catch (error) {
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
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Row(
            children: <Widget>[
              Container(
                width: 43,
                height: 43,
                decoration: BoxDecoration(
                  color: AppTheme.surfaceRaised,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(Icons.graphic_eq_rounded, color: AppTheme.mint),
              ),
              const SizedBox(width: 11),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('AURALIS', style: TextStyle(fontSize: 11, letterSpacing: 2.2, color: Colors.white54, fontWeight: FontWeight.w800)),
                    SizedBox(height: 4),
                    Text('Listen your way.', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: AppTheme.mint.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: AppTheme.mint.withValues(alpha: 0.18)),
                ),
                child: const Row(
                  children: <Widget>[
                    Icon(Icons.cloud_off_rounded, size: 13, color: AppTheme.mint),
                    SizedBox(width: 5),
                    Text('NO SERVER', style: TextStyle(fontSize: 9, letterSpacing: 1, color: AppTheme.mint, fontWeight: FontWeight.w800)),
                  ],
                ),
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
              prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.accent),
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
                            Text('${_results.length} tracks', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                            const Spacer(),
                            TextButton.icon(
                              onPressed: _loading ? null : () => _playResults(0),
                              icon: const Icon(Icons.play_arrow_rounded, size: 17),
                              label: const Text('Play all'),
                              style: TextButton.styleFrom(foregroundColor: AppTheme.accent),
                            ),
                          ],
                        ),
                      );
                    }
                    final songIndex = index - 1;
                    final song = _results[songIndex];
                    return SongTile(
                      song: song,
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
    final selected = _source == source;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      onSelected: (_) => setState(() => _source = source),
      labelStyle: TextStyle(
        color: selected ? AppTheme.accent : Colors.white60,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
      side: BorderSide(color: selected ? AppTheme.accent.withValues(alpha: 0.45) : Colors.white10),
      backgroundColor: AppTheme.surface,
      selectedColor: AppTheme.accent.withValues(alpha: 0.12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
    );
  }

  Widget _emptyContent() {
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
    return const SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(24, 24, 24, 18),
      child: Column(
        children: <Widget>[
          SizedBox(height: 18),
          Align(
            alignment: Alignment.centerLeft,
            child: Text('Your music, your device.', style: TextStyle(fontSize: 25, height: 1.1, fontWeight: FontWeight.w800)),
          ),
          SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: Text('Search online, keep favorites and playlists on-device, and save tracks for offline listening.', style: TextStyle(color: Colors.white54, height: 1.5)),
          ),
          SizedBox(height: 22),
          _FeatureCard(
            icon: Icons.queue_music_rounded,
            title: 'A queue that stays yours',
            subtitle: 'Add, reorder, shuffle, and repeat.',
          ),
          SizedBox(height: 10),
          _FeatureCard(
            icon: Icons.offline_bolt_rounded,
            title: 'Take music offline',
            subtitle: 'Downloads live in app-private storage.',
          ),
          SizedBox(height: 10),
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
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(19),
          border: Border.all(color: Colors.white.withValues(alpha: 0.035)),
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: AppTheme.accent.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(13)),
              child: Icon(icon, size: 20, color: AppTheme.accent),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
      );
}
