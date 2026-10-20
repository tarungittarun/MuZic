import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

import 'app_log.dart';

/// Media session + notification bridge for the app's single [AudioPlayer].
///
/// The player is still driven by [PlayerController]; this handler mirrors the
/// player's state into the media session (so the notification, lock screen,
/// Bluetooth controls and Android Auto all see it) and forwards remote
/// commands back to the player.
class MuzicAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  MuzicAudioHandler(this._player) {
    _player.playbackEventStream.map(_transformEvent).pipe(playbackState);
    _player.currentIndexStream.listen((_) => _broadcastMediaItem());
    _player.durationStream.listen((_) => _broadcastMediaItem());
    _player.sequenceStateStream.listen((_) => _broadcastMediaItem());
    _broadcastMediaItem();
    logInfo('audio', 'media session handler created');
  }

  final AudioPlayer _player;

  PlaybackState _transformEvent(PlaybackEvent event) {
    return PlaybackState(
      controls: <MediaControl>[
        MediaControl.skipToPrevious,
        if (_player.playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const <MediaAction>{
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
        MediaAction.play,
        MediaAction.pause,
      },
      androidCompactActionIndices: const <int>[0, 1, 2],
      processingState: switch (_player.processingState) {
        ProcessingState.idle => AudioProcessingState.idle,
        ProcessingState.loading => AudioProcessingState.loading,
        ProcessingState.buffering => AudioProcessingState.buffering,
        ProcessingState.ready => AudioProcessingState.ready,
        ProcessingState.completed => AudioProcessingState.completed,
      },
      playing: _player.playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: event.currentIndex,
    );
  }

  /// Publishes the current track (and the queue) so the notification has a
  /// title, artist, artwork and duration.
  void _broadcastMediaItem() {
    final sequenceState = _player.sequenceState;
    if (sequenceState == null) return;
    final sequence = sequenceState.effectiveSequence.toList(growable: false);
    if (sequence.isEmpty) return;

    final items = <MediaItem>[];
    for (final source in sequence) {
      final tag = source.tag;
      if (tag is MediaItem) items.add(tag);
    }
    if (items.isNotEmpty) queue.add(items);

    final index = _player.currentIndex ?? 0;
    if (index < 0 || index >= sequence.length) return;
    final tag = sequence[index].tag;
    if (tag is! MediaItem) return;
    final current = tag.copyWith(
      duration: _player.duration ?? tag.duration,
    );
    final previous = mediaItem.value;
    if (previous.id != current.id || previous.duration != current.duration) {
      mediaItem.add(current);
      logDebug('audio', 'notification media item', <String, Object?>{
        'title': current.title,
        'id': current.id,
      });
    }
  }

  @override
  Future<void> play() async {
    logInfo('audio', 'remote play');
    await _player.play();
  }

  @override
  Future<void> pause() async {
    logInfo('audio', 'remote pause');
    await _player.pause();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() async {
    logInfo('audio', 'remote next');
    if (_player.hasNext) {
      await _player.seekToNext();
    }
  }

  @override
  Future<void> skipToPrevious() async {
    logInfo('audio', 'remote previous');
    if (_player.position > const Duration(seconds: 3)) {
      await _player.seek(Duration.zero);
    } else if (_player.hasPrevious) {
      await _player.seekToPrevious();
    } else {
      await _player.seek(Duration.zero);
    }
  }

  @override
  Future<void> stop() async {
    logInfo('audio', 'remote stop');
    await _player.stop();
    await super.stop();
  }
}
