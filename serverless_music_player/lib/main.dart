import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'app.dart';
import 'providers/player_controller.dart';
import 'services/audio_player_service.dart';
import 'services/download_service.dart';
import 'services/library_service.dart';
import 'services/music_api_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.auralis.player.audio',
    androidNotificationChannelName: 'Auralis playback',
    androidNotificationOngoing: true,
  );

  final library = LibraryService();
  await library.init();
  final musicApi = MusicApiService();
  final audio = AudioPlayerService();
  final downloads = DownloadService(library: library);
  final player = PlayerController(
    audio: audio,
    musicApi: musicApi,
    downloads: downloads,
    library: library,
  );

  runApp(AuralisApp(
    library: library,
    musicApi: musicApi,
    audio: audio,
    downloads: downloads,
    player: player,
  ));
}
