import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_player/services/video_library_service.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;
  late File store;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('muzic_video_library_test');
    store = File(p.join(temp.path, 'lyric_videos.json'));
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('starts empty when no store exists', () async {
    final service = VideoLibraryService(store: store);
    await service.init();
    expect(service.videos, isEmpty);
    expect(service.count, 0);
    expect(service.isEmpty, isTrue);
  });

  test('records an export and persists it across instances', () async {
    final first = VideoLibraryService(store: store);
    await first.init();
    final record = await first.add(
      songId: 'saavn:1',
      title: 'Pehle Bhi Main',
      artist: 'Vishal Mishra',
      path: 'content://media/external/video/media/42',
      durationMs: 253000,
    );

    expect(first.count, 1);
    expect(first.hasVideoFor('saavn:1'), isTrue);
    expect(first.hasVideoFor('saavn:2'), isFalse);
    expect(record.title, 'Pehle Bhi Main');

    final second = VideoLibraryService(store: store);
    await second.init();
    expect(second.count, 1);
    expect(second.videos.single.path, record.path);
    expect(second.videos.single.durationMs, 253000);
    expect(second.videos.single.songId, 'saavn:1');
  });

  test('newest export is listed first', () async {
    final service = VideoLibraryService(store: store);
    await service.init();
    await service.add(
      songId: 'a',
      title: 'First',
      artist: 'A',
      path: 'content://one',
    );
    await Future<void>.delayed(const Duration(milliseconds: 3));
    await service.add(
      songId: 'b',
      title: 'Second',
      artist: 'B',
      path: 'content://two',
    );
    expect(service.videos.first.title, 'Second');
    expect(service.videos.last.title, 'First');
  });

  test('remove drops only the matching entry', () async {
    final service = VideoLibraryService(store: store);
    await service.init();
    final keep = await service.add(
      songId: 'a',
      title: 'Keep',
      artist: 'A',
      path: 'content://keep',
    );
    final drop = await service.add(
      songId: 'b',
      title: 'Drop',
      artist: 'B',
      path: 'content://drop',
    );

    await service.remove(drop.id);
    expect(service.count, 1);
    expect(service.videos.single.id, keep.id);

    final reloaded = VideoLibraryService(store: store);
    await reloaded.init();
    expect(reloaded.count, 1);
    expect(reloaded.videos.single.title, 'Keep');
  });

  test('survives a corrupt store file', () async {
    await store.writeAsString('{not json at all');
    final service = VideoLibraryService(store: store);
    await service.init();
    expect(service.videos, isEmpty);
    // And it can still write a good file afterwards.
    await service.add(
      songId: 'a',
      title: 'Recovered',
      artist: 'A',
      path: 'content://ok',
    );
    final reloaded = VideoLibraryService(store: store);
    await reloaded.init();
    expect(reloaded.videos.single.title, 'Recovered');
  });

  test('prunes records whose file disappeared', () async {
    final video = File(p.join(temp.path, 'clip.mp4'));
    await video.writeAsBytes(<int>[0, 1, 2, 3]);
    final service = VideoLibraryService(store: store);
    await service.init();
    await service.add(
      songId: 'a',
      title: 'Disk',
      artist: 'A',
      path: video.path,
    );
    await video.delete();
    await service.pruneMissing();
    expect(service.videos, isEmpty);
  });
}
