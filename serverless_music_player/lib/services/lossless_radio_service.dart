import '../models/song_model.dart';

/// A free, publicly documented lossless (FLAC) internet radio station.
class RadioStation {
  const RadioStation({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.streamUrl,
  });

  final String id;
  final String name;
  final String subtitle;
  final String streamUrl;

  SongModel toSong() => SongModel(
        id: 'radio:$id',
        sourceId: id,
        title: name,
        artist: subtitle,
        album: 'Lossless FLAC radio',
        source: SongSource.radio,
        streamUrl: streamUrl,
      );
}

/// Curated free FLAC streams (Radio Paradise publishes these URLs openly).
class LosslessRadioService {
  static const List<RadioStation> stations = <RadioStation>[
    RadioStation(
      id: 'paradise-main',
      name: 'Radio Paradise — Main Mix',
      subtitle: 'Eclectic mix · live FLAC',
      streamUrl: 'https://stream.radioparadise.com/flac',
    ),
    RadioStation(
      id: 'paradise-mellow',
      name: 'Radio Paradise — Mellow Mix',
      subtitle: 'Mellow mix · live FLAC',
      streamUrl: 'https://stream.radioparadise.com/mellow-flac',
    ),
    RadioStation(
      id: 'paradise-rock',
      name: 'Radio Paradise — Rock Mix',
      subtitle: 'Rock mix · live FLAC',
      streamUrl: 'https://stream.radioparadise.com/rock-flac',
    ),
    RadioStation(
      id: 'paradise-eclectic',
      name: 'Radio Paradise — Global Mix',
      subtitle: 'World / eclectic · live FLAC',
      streamUrl: 'https://stream.radioparadise.com/eclectic-flac',
    ),
  ];
}
