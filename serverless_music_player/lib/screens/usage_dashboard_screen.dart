import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/usage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/muzic_home_button.dart';

/// Private, on-device listening insights. This deliberately reports local
/// MuZic activity only; it does not imply provider-wide listening history.
class UsageDashboardScreen extends StatelessWidget {
  const UsageDashboardScreen({this.onHome, super.key});

  final VoidCallback? onHome;

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
          padding: const EdgeInsets.fromLTRB(18, 20, 14, 12),
          child: Row(
            children: <Widget>[
              MuZicHomeButton(onPressed: onHome ?? () {}),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'YOUR LISTENING',
                      style: TextStyle(
                        fontSize: 9,
                        letterSpacing: 1.8,
                        color: palette.textMuted,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    const Text(
                      'Insights',
                      style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Clear usage history',
                onPressed: recentEvents.isEmpty &&
                        usage.listeningTime == Duration.zero
                    ? null
                    : () => _confirmClear(context),
                icon: const Icon(Icons.delete_sweep_outlined),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: <Widget>[
              _ListeningHero(
                listeningTime: usage.listeningTime,
                plays: usage.playStarts,
                searches: usage.searches,
              ),
              const SizedBox(height: 16),
              Row(
                children: <Widget>[
                  const Expanded(
                    child: _SectionHeading(title: 'Your activity'),
                  ),
                  Text(
                    'CUMULATIVE',
                    style: TextStyle(
                      color: palette.textMuted,
                      fontSize: 9,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 9),
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
                    icon: Icons.lyrics_outlined,
                    label: 'Lyrics opened',
                    value: '${usage.lyricsChecks}',
                  ),
                  _MetricCard(
                    icon: Icons.queue_music_rounded,
                    label: 'Added to queue',
                    value: '${usage.queueAdds}',
                  ),
                ],
              ),
              if (topTracks.isNotEmpty) ...<Widget>[
                const SizedBox(height: 22),
                const _SectionHeading(title: 'On repeat'),
                const SizedBox(height: 9),
                Container(
                  decoration: BoxDecoration(
                    color: palette.surface,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: palette.outline),
                  ),
                  child: Column(
                    children: <Widget>[
                      for (var index = 0; index < topTracks.length; index++)
                        _TopTrackRow(
                          index: index,
                          track: topTracks[index],
                          maxPlays: topTracks.first.plays,
                          isLast: index == topTracks.length - 1,
                        ),
                    ],
                  ),
                ),
              ],
              if (topSearches.isNotEmpty) ...<Widget>[
                const SizedBox(height: 22),
                const _SectionHeading(title: 'Your search lanes'),
                const SizedBox(height: 9),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    for (final search in topSearches)
                      _SearchChip(
                        query: search.query,
                        count: search.searches,
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 22),
              Row(
                children: <Widget>[
                  const Expanded(
                    child: _SectionHeading(title: 'Recent activity'),
                  ),
                  Text(
                    '${recentEvents.length} EVENTS',
                    style: TextStyle(
                      color: palette.textMuted,
                      fontSize: 9,
                      letterSpacing: 1.1,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 9),
              if (recentEvents.isEmpty)
                _EmptyActivity(onHome: onHome)
              else
                Container(
                  decoration: BoxDecoration(
                    color: palette.surface,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: palette.outline),
                  ),
                  child: Column(
                    children: <Widget>[
                      for (var index = 0; index < recentEvents.length; index++)
                        _ActivityTile(
                          event: recentEvents[index],
                          isLast: index == recentEvents.length - 1,
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 15),
              Container(
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: palette.surfaceRaised.withValues(alpha: 0.62),
                  borderRadius: BorderRadius.circular(17),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(Icons.lock_outline_rounded,
                        size: 17, color: palette.accent),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        'Private to this device. MuZic keeps the last 1,200 '
                        'activity events locally; totals are cumulative. '
                        'Music searches still contact the selected provider.',
                        style: TextStyle(
                          color: palette.textSecondary,
                          fontSize: 10.5,
                          height: 1.45,
                        ),
                      ),
                    ),
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
        content: const Text(
          'This removes saved activity events and resets the dashboard totals. '
          'Favorites, downloads, and playlists stay untouched.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Clear usage'),
          ),
        ],
      ),
    );
    if (clear == true && context.mounted) {
      await context.read<UsageService>().clear();
    }
  }
}

class _ListeningHero extends StatelessWidget {
  const _ListeningHero({
    required this.listeningTime,
    required this.plays,
    required this.searches,
  });

  final Duration listeningTime;
  final int plays;
  final int searches;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      height: 168,
      padding: const EdgeInsets.all(19),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[
            palette.accent.withValues(alpha: 0.92),
            const Color(0xFF5945A6),
            const Color(0xFF236A69),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: palette.accent.withValues(alpha: 0.20),
            blurRadius: 22,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      child: Stack(
        children: <Widget>[
          Positioned(
            right: -8,
            top: -14,
            child: Icon(
              Icons.headphones_rounded,
              size: 122,
              color: Colors.white.withValues(alpha: 0.10),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(Icons.graphic_eq_rounded,
                      color: Colors.white.withValues(alpha: 0.92), size: 17),
                  const SizedBox(width: 7),
                  Text(
                    'TIME WITH MUSIC',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.86),
                      fontSize: 9,
                      letterSpacing: 1.6,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                _formatDuration(listeningTime),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  height: 1,
                  letterSpacing: -1.1,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '$plays track starts  ·  $searches searches',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.83),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final width = (MediaQuery.sizeOf(context).width - 41) / 2;
    return SizedBox(
      width: width,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: palette.outline),
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 35,
              height: 35,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: <Color>[
                    palette.accent.withValues(alpha: 0.2),
                    palette.mint.withValues(alpha: 0.13),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: palette.accent, size: 18),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: palette.textMuted, fontSize: 9.5),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopTrackRow extends StatelessWidget {
  const _TopTrackRow({
    required this.index,
    required this.track,
    required this.maxPlays,
    required this.isLast,
  });

  final int index;
  final UsageTrackSummary track;
  final int maxPlays;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final ratio = maxPlays <= 0 ? 0.0 : track.plays / maxPlays;
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(13, 12, 14, 10),
          child: Row(
            children: <Widget>[
              Container(
                width: 31,
                height: 31,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: index == 0
                      ? palette.accent.withValues(alpha: 0.22)
                      : palette.surfaceRaised,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Text(
                  '${index + 1}'.padLeft(2, '0'),
                  style: TextStyle(
                    color: index == 0 ? palette.accent : palette.textSecondary,
                    fontWeight: FontWeight.w900,
                    fontSize: 10,
                  ),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(track.title,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 3),
                    Text(
                      '${track.artist} · ${_prettySource(track.source)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: palette.textMuted, fontSize: 10),
                    ),
                    const SizedBox(height: 7),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: ratio.clamp(0.0, 1.0).toDouble(),
                        minHeight: 4,
                        backgroundColor: palette.surfaceRaised,
                        color: index == 0 ? palette.accent : palette.mint,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${track.plays}×',
                style: TextStyle(
                  color: palette.accent,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
        if (!isLast)
          Divider(height: 1, indent: 56, endIndent: 12, color: palette.outline),
      ],
    );
  }
}

class _SearchChip extends StatelessWidget {
  const _SearchChip({required this.query, required this.count});

  final String query;
  final int count;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 11, 8),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: palette.outline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.search_rounded, size: 15, color: palette.accent),
          const SizedBox(width: 7),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.46,
            ),
            child: Text(query, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 7),
          Text(
            '$count×',
            style: TextStyle(
              color: palette.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
      );
}

class _EmptyActivity extends StatelessWidget {
  const _EmptyActivity({required this.onHome});

  final VoidCallback? onHome;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: palette.outline),
      ),
      child: Column(
        children: <Widget>[
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: <Color>[
                  palette.accent.withValues(alpha: 0.2),
                  palette.mint.withValues(alpha: 0.14),
                ],
              ),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.insights_rounded, color: palette.accent),
          ),
          const SizedBox(height: 12),
          const Text(
            'Your next favorite starts here',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
          const SizedBox(height: 6),
          Text(
            'Search, listen, like, or download a track to build your private '
            'listening history.',
            textAlign: TextAlign.center,
            style: TextStyle(color: palette.textMuted, height: 1.4, fontSize: 11),
          ),
          if (onHome != null) ...<Widget>[
            const SizedBox(height: 13),
            FilledButton.tonalIcon(
              onPressed: onHome,
              icon: const Icon(Icons.search_rounded, size: 17),
              label: const Text('Find music'),
            ),
          ],
        ],
      ),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({required this.event, required this.isLast});

  final UsageEvent event;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
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
      _ => event.title.isEmpty ? 'Music activity' : event.title,
    };
    final subtitleParts = <String>[
      _formatTime(event.timestamp),
      if (event.type == 'search' && event.resultCount != null)
        '${event.resultCount} results · ${_prettySource(event.source)}',
      if (event.type != 'search' && event.source.isNotEmpty)
        _prettySource(event.source),
      if (event.type != 'search' && event.artist.isNotEmpty) event.artist,
    ];

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(13, 9, 13, 9),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 32,
                child: Column(
                  children: <Widget>[
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: palette.accent.withValues(alpha: 0.13),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(_eventIcon(event.type),
                          color: palette.accent, size: 16),
                    ),
                    if (!isLast)
                      Container(
                        width: 1,
                        height: 16,
                        color: palette.outline,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitleParts.join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: palette.textMuted, fontSize: 9.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (!isLast)
          Divider(height: 1, indent: 56, endIndent: 13, color: palette.outline),
      ],
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
      'playlist_create' || 'playlist_add' || 'playlist_delete' =>
        Icons.library_music_rounded,
      _ => Icons.circle_outlined,
    };

String _prettySource(String value) => switch (value) {
      'jioSaavn' => 'Source A',
      'youtube' => 'Source B',
      'automatic' => 'Auto',
      _ => value,
    };

String _formatTime(DateTime value) {
  final local = value.toLocal();
  final date = '${local.day.toString().padLeft(2, '0')} '
      '${_monthName(local.month)}';
  final time = '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
  return '$date · $time';
}

String _monthName(int month) => const <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ][month - 1];

String _formatDuration(Duration value) {
  if (value.inSeconds < 60) return '${value.inSeconds}s';
  final hours = value.inHours;
  final minutes = value.inMinutes.remainder(60);
  final seconds = value.inSeconds.remainder(60);
  if (hours > 0) return '${hours}h ${minutes}m';
  return seconds == 0 ? '${minutes}m' : '${minutes}m ${seconds}s';
}
