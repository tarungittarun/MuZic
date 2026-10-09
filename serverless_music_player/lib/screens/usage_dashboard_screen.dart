import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/usage_service.dart';
import '../theme/app_theme.dart';

class UsageDashboardScreen extends StatelessWidget {
  const UsageDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final usage = context.watch<UsageService>();
    final palette = context.palette;
    final recentEvents = usage.recentEvents;
    final topTracks = usage.topTracks;
    final topSearches = usage.topSearches;

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 14, 12),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'ON THIS DEVICE',
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 2,
                        color: palette.textMuted,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Usage',
                      style: TextStyle(fontSize: 27, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Clear usage history',
                onPressed: recentEvents.isEmpty && usage.listeningTime == Duration.zero
                    ? null
                    : () => _confirmClear(context),
                icon: const Icon(Icons.delete_sweep_outlined),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 22),
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'Private activity summary — the last 1,200 actions stay on-device; totals are cumulative. Music searches still contact the selected provider.',
                  style: TextStyle(color: palette.textSecondary, height: 1.45, fontSize: 12),
                ),
              ),
              Wrap(
                spacing: 9,
                runSpacing: 9,
                children: <Widget>[
                  _MetricCard(
                    icon: Icons.search_rounded,
                    label: 'Searches',
                    value: '${usage.searches}',
                  ),
                  _MetricCard(
                    icon: Icons.play_circle_outline_rounded,
                    label: 'Track starts',
                    value: '${usage.playStarts}',
                  ),
                  _MetricCard(
                    icon: Icons.favorite_border_rounded,
                    label: 'Likes added',
                    value: '${usage.favoritesAdded}',
                  ),
                  _MetricCard(
                    icon: Icons.download_outlined,
                    label: 'Downloads',
                    value: '${usage.downloads}',
                  ),
                  _MetricCard(
                    icon: Icons.headphones_rounded,
                    label: 'Listening time',
                    value: _formatDuration(usage.listeningTime),
                  ),
                  _MetricCard(
                    icon: Icons.lyrics_outlined,
                    label: 'Lyrics checks',
                    value: '${usage.lyricsChecks}',
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (topTracks.isNotEmpty) ...<Widget>[
                const _SectionHeading(title: 'Most played'),
                Card(
                  child: Column(
                    children: <Widget>[
                      for (var index = 0; index < topTracks.length; index++) ...<Widget>[
                        if (index > 0)
                          Divider(height: 1, indent: 16, endIndent: 16, color: palette.outline),
                        ListTile(
                          dense: true,
                          leading: CircleAvatar(
                            radius: 16,
                            backgroundColor: palette.accent.withValues(alpha: 0.14),
                            child: Text(
                              '${index + 1}',
                              style: TextStyle(color: palette.accent, fontWeight: FontWeight.w800),
                            ),
                          ),
                          title: Text(topTracks[index].title, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                            '${topTracks[index].artist} · ${_prettySource(topTracks[index].source)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: palette.textMuted, fontSize: 11),
                          ),
                          trailing: Text(
                            '${topTracks[index].plays}×',
                            style: TextStyle(color: palette.accent, fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 18),
              ],
              if (topSearches.isNotEmpty) ...<Widget>[
                const _SectionHeading(title: 'Frequent searches'),
                Card(
                  child: Column(
                    children: <Widget>[
                      for (var index = 0; index < topSearches.length; index++) ...<Widget>[
                        if (index > 0)
                          Divider(height: 1, indent: 16, endIndent: 16, color: palette.outline),
                        ListTile(
                          dense: true,
                          leading: Icon(Icons.manage_search_rounded, color: palette.textMuted),
                          title: Text(topSearches[index].query, maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: Text(
                            '${topSearches[index].searches}×',
                            style: TextStyle(color: palette.textSecondary, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 18),
              ],
              const _SectionHeading(title: 'Recent activity'),
              if (recentEvents.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: <Widget>[
                        Icon(Icons.insights_rounded, color: palette.accent, size: 28),
                        const SizedBox(height: 9),
                        const Text('Your activity will appear here', style: TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 5),
                        Text(
                          'Search, play, like, or download a track to start your private on-device dashboard.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: palette.textMuted, height: 1.4, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                )
              else
                Card(
                  child: Column(
                    children: <Widget>[
                      for (var index = 0; index < recentEvents.length; index++) ...<Widget>[
                        if (index > 0)
                          Divider(height: 1, indent: 16, endIndent: 16, color: palette.outline),
                        _ActivityTile(event: recentEvents[index], palette: palette),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final clear = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear local usage?'),
        content: const Text('This removes saved search and activity events and resets the dashboard totals. Your favorites, downloads, and playlists stay untouched.'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Clear usage')),
        ],
      ),
    );
    if (clear == true && context.mounted) {
      await context.read<UsageService>().clear();
    }
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final width = (MediaQuery.sizeOf(context).width - 41) / 2;
    return SizedBox(
      width: width,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Row(
            children: <Widget>[
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: palette.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: palette.accent, size: 19),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    const SizedBox(height: 3),
                    Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: palette.textMuted, fontSize: 10)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 0, 2, 8),
        child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
      );
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({required this.event, required this.palette});

  final UsageEvent event;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final title = switch (event.type) {
      'search' => 'Searched “${event.query}”',
      'play' => 'Played ${event.title}',
      'favorite_added' => 'Liked ${event.title}',
      'favorite_removed' => 'Unliked ${event.title}',
      'download' => 'Downloaded ${event.title}',
      'download_removed' => 'Removed offline copy of ${event.title}',
      'queue_add' => 'Added ${event.title} to queue',
      'lyrics_check' => 'Checked lyrics for ${event.title}',
      'playlist_create' => 'Created playlist ${event.detail}',
      'playlist_add' => 'Added ${event.title} to ${event.detail}',
      'playlist_delete' => 'Deleted playlist ${event.detail}',
      _ => event.title.isEmpty ? 'Auralis activity' : event.title,
    };
    final subtitleParts = <String>[
      _formatTime(event.timestamp),
      if (event.type == 'search' && event.resultCount != null)
        '${event.resultCount} results · ${_prettySource(event.source)}',
      if (event.type != 'search' && event.source.isNotEmpty)
        _prettySource(event.source),
      if (event.type != 'search' && event.artist.isNotEmpty) event.artist,
    ];
    return ListTile(
      dense: true,
      leading: Icon(_eventIcon(event.type), color: palette.accent, size: 20),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      subtitle: Text(subtitleParts.join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: palette.textMuted, fontSize: 10)),
    );
  }
}

IconData _eventIcon(String type) => switch (type) {
      'search' => Icons.search_rounded,
      'play' => Icons.play_arrow_rounded,
      'favorite_added' => Icons.favorite_rounded,
      'favorite_removed' => Icons.favorite_border_rounded,
      'download' || 'download_removed' => Icons.download_done_rounded,
      'queue_add' => Icons.queue_music_rounded,
      'lyrics_check' => Icons.lyrics_rounded,
      'playlist_create' || 'playlist_add' || 'playlist_delete' => Icons.library_music_rounded,
      _ => Icons.circle_outlined,
    };

String _prettySource(String value) => switch (value) {
      'jioSaavn' => 'JioSaavn',
      'youtube' => 'YouTube',
      'automatic' => 'Auto',
      _ => value,
    };

String _formatTime(DateTime value) {
  final local = value.toLocal();
  final date = '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
  final time = '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
  return '$date $time';
}

String _formatDuration(Duration value) {
  if (value.inSeconds < 60) return '${value.inSeconds}s';
  final hours = value.inHours;
  final minutes = value.inMinutes.remainder(60);
  final seconds = value.inSeconds.remainder(60);
  if (hours > 0) return '${hours}h ${minutes}m';
  return seconds == 0 ? '${minutes}m' : '${minutes}m ${seconds}s';
}
