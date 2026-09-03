import 'dart:ui' as ui;

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:fstapp/components/map/map_place_model.dart';
import 'package:fstapp/components/map/icon_model.dart';
import 'package:fstapp/theme_config.dart';

class MapLocationPinHelper {
  static String? resolveIconData(
    MapPlaceModel place,
    List<IconModel> source,
  ) {
    if (place.icon != null) {
      final data = source
          .firstWhereOrNull((icon) => icon.id == place.icon)
          ?.renderableSvgData;
      if (data != null) return data;
    }
    if (place.type != null) {
      return source
          .firstWhereOrNull((icon) => icon.normalizedLink == place.type)
          ?.renderableSvgData;
    }
    return null;
  }

  static bool hasCustomIcon(MapPlaceModel place, List<IconModel> source) =>
      resolveIconData(place, source) != null;

  static Widget? type2icon(
      BuildContext context, MapPlaceModel placeType, List<IconModel> source,
      {Color? pinColor}) {
    SvgPicture? fill;

    final iconData = resolveIconData(placeType, source);
    if (iconData != null) {
      fill = SvgPicture.string(
        iconData,
        colorFilter: const ColorFilter.mode(Colors.black, BlendMode.srcIn),
        errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
      );
      return _locationPin(context, fill,
          top: 7.5,
          left: 14.5,
          iconTop: 12,
          iconLeft: 19,
          iconWidth: 19,
          iconHeight: 19,
          pinColor: pinColor);
    }

    return null;
  }

  static Widget rasterIcon(
    BuildContext context,
    ui.Image image, {
    required Color pinColor,
  }) =>
      _locationPin(
        context,
        RawImage(
          image: image,
          fit: BoxFit.contain,
          color: Colors.black,
          colorBlendMode: BlendMode.srcIn,
        ),
        top: 7.5,
        left: 14.5,
        iconTop: 12,
        iconLeft: 19,
        iconWidth: 19,
        iconHeight: 19,
        pinColor: pinColor,
      );

  static Stack _locationPin(BuildContext context, Widget fill,
      {required double top,
      required double left,
      required double iconTop,
      required double iconLeft,
      required double iconWidth,
      required double iconHeight,
      Color? pinColor}) {
    return Stack(
      children: [
        Icon(Icons.location_pin,
            size: 58, color: pinColor ?? ThemeConfig.mapPinColor(context)),
        Positioned(
          top: top,
          left: left,
          child: Container(
            width: 29.0,
            height: 29.0,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
        ),
        Positioned(
          top: iconTop,
          left: iconLeft,
          width: iconWidth,
          height: iconHeight,
          child: Container(alignment: Alignment.center, child: fill),
        ),
      ],
    );
  }
}
