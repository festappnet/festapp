import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/components/_shared/common_strings.dart';

part 'brand_loading_paths.dart';

/// Product-level loading. Small action spinners keep their existing controls.
/// Other tenants retain their own brand and the normal progress indicator.
class BrandLoadingIndicator extends StatefulWidget {
  final double width;

  const BrandLoadingIndicator({super.key, this.width = 240});

  @override
  State<BrandLoadingIndicator> createState() => _BrandLoadingIndicatorState();
}

class _BrandLoadingIndicatorState extends State<BrandLoadingIndicator>
    with SingleTickerProviderStateMixin {
  bool _pulsing = false;
  late final _controller = AnimationController(
    vsync: this,
    duration: _brandCycle,
  )..addStatusListener(_onStatus);

  void _onStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || _pulsing) return;
    setState(() => _pulsing = true);
    _controller.repeat(period: _brandPulseCycle, min: 0, max: 1);
  }

  void _animate() {
    if (_controller.isAnimating) return;
    if (_pulsing) {
      _controller.repeat(period: _brandPulseCycle);
    } else {
      _controller.forward();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppConfig.loadingStyle != 'vstupenky-outline' ||
        MediaQuery.disableAnimationsOf(context) ||
        !TickerMode.valuesOf(context).enabled) {
      _controller.stop();
    } else {
      _animate();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (AppConfig.loadingStyle != 'vstupenky-outline') {
      return const CircularProgressIndicator();
    }
    return Semantics(
      label: CommonStrings.loading,
      child: ExcludeSemantics(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: widget.width,
            maxHeight: widget.width / _brandViewBox.size.aspectRatio,
          ),
          child: AspectRatio(
            aspectRatio: _brandViewBox.size.aspectRatio,
            child: CustomPaint(
              painter: _BrandLoadingPainter(
                animation: _controller,
                pulsing: _pulsing,
                reducedMotion: MediaQuery.disableAnimationsOf(context),
                ink: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xffffffff)
                    : const Color(0xff19243b),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LogoPart {
  final List<_StrokePath> strokes;
  late final Path path = _mergePaths();
  final bool blue;
  final double drawStart;
  final double drawEnd;
  final List<Offset> fill;
  final List<Offset> outline;
  _LogoPart({
    required List<Path> paths,
    required this.blue,
    required this.drawStart,
    required this.drawEnd,
    required this.fill,
    required this.outline,
  }) : strokes = paths.map(_StrokePath.new).toList();

  Path _mergePaths() {
    final result = Path();
    for (final stroke in strokes) {
      result.addPath(stroke.path, Offset.zero);
    }
    return result;
  }
}

class _StrokePath {
  final Path path;
  late final List<ui.PathMetric> metrics = path.computeMetrics().toList();
  late final double length = metrics.fold<double>(
    0,
    (sum, metric) => sum + metric.length,
  );
  _StrokePath(this.path);
}

class _BrandLoadingPainter extends CustomPainter {
  final Animation<double> animation;
  final bool pulsing;
  final bool reducedMotion;
  final Color ink;

  _BrandLoadingPainter({
    required this.animation,
    required this.pulsing,
    required this.reducedMotion,
    required this.ink,
  }) : super(repaint: animation);

  static double _opacity(List<Offset> stops, double phase) {
    for (var i = 1; i < stops.length; i++) {
      if (phase <= stops[i].dx) {
        final a = stops[i - 1];
        final b = stops[i];
        return a.dy + (b.dy - a.dy) * (phase - a.dx) / (b.dx - a.dx);
      }
    }
    return stops.last.dy;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final scale = math.min(
      size.width / _brandViewBox.width,
      size.height / _brandViewBox.height,
    );
    canvas.save();
    canvas.translate(
      (size.width - _brandViewBox.width * scale) / 2,
      (size.height - _brandViewBox.height * scale) / 2,
    );
    canvas.scale(scale);
    canvas.translate(-_brandViewBox.left, -_brandViewBox.top);
    final phase = pulsing ? 1.0 : animation.value;
    final pulseProgress = animation.value < 0.5
        ? animation.value * 2
        : (1 - animation.value) * 2;
    final pulseOpacity = pulsing && !reducedMotion
        ? 1 -
              (1 - _brandPulseMinOpacity) *
                  Curves.easeInOut.transform(pulseProgress)
        : 1.0;
    for (final part in _brandLogoParts) {
      final color = part.blue ? const Color(0xff80bdf2) : ink;
      final opacity =
          (reducedMotion ? 1.0 : _opacity(part.fill, phase)) * pulseOpacity;
      if (opacity > 0) {
        canvas.drawPath(
          part.path,
          Paint()..color = color.withValues(alpha: opacity),
        );
      }
    }
    if (!reducedMotion) {
      for (final part in _brandLogoParts) {
        final opacity = _opacity(part.outline, phase);
        if (opacity <= 0) continue;
        final progress =
            ((phase - part.drawStart) / (part.drawEnd - part.drawStart)).clamp(
              0.0,
              1.0,
            );
        if (progress <= 0) continue;
        final contour = Path();
        // SVG dash offset restarts on each contour using the compound path's
        // normalized length. Keep Flutter and browser stroke behavior aligned.
        for (final stroke in part.strokes) {
          for (final metric in stroke.metrics) {
            contour.addPath(
              metric.extractPath(
                0,
                math.min(metric.length, stroke.length * progress),
              ),
              Offset.zero,
            );
          }
        }
        canvas.drawPath(
          contour,
          Paint()
            ..color = (part.blue ? const Color(0xff80bdf2) : ink).withValues(
              alpha: opacity,
            )
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.25 / scale
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BrandLoadingPainter oldDelegate) =>
      oldDelegate.animation != animation ||
      oldDelegate.pulsing != pulsing ||
      oldDelegate.reducedMotion != reducedMotion ||
      oldDelegate.ink != ink;
}
