import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/song_model.dart';

class UsageEvent {
  const UsageEvent({
    required this.type,
    required this.timestamp,
    this.songId = '',
    this.title = '',
    this.artist = '',
    this.source = '',
    this.query = '',
    this.resultCount,
    this.detail = '',
  });

  final String type;
  final DateTime timestamp;
  final String songId;
  final String title;
  final String artist;
  final String source;
  final String query;
  final int? resultCount;
  final String detail;

  factory UsageEvent.fromValue(dynamic value) {
    if (value is! Map) throw const FormatException('Usage event must be a map.');
    final map = Map<String, dynamic>.from(value);
    final rawTime = map['timestamp'];
    final timestamp = rawTime is num
        ? DateTime.fromMillisecondsSinceEpoch(rawTime.toInt())
        : DateTime.tryParse(rawTime?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
    return UsageEvent(
      type: map['type']?.toString() ?? 'unknown',
      timestamp: timestamp,
      songId: map['songId']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      artist: map['artist']?.toString() ?? '',
      source: map['source']?.toString() ?? '',
      query: map['query']?.toString() ?? '',
      resultCount: map['resultCount'] is num
          ? (map['resultCount'] as num).toInt()
          : int.tryParse(map['resultCount']?.toString() ?? ''),
      detail: map['detail']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
        'type': type,
        'timestamp': timestamp.millisecondsSinceEpoch,
        'songId': songId,
        'title': title,
        'artist': artist,
        'source': source,
        'query': query,
        'resultCount': resultCount,
        'detail': detail,
      };
}

class UsageTrackSummary {
  const UsageTrackSummary({
    required this.id,
    required this.title,
    required this.artist,
    required this.source,
    required this.plays,
  });

  final String id;
  final String title;
  final String artist;
  final String source;
  final int plays;
}

class UsageQuerySummary {
  const UsageQuerySummary({required this.query, required this.searches});

  final String query;
  final int searches;
}

class UsageService extends ChangeNotifier {
  static const int _maxRecentEvents = 1200;
  static const String _eventsBoxName = 'local_usage_events';
  static const String _summaryBoxName = 'local_usage_summary';

  late Box<dynamic> _events;
  late Box<dynamic> _summary;
  Future<void> _recordQueue = Future<void>.value();

  Future<void> init() async {
    _events = await Hive.openBox<dynamic>(_eventsBoxName);
    _summary = await Hive.openBox<dynamic>(_summaryBoxName);
  }

  int get searches => _count('search');
  int get playStarts => _count('play');
  int get favoritesAdded => _count('favorite_added');
  int get downloads => _count('download');
  int get queueAdds => _count('queue_add');
  int get lyricsChecks => _count('lyrics_check');

  Duration get listeningTime => Duration(
        milliseconds: _asInt(_summary.get('listening_ms', defaultValue: 0)),
      );

  List<UsageEvent> get _allEvents {
    final result = <UsageEvent>[];
    for (final value in _events.values) {
      try {
        result.add(UsageEvent.fromValue(value));
      } on FormatException {
        continue;
      } on TypeError {
        continue;
      }
    }
    result.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return result;
  }

  List<UsageEvent> get recentEvents =>
      _allEvents.take(100).toList(growable: false);

  List<UsageTrackSummary> get topTracks {
    final aggregates = <String, UsageTrackSummary>{};
    for (final event in _allEvents) {
      if (event.type != 'play' || event.songId.isEmpty) continue;
      final existing = aggregates[event.songId];
      aggregates[event.songId] = UsageTrackSummary(
        id: event.songId,
        title: event.title,
        artist: event.artist,
        source: event.source,
        plays: (existing?.plays ?? 0) + 1,
      );
    }
    final result = aggregates.values.toList()
      ..sort((a, b) => b.plays.compareTo(a.plays));
    return result.take(5).toList(growable: false);
  }

  List<UsageQuerySummary> get topSearches {
    final counts = <String, int>{};
    for (final event in _allEvents) {
      if (event.type != 'search' || event.query.trim().isEmpty) continue;
      final key = event.query.trim();
      counts[key] = (counts[key] ?? 0) + 1;
    }
    final result = counts.entries
        .map((entry) => UsageQuerySummary(query: entry.key, searches: entry.value))
        .toList()
      ..sort((a, b) => b.searches.compareTo(a.searches));
    return result.take(5).toList(growable: false);
  }

  Future<void> recordSearch({
    required String query,
    required String source,
    required int resultCount,
  }) =>
      record(
        type: 'search',
        query: query,
        source: source,
        resultCount: resultCount,
      );

  Future<void> recordSongEvent(String type, SongModel song, {String detail = ''}) =>
      record(
        type: type,
        songId: song.id,
        title: song.title,
        artist: song.artist,
        source: song.source.name,
        detail: detail,
      );

  Future<void> record({
    required String type,
    String songId = '',
    String title = '',
    String artist = '',
    String source = '',
    String query = '',
    int? resultCount,
    String detail = '',
  }) {
    final event = UsageEvent(
      type: type,
      timestamp: DateTime.now(),
      songId: songId,
      title: title,
      artist: artist,
      source: source,
      query: query,
      resultCount: resultCount,
      detail: detail,
    );
    return _enqueue(() async {
      await _events.add(event.toMap());
      final counterKey = 'count_$type';
      await _summary.put(
        counterKey,
        _asInt(_summary.get(counterKey, defaultValue: 0)) + 1,
      );
      while (_events.length > _maxRecentEvents) {
        await _events.deleteAt(0);
      }
      notifyListeners();
    });
  }

  Future<void> addListeningTime(Duration duration) {
    if (duration <= Duration.zero) return Future<void>.value();
    return _enqueue(() async {
      final updated = _asInt(_summary.get('listening_ms', defaultValue: 0)) +
          duration.inMilliseconds;
      await _summary.put('listening_ms', updated);
      notifyListeners();
    });
  }

  Future<void> clear() => _enqueue(() async {
        await _events.clear();
        await _summary.clear();
        notifyListeners();
      });

  Future<void> _enqueue(Future<void> Function() action) {
    final pending = _recordQueue.then((_) => action());
    _recordQueue = pending.catchError((Object error) {
      debugPrint('Could not save local usage: $error');
    });
    return _recordQueue;
  }

  int _count(String type) => _asInt(_summary.get('count_$type', defaultValue: 0));

  int _asInt(dynamic value) => value is num ? value.toInt() : int.tryParse('$value') ?? 0;
}
