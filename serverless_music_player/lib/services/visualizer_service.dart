import 'dart:async';

import 'package:flutter/services.dart';

import 'app_log.dart';

/// Streams live waveform bands (0..1) captured from the active playback
/// session by the Android Visualizer API.
class VisualizerService {
  VisualizerService({EventChannel? channel})
      : _channel = channel ?? const EventChannel('music_player/visualizer');

  final EventChannel _channel;
  StreamSubscription<dynamic>? _subscription;
  final StreamController<List<double>> _controller =
      StreamController<List<double>>.broadcast();

  Stream<List<double>> get bands => _controller.stream;

  bool _listening = false;

  /// Starts capturing. [sessionId] is the Android audio session that playback
  /// is using; 0 means "not available yet".
  void start(int? sessionId) {
    if (_listening) return;
    _listening = true;
    _subscription = _channel.receiveBroadcastStream(sessionId ?? 0).listen(
      (dynamic event) {
        if (event is! List) return;
        final values = <double>[];
        for (final item in event) {
          if (item is num) values.add(item.toDouble().clamp(0.0, 1.0));
        }
        if (values.isNotEmpty) _controller.add(values);
      },
      onError: (Object error) {
        logWarn('visualizer', 'capture unavailable', <String, Object?>{
          'error': '$error',
        });
        _listening = false;
      },
      cancelOnError: false,
    );
    logInfo('visualizer', 'capture started', <String, Object?>{
      'sessionId': sessionId,
    });
  }

  Future<void> stop() async {
    if (!_listening) return;
    _listening = false;
    await _subscription?.cancel();
    _subscription = null;
    logDebug('visualizer', 'capture stopped');
  }

  void dispose() {
    unawaited(stop());
    unawaited(_controller.close());
  }
}
