import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_settings_service.dart';

/// Page-specific reachability: three firm pull-downs at the top of the
/// currently visible page translate it into thumb reach. The page retains its
/// normal full-height viewport; scrolling back up hands the space back without
/// trapping the page in a smaller scroll area.
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

class _OneHandReachState extends State<OneHandReach>
    with SingleTickerProviderStateMixin {
  static const Duration _dropDuration = Duration(milliseconds: 260);
  static const Duration _pullWindow = Duration(seconds: 3);

  late final AnimationController _dropController = AnimationController(
    vsync: this,
    duration: _dropDuration,
  )..addStatusListener(_onDropStatusChanged);

  bool _active = false;
  bool _dropAnimating = false;
  double _offset = 0;
  double _maxDrop = 0;
  int _pullDownCount = 0;
  DateTime? _pullWindowStart;
  bool _atTop = true;
  Offset? _pointerStart;
  Offset? _pointerLast;
  bool _pullCountedThisPointer = false;
  bool? _wasEnabled;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final enabled = context.read<AppSettingsService>().oneHandModeEnabled;
    if (_wasEnabled == true && !enabled) _resetReach();
    _wasEnabled = enabled;
  }

  @override
  void didUpdateWidget(covariant OneHandReach oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.visible) _resetReach();
  }

  void _onDropStatusChanged(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted || !_dropAnimating) {
      return;
    }
    setState(() {
      _dropAnimating = false;
      _offset = _maxDrop;
    });
  }

  void _resetReach() {
    _dropAnimating = false;
    _active = false;
    _offset = 0;
    _pullDownCount = 0;
    _pullWindowStart = null;
    _pointerStart = null;
    _pointerLast = null;
    _pullCountedThisPointer = false;
    _dropController.stop();
    _dropController.value = 0;
  }

  void _handlePointerDown(PointerDownEvent event) {
    _pointerStart = event.position;
    _pointerLast = event.position;
    _pullCountedThisPointer = false;
  }

  void _handlePointerMove(PointerMoveEvent event) {
    final start = _pointerStart;
    final last = _pointerLast;
    if (start == null || last == null) return;
    final movement = event.position - last;
    _pointerLast = event.position;
    if (!widget.visible ||
        !context.read<AppSettingsService>().oneHandModeEnabled) {
      return;
    }

    if (_active) {
      // Follow upward finger movement directly in a transform layer. This is
      // independent of scroll-physics overscroll thresholds on each device.
      if (_dropAnimating || movement.dy >= 0) return;
      final next = (_offset + movement.dy).clamp(0.0, _maxDrop).toDouble();
      if (next != _offset) {
        setState(() {
          _offset = next;
          if (_offset <= 0) {
            _active = false;
            _pullDownCount = 0;
            _pullWindowStart = null;
          }
        });
      }
      return;
    }

    if (!_atTop || _pullCountedThisPointer) return;
    final total = event.position - start;
    if (total.dy < 64 || total.dy < total.dx.abs() * 1.25) return;
    _pullCountedThisPointer = true;
    _recordPullDown();
  }

  void _recordPullDown() {
    final now = DateTime.now();
    if (_pullWindowStart == null ||
        now.difference(_pullWindowStart!) > _pullWindow) {
      _pullWindowStart = now;
      _pullDownCount = 1;
    } else {
      _pullDownCount++;
    }

    if (_pullDownCount >= 3 && _maxDrop > 0) {
      _pullDownCount = 0;
      _pullWindowStart = null;
      _active = true;
      _dropAnimating = true;
      _offset = _maxDrop;
      _dropController.forward(from: 0);
      setState(() {});
    }
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (!widget.visible ||
        !context.read<AppSettingsService>().oneHandModeEnabled) {
      return false;
    }
    final metrics = notification.metrics;
    if (metrics.axis != Axis.vertical) return false;
    _atTop = metrics.extentBefore <= 0.5;

    return false;
  }

  @override
  void dispose() {
    _dropController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = context.select<AppSettingsService, bool>(
      (settings) => settings.oneHandModeEnabled,
    );
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: (_) {
        _pointerStart = null;
        _pointerLast = null;
      },
      onPointerCancel: (_) {
        _pointerStart = null;
        _pointerLast = null;
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: _handleScrollNotification,
        child: LayoutBuilder(
          builder: (context, constraints) {
            _maxDrop = constraints.maxHeight * 0.42;
            return ClipRect(
              child: AnimatedBuilder(
                animation: _dropController,
                child: widget.child,
                builder: (context, child) {
                  final offset = !enabled || !widget.visible || !_active
                      ? 0.0
                      : _dropAnimating
                          ? _maxDrop * Curves.easeOutCubic.transform(
                              _dropController.value,
                            )
                          : _offset.clamp(0.0, _maxDrop).toDouble();
                  return Transform.translate(
                    key: const ValueKey<String>('one-hand-page-transform'),
                    offset: Offset(0, offset),
                    child: child,
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}
