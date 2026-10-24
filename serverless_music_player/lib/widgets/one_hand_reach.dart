import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_settings_service.dart';

/// Keeps horizontal carousels available while the reach gesture returns the
/// translated page to its normal position. Without this vertical-only lock,
/// the restoring swipe also scrolls the page itself and pushes its header out
/// of view behind the newly uncovered background.
class _ReachScrollBehavior extends MaterialScrollBehavior {
  const _ReachScrollBehavior({required this.lockVertical});

  final bool lockVertical;

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    final platformPhysics = super.getScrollPhysics(context);
    return lockVertical
        ? _VerticalReachLockPhysics(parent: platformPhysics)
        : platformPhysics;
  }
}

class _VerticalReachLockPhysics extends ScrollPhysics {
  const _VerticalReachLockPhysics({super.parent});

  bool _isVertical(ScrollMetrics position) =>
      position.axisDirection == AxisDirection.down ||
      position.axisDirection == AxisDirection.up;

  @override
  bool shouldAcceptUserOffset(ScrollMetrics position) {
    if (_isVertical(position)) return false;
    return super.shouldAcceptUserOffset(position);
  }

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) {
    if (_isVertical(position)) return 0;
    return super.applyPhysicsToUserOffset(position, offset);
  }

  @override
  _VerticalReachLockPhysics applyTo(ScrollPhysics? ancestor) =>
      _VerticalReachLockPhysics(parent: buildParent(ancestor));
}

/// Page-specific reachability: two firm pull-downs at the top of the
/// currently visible page translate it down by half a screen. The page retains
/// its normal full-height viewport; scrolling back up hands the space back
/// without trapping the page in a smaller scroll area.
class OneHandReach extends StatefulWidget {
  const OneHandReach({required this.visible, required this.child, super.key});

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
  bool _restoring = false;
  bool _restoreGestureStarted = false;
  double _restoreStartOffset = 0;
  double _offset = 0;
  double _maxDrop = 0;
  int _pullDownCount = 0;
  DateTime? _pullWindowStart;
  bool _atTop = true;
  Offset? _pointerStart;
  Offset? _pointerLast;
  bool _pullCountedThisPointer = false;
  bool _restoreScrollLockUntilPointerUp = false;
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
    if (status != AnimationStatus.completed || !mounted) return;
    if (_dropAnimating) {
      setState(() {
        _dropAnimating = false;
        _offset = _maxDrop;
      });
      return;
    }
    if (_restoring) {
      setState(() {
        _restoring = false;
        _active = false;
        _offset = 0;
        _restoreStartOffset = 0;
        _restoreScrollLockUntilPointerUp = false;
        _pullDownCount = 0;
        _pullWindowStart = null;
      });
    }
  }

  void _resetReach() {
    _dropAnimating = false;
    _restoring = false;
    _restoreGestureStarted = false;
    _restoreStartOffset = 0;
    _active = false;
    _offset = 0;
    _pullDownCount = 0;
    _pullWindowStart = null;
    _pointerStart = null;
    _pointerLast = null;
    _pullCountedThisPointer = false;
    _restoreScrollLockUntilPointerUp = false;
    _dropController.stop();
    _dropController.value = 0;
  }

  void _handlePointerDown(PointerDownEvent event) {
    _pointerStart = event.position;
    _pointerLast = event.position;
    _pullCountedThisPointer = false;
    _restoreGestureStarted = false;
  }

  void _handlePointerEnd(PointerEvent event) {
    final shouldSnapBack =
        _active && _restoreGestureStarted && _offset > 0 && mounted;
    _pointerStart = null;
    _pointerLast = null;
    _restoreGestureStarted = false;
    if (shouldSnapBack) {
      _animateRestoreToTop();
    } else if (_restoreScrollLockUntilPointerUp && mounted) {
      setState(() => _restoreScrollLockUntilPointerUp = false);
    }
  }

  void _animateRestoreToTop() {
    if (!_active || _offset <= 0 || !mounted) return;
    setState(() {
      _restoring = true;
      _restoreStartOffset = _offset;
    });
    _dropController.forward(from: 0);
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
      if (movement.dy >= 0) return;
      _restoreGestureStarted = true;
      if (_dropAnimating) {
        // A quick return swipe must be allowed to interrupt the drop-in
        // animation; otherwise the page appears stuck until that animation
        // finishes, leaving a temporary black gap above it.
        _offset =
            _maxDrop * Curves.easeOutCubic.transform(_dropController.value);
        _dropController.stop();
        _dropAnimating = false;
      }
      final next = (_offset + movement.dy).clamp(0.0, _maxDrop).toDouble();
      setState(() {
        _offset = next;
        if (_offset <= 0) {
          _active = false;
          // Keep vertical scrolling locked for the remainder of this finger
          // gesture. Otherwise the same upward swipe first removes the
          // reach offset and then scrolls the page underneath it, making the
          // header disappear behind the newly exposed blank area.
          _restoreScrollLockUntilPointerUp = true;
          _pullDownCount = 0;
          _pullWindowStart = null;
        }
      });
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

    if (_pullDownCount >= 2 && _maxDrop > 0) {
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

    // Physics is the first line of defence. This also rolls back any position
    // change that slipped through while the transformed page was being
    // restored, so the app header cannot remain scrolled behind the exposed
    // blank area on devices with different scroll/gesture arbitration.
    if ((_active || _restoreScrollLockUntilPointerUp) &&
        notification is ScrollUpdateNotification &&
        metrics.extentBefore > 0.5) {
      final scrollContext = notification.context;
      final scrollable = scrollContext == null
          ? null
          : Scrollable.maybeOf(scrollContext);
      final position = scrollable?.position;
      if (position != null && position.hasContentDimensions) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !position.hasContentDimensions) return;
          final top = position.minScrollExtent;
          if (position.pixels > top + 0.5) position.jumpTo(top);
          _atTop = true;
        });
      }
    }

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
      onPointerUp: _handlePointerEnd,
      onPointerCancel: _handlePointerEnd,
      child: NotificationListener<ScrollNotification>(
        onNotification: _handleScrollNotification,
        child: LayoutBuilder(
          builder: (context, constraints) {
            _maxDrop = constraints.maxHeight * 0.50;
            return ClipRect(
              child: AnimatedBuilder(
                animation: _dropController,
                child: widget.child,
                builder: (context, child) {
                  final offset = !enabled || !widget.visible || !_active
                      ? 0.0
                      : _dropAnimating
                      ? _maxDrop *
                            Curves.easeOutCubic.transform(_dropController.value)
                      : _restoring
                      ? _restoreStartOffset *
                            (1 -
                                Curves.easeInOutCubic.transform(
                                  _dropController.value,
                                ))
                      : _offset.clamp(0.0, _maxDrop).toDouble();
                  final lockVerticalScroll =
                      enabled &&
                      widget.visible &&
                      (_active || _restoreScrollLockUntilPointerUp);
                  return ScrollConfiguration(
                    behavior: lockVerticalScroll
                        ? const _ReachScrollBehavior(lockVertical: true)
                        : const _ReachScrollBehavior(lockVertical: false),
                    child: Transform.translate(
                      key: const ValueKey<String>('one-hand-page-transform'),
                      offset: Offset(0, offset),
                      child: child,
                    ),
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
