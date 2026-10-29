import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:fstapp/app_config.dart';

/// Startup motion belongs to the selected tenant, not the Festapp platform.
class BrandLoadingIndicator extends StatefulWidget {
  const BrandLoadingIndicator({super.key});

  @override
  State<BrandLoadingIndicator> createState() => _BrandLoadingIndicatorState();
}

class _BrandLoadingIndicatorState extends State<BrandLoadingIndicator>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppConfig.loadingSymbolAsset.isEmpty ||
        MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (AppConfig.loadingSymbolAsset.isEmpty) {
      return const CircularProgressIndicator();
    }
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final color = Theme.of(context).colorScheme.primary;
    return Semantics(
      label: AppConfig.appName,
      liveRegion: true,
      child: ExcludeSemantics(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => SizedBox(
            height: 48,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (index) {
                final wave = reduceMotion
                    ? 0.0
                    : math.sin((_controller.value - index * .1125) * math.pi * 2);
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Transform.translate(
                    offset: Offset(0, wave * 5),
                    child: Transform.rotate(
                      angle: wave * .08,
                      child: Opacity(
                        opacity: reduceMotion ? 1 : .7 - wave * .3,
                        child: SvgPicture.asset(
                          AppConfig.loadingSymbolAsset,
                          width: 48,
                          height: 28,
                          colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}
