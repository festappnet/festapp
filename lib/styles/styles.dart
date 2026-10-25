import 'package:material_ui/material_ui.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:fstapp/styles/styles_config.dart';
import 'package:fstapp/theme_config.dart';
import 'package:simple_shadow/simple_shadow.dart';

class MainPageButton extends StatelessWidget {
  final VoidCallback onPressed;
  final Widget child;
  final EdgeInsets margin;
  Color? backgroundColor;

  MainPageButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.backgroundColor,
    this.margin = const EdgeInsets.symmetric(horizontal: 8.0),
  });

  @override
  Widget build(BuildContext context) {
    backgroundColor ??= ThemeConfig.seed2;
    return Container(
      margin: margin,
      child: ElevatedButton(
        onPressed: onPressed,
        style: StylesConfig.mainPageButtonStyle(context).copyWith(
          backgroundColor: WidgetStatePropertyAll(backgroundColor),
        ),
        child: child,
      ),
    );
  }
}

class CircularButton extends MainPageButton {
  final Size size;

  CircularButton({
    super.key,
    required super.onPressed,
    required super.child,
    super.backgroundColor,
    this.size = const Size(50, 50),
  });

  @override
  Widget build(BuildContext context) {
    backgroundColor ??= ThemeConfig.seed2;
    return Container(
      margin: margin,
      child: ElevatedButton(
        onPressed: onPressed,
        style: StylesConfig.mainPageButtonStyle(context).copyWith(
          backgroundColor: WidgetStateProperty.all(backgroundColor),
          shape: WidgetStateProperty.all(const CircleBorder()),
          minimumSize: WidgetStateProperty.all(size),
        ),
        child: child,
      ),
    );
  }
}

class SvgIconButton extends StatelessWidget {
  final VoidCallback onPressed;
  final String iconPath;
  final double splashRadius;
  final double iconSize;

  const SvgIconButton({
    super.key,
    required this.onPressed,
    required this.iconPath,
    this.splashRadius = 32,
    this.iconSize = 60,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      padding: const EdgeInsets.all(0),
      splashRadius: splashRadius,
      iconSize: iconSize,
      icon: SimpleShadow(
        opacity: 0.2,
        offset: const Offset(0, 2),
        //sigma: 10,
        child: SvgPicture.asset(
          iconPath,
        ),
      ),
      onPressed: onPressed,
    );
  }
}

//coffee
// static const primaryColor = 0xFF122640;
// static const backgroundColor = Color(0xFFFFFFFF);
// static const color1 = Color(primaryColor);
// static const color2 = Color(0xFFBF8641);
// static const color3 = Color(0xFF593E25);
// static const color4 = Color(0xFF1B3659);
// static const attentionColor = Color(0xFF8B0000);

//raven theme
// static const primaryColor = 0xFF1D2026;
// static const backgroundColor = Color(0xFFFFFFFF);
// static const color1 = Color(primaryColor);
// static const color2 = Color(0xFF5E6D8C);
// static const color3 = Color(0xFFBFBFBF);
// static const color4 = Color(0xFF2C3540);
// static const attentionColor = Color(0xFF8B0000);

//rock style
// static const primaryColor = 0xFF260101;
// static const backgroundColor = Color(0xFFFFFFFF);
// static const color1 = Color(primaryColor);
// static const color2 = Color(0xFFBF4904);
// static const color3 = Color(0xFFF29D52);
// static const color4 = Color(0xFF731702);
// static const attentionColor = Color(0xFF8B0000);

//galaxy
// static const primaryColor = 0xFF023059;
// static const backgroundColor = Color(0xFFFFFFFF);
// static const color1 = Color(primaryColor);
// static const color2 = Color(0xFF8C331F);
// static const color3 = Color(0xFFA65424);
// static const color4 = Color(0xFF26080D);
// static const attentionColor = Color(0xFF8B0000);

//coffee
// static const primaryColor = 0xFF261914;
// static const backgroundColor = Color(0xFFFFFFFF);
// static const color1 = Color(primaryColor);
// static const color2 = Color(0xFF735A4C);
// static const color3 = Color(0xFFA69485);
// static const color4 = Color(0xFF592C22);
// static const attentionColor = Color(0xFF8B0000);

// static const primaryColor = 0xFF261914;
// static const backgroundColor = Color(0xFFFFFFFF);
// static const color1 = Color(primaryColor);
// static const color2 = Color(0xFF692F00);
// static const color3 = Color(0xFF472705);
// static const color4 = Color(0xFF2B1000);
// static const attentionColor = Color(0xFF8B0000);

// static const primaryColor = 0xFF072026;
// static const backgroundColor = Color(0xFFFFFFFF);
// static const color1 = Color(primaryColor);
// static const color2 = Color(0xFF8C7E6C);
// static const color3 = Color(0xFFD9B79A);
// static const color4 = Color(0xFF2D3E40);
// static const attentionColor = Color(0xFF8B0000);
