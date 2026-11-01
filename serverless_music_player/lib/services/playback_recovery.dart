import '../models/song_model.dart';

enum PlaybackRecoveryAction {
  lowerSourceAQuality,
  refreshSourceA,
  lowerSourceBBitrate,
  alternateSource,
  stop,
}

/// Selects a bounded next step when an online stream errors or stops loading.
///
/// Every retry is keyed in [attempts], so repeated player events cannot create
/// an endless retry loop.
PlaybackRecoveryAction nextPlaybackRecoveryAction({
  required SongModel song,
  required Set<String> attempts,
}) {
  if (song.source == SongSource.local || song.source == SongSource.radio) {
    return PlaybackRecoveryAction.stop;
  }

  final url = song.streamUrl ?? '';
  if (song.source == SongSource.jioSaavn) {
    if (url.contains('_320.mp4') && !attempts.contains('quality')) {
      return PlaybackRecoveryAction.lowerSourceAQuality;
    }
    if (!attempts.contains('source-a-refresh')) {
      return PlaybackRecoveryAction.refreshSourceA;
    }
  }

  if (song.source == SongSource.youtube &&
      !attempts.contains('youtube-low')) {
    return PlaybackRecoveryAction.lowerSourceBBitrate;
  }

  if (!attempts.contains('youtube')) {
    return PlaybackRecoveryAction.alternateSource;
  }

  return PlaybackRecoveryAction.stop;
}
