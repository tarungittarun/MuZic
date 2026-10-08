import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

import '../models/song_model.dart';

class AudioPlayerService {
  AudioPlayerService() : player = AudioPlayer();

  final AudioPlayer player;

  AudioSource sourceFor(
    SongModel song, {
    String? remoteUrl,
    String? localPath,
  }) {
    final artUri = _artUri(song);
    final tag = MediaItem(
      id: song.id,
      title: song.title,
      artist: song.artist,
      album: song.album,
      artUri: artUri,
      extras: <String, dynamic>{'source': song.source.name},
    );
    if (localPath != null) {
      return AudioSource.file(localPath, tag: tag);
    }
    final url = remoteUrl ?? song.streamUrl;
    if (url == null || url.isEmpty) {
      throw StateError('No audio URL is available for ${song.title}.');
    }
    return AudioSource.uri(Uri.parse(url), tag: tag);
  }

  Future<Duration?> setQueue(
    List<AudioSource> sources, {
    required int initialIndex,
    Duration initialPosition = Duration.zero,
  }) {
    return player.setAudioSources(
      sources,
      initialIndex: initialIndex,
      initialPosition: initialPosition,
    );
  }

  Future<void> append(AudioSource source) => player.addAudioSource(source);

  Future<void> move(int from, int to) => player.moveAudioSource(from, to);

  Future<void> dispose() async {
    await player.dispose();
  }

  Uri? _artUri(SongModel song) {
    final localArt = song.localArtworkPath;
    if (localArt != null && localArt.isNotEmpty && File(localArt).existsSync()) {
      return Uri.file(localArt);
    }
    final url = song.artworkUrl;
    final uri = Uri.tryParse(url);
    if (uri != null && (uri.scheme == 'https' || uri.scheme == 'http')) {
      return uri;
    }
    return null;
  }
}
