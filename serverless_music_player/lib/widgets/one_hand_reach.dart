import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/song_model.dart';
import '../providers/player_controller.dart';
import '../services/app_settings_service.dart';
import '../services/library_service.dart';
import '../theme/app_theme.dart';
import 'cover_art.dart';

/// Page-specific One UI-style reachability.
///
/// Three firm pull-downs at the top of *this* page drop its content into
/// thumb reach and reveal a simple last-played card in the space above.
/// The page keeps its full-height viewport underneath: as the user scrolls
/// up, the dropped amount shrinks in step with the scroll until the page
/// is full-screen again and ordinary scrolling continues normally. Nothing is
/// trapped inside a permanent half-screen box, and the state belongs to
/// this page only — switching tabs resets it.
class OneHandReach extends StatefulWidget {
  const OneHandReach({
    required this.visible,
    required this.child,
    super.key,
  });

  /// Whether this is the currently selected main page.
  final bool visible;
  final Widget child;

  @override
  State<OneHandReach> createState() => _OneHandReachState();
}

class _OneHandReachState extends State<OneHandReach> {
  bool _active = false;
  double _offset = 0;
  double _maxDrop = 0;
  int _pullDownCount = 0;
  DateTime? _pullWindowStart;
  bool _pullCountedThisDrag = false;

  @override
  void didUpdateWidget(covariant OneHandReach oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.visible) {
      // Page-specific: leaving the page always restores full screen.
      _active = false;
      _offset = 0;
      _pullDownCount = 0;
      _pullWindowStart = null;
    }
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (!widget.visible ||
        !context.read<AppSettingsService>().oneHandModeEnabled) {
      return false;
    }
    final metrics = notification.metrics;
    if (metrics.axis != Axis.vertical) return false;

    if (notification is ScrollStartNotification) {
      _pullCountedThisDrag = false;
      return false;
    }

    if (_active) {
      // Scrolling up hands the dropped space back smoothly: the offset
      // shrinks with the scroll delta, then ordinary scrolling continues.
      if (notification is ScrollUpdateNotification) {
        final delta = notification.scrollDelta ?? 0;
        if (delta == 0) return false;
        final next = (_offset - delta).clamp(0.0, _maxDrop).toDouble();
        if (next != _offset) {
          setState(() {
            _offset = next;
            if (_offset <= 0) _active = false;
          });
        }
      }
      return false;
    }

    if (notification is! OverscrollNotification ||
        _pullCountedThisDrag ||
        metrics.extentBefore != 0 ||
        notification.overscroll >= -14) {
      return false;
    }
    _pullCountedThisDrag = true;
    final now = DateTime.now();
    if (_pullWindowStart == null ||
        now.difference(_pullWindowStart!) > const Duration(seconds: 2)) {
      _pullWindowStart = now;
      _pullDownCount = 1;
    } else {
      _pullDownCount++;
    }
    if (_pullDownCount >= 3 && _maxDrop > 0) {
      _pullDownCount = 0;
      _pullWindowStart = null;
      setState(() {
        _active = true;
        _offset = _maxDrop;
      });
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final enabled = context.select<AppSettingsService, bool>(
      (settings) => settings.oneHandModeEnabled,
    );
    return NotificationListener<ScrollNotification>(
      onNotification: _handleScrollNotification,
      child: LayoutBuilder(
        builder: (context, constraints) {
          _maxDrop = constraints.maxHeight * 0.42;
          final offset = enabled && _active
              ? _offset.clamp(0.0, _maxDrop).toDouble()
              : 0.0;
          return ClipRect(
            child: Stack(
              children: <Widget>[
                // Full-height viewport, just translated down. The page
                // scrolls exactly as usual; only its top is dropped.
                Positioned(
                  left: 0,
                  right: 0,
                  top: offset,
                  bottom: -offset,
                  child: widget.child,
                ),
                if (offset > 24)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    height: offset,
                    child: Opacity(
                      opacity: (offset / _maxDrop).clamp(0.0, 1.0).toDouble(),
                      child: const _LastPlayedBanner(),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Simple, useful card for the space opened above a dropped page: the
/// song playing now, or the last one the user played.
class _LastPlayedBanner extends StatelessWidget {
  const _LastPlayedBanner();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final current = context.select<PlayerController, SongModel?>(
      (player) => player.currentSong,
    );
    final lastPlayed = context.select<LibraryService, SongModel?>(
      (library) => library.recentSongs.isEmpty ? null : library.recentSongs.first,
    );
    final song = current ?? lastPlayed;
    final isCurrent = current != null;
    final isPlaying = context.select<PlayerController, bool>(
      (player) => isCurrent && player.isPlaying,
    );
    final player = context.read<PlayerController>();

    return SafeArea(
      bottom: false,
      child: Align(
        alignment: Alignment.center,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            decoration: BoxDecoration(
              color: palette.surface.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: palette.outline, width: 0.8),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.22),
                  blurRadius: 18,
                  offset: const Offset(0, 7),
                ),
              ],
            ),
            child: Row(
              children: <Widget>[
                if (song != null)
                  CoverArt(song: song, size: 54, radius: 14)
                else
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: palette.accent.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(Icons.music_note_rounded, color: palette.accent),
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        isCurrent ? 'NOW PLAYING' : 'LAST PLAYED',
                        style: TextStyle(
                          color: palette.textMuted,
                          fontSize: 9.5,
                          letterSpacing: 1.6,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        song?.title ?? 'Nothing played yet',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        song?.artist ?? 'Play a song and it will live here.',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: palette.textMuted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                if (song != null)
                  IconButton.filled(
                    tooltip: isCurrent
                        ? (isPlaying ? 'Pause' : 'Play')
                        : 'Play again',
                    onPressed: () {
                      if (isCurrent) {
                        player.togglePlayback();
                      } else {
                        player.playQueue(<SongModel>[song], initialIndex: 0);
                      }
                    },
                    icon: Icon(
                      isCurrent && isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
