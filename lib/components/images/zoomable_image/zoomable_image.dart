import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/images/zoomable_image/pinch_zoom_release_unzoom_widget.dart';

/// Provides the “blockScroll” callbacks to all descendants.
class PinchScrollScope extends InheritedWidget {
  final VoidCallback onPinchStart;
  final VoidCallback onPinchEnd;

  const PinchScrollScope({
    super.key,
    required this.onPinchStart,
    required this.onPinchEnd,
    required super.child,
  });

  static PinchScrollScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PinchScrollScope>();

  @override
  bool updateShouldNotify(covariant PinchScrollScope old) => false;
}

/// Wraps any child and provides a scroll view that can be blocked
/// during two-finger pinch gestures.
class PinchScrollView extends StatefulWidget {
  final Widget Function(VoidCallback onPinchStart, VoidCallback onPinchEnd)
      builder;

  const PinchScrollView({super.key, required this.builder});

  @override
  State<PinchScrollView> createState() => _PinchScrollViewState();
}

class _PinchScrollViewState extends State<PinchScrollView> {
  bool blockScroll = false;
  final ScrollController controller = ScrollController();

  void _onPinchStart() {
    setState(() => blockScroll = true);
  }

  void _onPinchEnd() {
    Future.delayed(
      PinchZoomReleaseUnzoomWidget.defaultResetDuration,
      () {

        setState(() => blockScroll = false);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return PinchScrollScope(
      onPinchStart: _onPinchStart,
      onPinchEnd: _onPinchEnd,
      child: SingleChildScrollView(
        controller: controller,
        physics: blockScroll
            ? const NeverScrollableScrollPhysics()
            : const BouncingScrollPhysics(),
        child: widget.builder(_onPinchStart, _onPinchEnd),
      ),
    );
  }
}

/// A small widget that listens for raw pointer downs/ups,
/// counts fingers, and fires your two-finger callbacks (or the inherited ones).
class ZoomableImage extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTwoFingerStart;
  final VoidCallback? onTwoFingerEnd;

  const ZoomableImage({
    super.key,
    required this.child,
    this.onTwoFingerStart,
    this.onTwoFingerEnd,
  });

  @override
  State<ZoomableImage> createState() => _ZoomableImageState();
}

class _ZoomableImageState extends State<ZoomableImage> {
  int _pointers = 0;

  void _handlePointerDown(PointerDownEvent e) {
    _pointers++;
    if (_pointers == 2) {

      final cb =
          widget.onTwoFingerStart ?? PinchScrollScope.of(context)?.onPinchStart;
      cb?.call();
    }
  }

  void _handlePointerUp(PointerUpEvent e) {
    _pointers = (_pointers - 1).clamp(0, 10);
    if (_pointers < 1) {

      final cb =
          widget.onTwoFingerEnd ?? PinchScrollScope.of(context)?.onPinchEnd;
      cb?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _handlePointerDown,
      onPointerUp: _handlePointerUp,
      child: PinchZoomReleaseUnzoomWidget(
        maxScale: 4,
        fingersRequiredToPinch: 2,
        child: widget.child,
      ),
    );
  }
}
