import 'dart:async';
import 'package:material_ui/material_ui.dart';

/// Retries a failed preview twice, then leaves the existing error affordance.
/// The provider retains its normal cache policy for successful images.
class RecoveringImage extends StatefulWidget {
  const RecoveringImage(
      {super.key,
      required this.image,
      this.fit = BoxFit.contain,
      this.width,
      this.height});
  final ImageProvider image;
  final BoxFit fit;
  final double? width;
  final double? height;
  @override
  State<RecoveringImage> createState() => _RecoveringImageState();
}

class _RecoveringImageState extends State<RecoveringImage> {
  Timer? _retry;
  int _attempt = 0;
  int _generation = 0;

  @override
  void didUpdateWidget(RecoveringImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image != widget.image) {
      _retry?.cancel();
      _retry = null;
      _attempt = 0;
      _generation++;
    }
  }

  void _retryAfterFailure() {
    if (_retry != null || _attempt >= 2) return;
    final generation = _generation;
    final image = widget.image;
    _retry = Timer(Duration(milliseconds: 500 * (_attempt + 1)), () async {
      if (!mounted || generation != _generation) return;
      await image.evict();
      if (!mounted || generation != _generation) return;
      setState(() {
        _retry = null;
        _attempt++;
      });
    });
  }

  @override
  void dispose() {
    _generation++;
    _retry?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Image(
        key: ValueKey(_attempt),
        image: widget.image,
        fit: widget.fit,
        width: widget.width,
        height: widget.height,
        errorBuilder: (_, error, stack) {
          _retryAfterFailure();
          return const Icon(Icons.broken_image, size: 24);
        },
        frameBuilder: (_, child, frame, synchronous) => synchronous ||
                frame != null
            ? child
            : const SizedBox(
                width: 50,
                height: 50,
                child:
                    Center(child: CircularProgressIndicator(strokeWidth: 2))),
      );
}
