import 'package:flutter/material.dart';
import 'package:collection/collection.dart';
import 'package:fstapp/components/map/map_scene.dart';
import 'package:fstapp/components/map/place_model.dart';
import 'package:fstapp/components/schedule/event_model.dart';
import 'package:fstapp/data_services/data_extensions.dart';
import 'package:fstapp/services/responsive_service.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:fstapp/components/map/path_group_model.dart';
import 'package:fstapp/components/map/icon_model.dart';
import 'package:fstapp/components/icons/place_type_model.dart';
import 'package:fstapp/components/icons/icons_strings.dart';
import 'package:fstapp/components/html/html_helper.dart';
import 'package:fstapp/theme_config.dart';

class CounselingHoursRange {
  final DateTime start;
  final DateTime end;
  final int? entryEventId;

  const CounselingHoursRange({
    required this.start,
    required this.end,
    this.entryEventId,
  });
}

class MapPageHelper {
  static bool hasMeaningfulPlaceDescription(String? description) =>
      !HtmlHelper.isHtmlEmptyOrNull(description);

  static Map<int, List<CounselingHoursRange>> assignEventsToPlaces(
    List<PlaceModel> places,
    List<EventModel> events,
  ) {
    final publicEvents = events.filterNotHidden();
    final visibleEvents = publicEvents
        .where((event) => !event.isCounselingSlot)
        .toList()
        .sortEvents();
    final counselingByPlace = <int, List<CounselingHoursRange>>{};
    final counselingEntriesByDay = <DateTime, EventModel>{};
    for (final entry
        in publicEvents.where((event) => event.isCounselingEntry)) {
      counselingEntriesByDay.putIfAbsent(_eventDay(entry), () => entry);
    }
    for (final place in places) {
      place.events
        ..clear()
        ..addAll(visibleEvents.where((event) => event.place?.id == place.id));
      final placeId = place.id;
      if (placeId == null) continue;
      final slots = publicEvents.where(
        (event) => event.isCounselingSlot && event.place?.id == placeId,
      );
      final slotsByDay = <DateTime, List<EventModel>>{};
      for (final slot in slots) {
        final day = _eventDay(slot);
        slotsByDay.putIfAbsent(day, () => []).add(slot);
      }
      final ranges = slotsByDay.entries.map((entry) {
        final ordered = entry.value.sortEvents();
        final end = ordered
            .map((slot) => slot.endTime)
            .reduce((a, b) => a.isAfter(b) ? a : b);
        return CounselingHoursRange(
          start: ordered.first.startTime,
          end: end,
          entryEventId: counselingEntriesByDay[entry.key]?.id,
        );
      }).toList()
        ..sort((a, b) => a.start.compareTo(b.start));
      if (ranges.isNotEmpty) counselingByPlace[placeId] = ranges;
    }
    return counselingByPlace;
  }

  static DateTime _eventDay(EventModel event) {
    final start = event.startTime;
    return DateTime(start.year, start.month, start.day);
  }

  static Uri navigationUri({
    required double latitude,
    required double longitude,
    required String label,
    required bool isWeb,
    required TargetPlatform platform,
  }) {
    final coordinates = '$latitude,$longitude';
    if (!isWeb && platform == TargetPlatform.android) {
      return Uri(
        scheme: 'geo',
        path: coordinates,
        queryParameters: {'q': '$coordinates ($label)'},
      );
    }
    if (!isWeb && platform == TargetPlatform.iOS) {
      return Uri.https('maps.apple.com', '/', {
        'daddr': coordinates,
        'dirflg': 'w',
      });
    }
    return Uri.https('mapy.com', '/zakladni', {
      'source': 'coor',
      'id': '$longitude,$latitude',
      'x': '$longitude',
      'y': '$latitude',
      'z': '17',
    });
  }

  static Color _parsePathColor(String? value) {
    final hex = value?.replaceFirst('#', '');
    if (hex == null || (hex.length != 6 && hex.length != 8)) {
      return Colors.blue;
    }
    final normalized = hex.length == 6 ? 'ff$hex' : hex;
    final parsed = int.tryParse(normalized, radix: 16);
    return parsed == null ? Colors.blue : Color(parsed);
  }

  /// Build renderer-neutral line geometry per group.
  static Future<Map<int, List<MapPathPresentation>>> loadGroupPaths(
    List<PlaceModel> placesList,
    List<PathGroupsModel> groups,
  ) async {
    final Map<int, List<MapPathPresentation>> result = {};

    for (var g in groups) {
      if (g.isHidden == true || g.pathData == null) continue;
      final groupId = g.id;
      if (groupId == null) continue;

      final pathColor = _parsePathColor(g.color);
      final lines = <MapPathPresentation>[];

      MapPathPresentation path(
        List<LatLng> points,
        double strokeWidth,
        MapPathKind kind,
      ) =>
          MapPathPresentation(
            id: 'group_${groupId}_${lines.length}',
            groupId: groupId,
            points: points,
            colorValue: pathColor.toARGB32(),
            strokeWidth: strokeWidth,
            kind: kind,
          );

      for (var segment in g.pathData!) {
        // map segment (List<PathNode>) -> List<LatLng>: place refs are looked
        // up in placesList, free points use their inline coordinates.
        final pts = List<LatLng>.from(
          segment.map((node) => node.resolve(placesList)).whereType<LatLng>(),
        );
        if (pts.length < 2) continue;

        // main line
        lines.add(path(pts, 3, MapPathKind.main));
      }

      result[groupId] = lines;
    }

    return result;
  }

  /// Builds a responsive, rounded background "icon area" that is either
  /// a horizontal strip (mobile) or vertical column (tablet/desktop).
  static Widget buildGroupIconArea(
    BuildContext context,
    List<PathGroupsModel> groups,
    int? selectedGroupId,
    void Function(int) onTap,
    List<IconModel> icons, {
    ScrollController? scrollController,
  }) {
    if (groups.isEmpty) return const SizedBox.shrink();

    final bool isMobile = ResponsiveService.isMobile(context);
    final double itemWidth = 60; // same as in _buildIconColumn
    final double itemSpacing = 12; // horizontal margin*2

    // build children with index so we can scroll to i
    final children = List<Widget>.generate(groups.length, (i) {
      final g = groups[i];
      return _buildIconColumn(
        context,
        g,
        selectedGroupId,
        (id) {
          if (g.id == null) return;
          onTap(g.id!);

          // on mobile, animate the scroll so tapped icon is centered
          if (isMobile && scrollController != null) {
            final screenW = MediaQuery.of(context).size.width;
            final target =
                i * (itemWidth + itemSpacing) - (screenW - itemWidth) / 2;
            scrollController.animateTo(
              target.clamp(0.0, scrollController.position.maxScrollExtent),
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
            );
          }
        },
        icons,
      );
    });

    Widget strip = isMobile
        ? SingleChildScrollView(
            controller: scrollController,
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start, // icons stay at top
              children: children,
            ),
          )
        : SingleChildScrollView(
            controller: scrollController,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, // align left
              children: children,
            ),
          );

    return Positioned(
      top: 8,
      left: isMobile ? 8 : null,
      right: 8,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white70,
          borderRadius: BorderRadius.circular(12),
        ),
        child: strip,
      ),
    );
  }

  static Widget _buildIconColumn(
    BuildContext context,
    PathGroupsModel g,
    int? selectedGroupId,
    void Function(int) onTap,
    List<IconModel> icons,
  ) {
    final pathColor = g.color != null
        ? Color(int.parse(g.color!.replaceFirst('#', '0x')))
        : Colors.blue;
    final bool isSelected = g.id == selectedGroupId;
    final iconSvg =
        icons.firstWhereOrNull((i) => i.id == g.icon)?.renderableSvgData;

    Widget badge = (iconSvg != null)
        ? SvgPicture.string(
            iconSvg,
            width: 24,
            height: 24,
            errorBuilder: (context, error, stackTrace) =>
                Icon(Icons.route_outlined, size: 24, color: pathColor),
          )
        : Icon(Icons.route_outlined, size: 24, color: pathColor);

    return GestureDetector(
      onTap: () {
        if (g.id != null) onTap(g.id!);
      },
      child: Container(
        width: 60, // enough to fit icon + two lines
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Column(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? pathColor : Colors.grey.shade400,
                  width: 3,
                ),
              ),
              child: Center(child: badge),
            ),
            const SizedBox(height: 4),
            Text(
              g.title ?? '',
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.black,
                fontSize: 11,
                fontWeight: isSelected
                    ? FontWeight.bold
                    : FontWeight.normal, // bold when selected
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Bottom-center dark pill with one chip per visible place type and an
  /// optional trailing "Other" chip. Single-select: the caller filters the map
  /// markers to the tapped type (or the [otherCode] bucket) and re-fits the camera.
  /// Returns an empty box when there are no place types to show.
  static Widget buildPlaceTypeFilterBar(
    BuildContext context,
    List<PlaceTypeModel> placeTypes,
    String? selectedCode,
    String otherCode,
    void Function(String? code) onTap,
    List<IconModel> icons, {
    bool showOther = true,
  }) {
    if (placeTypes.isEmpty) return const SizedBox.shrink();

    final chips = <Widget>[
      for (final type in placeTypes)
        _buildPlaceTypeChip(
          code: type.code,
          iconWidget: _placeTypeIcon(type.icon, icons),
          isSelected: selectedCode == type.code,
          onTap: onTap,
          semanticLabel: type.title ?? '',
        ),
      if (showOther)
        _buildPlaceTypeChip(
          code: otherCode,
          iconWidget: const Icon(Icons.more_horiz,
              size: _chipIconSize, color: Colors.white),
          isSelected: selectedCode == otherCode,
          onTap: onTap,
          semanticLabel: IconsStrings.placeTypesOther,
        ),
    ];

    return Positioned(
      left: 0,
      right: 0,
      bottom: 16,
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width - 24,
            ),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: ThemeConfig.appBarColor(),
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 6,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: chips,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Whether the trailing "Other" chip has at least one visible map marker.
  static bool hasOtherVisiblePlaces(
    Iterable<MapPlacePresentation> places,
    Iterable<PlaceTypeModel> visiblePlaceTypes,
  ) {
    final visibleCodes = visiblePlaceTypes.map((type) => type.code).toSet();
    return places.any((marker) {
      final place = marker.place;
      return !place.isHidden &&
          (place.type == null || !visibleCodes.contains(place.type));
    });
  }

  static Widget _buildPlaceTypeChip({
    required String? code,
    required Widget iconWidget,
    required bool isSelected,
    required void Function(String? code) onTap,
    String? semanticLabel,
  }) {
    return Tooltip(
      message: semanticLabel ?? '',
      child: GestureDetector(
        onTap: () => onTap(code),
        child: Container(
          width: 34,
          height: 34,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: isSelected
                ? Colors.white.withValues(alpha: 0.22)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(child: iconWidget),
        ),
      ),
    );
  }

  /// Hard cap on a chip icon's rendered width AND height (dp). Icons vary wildly
  /// in viewBox aspect ratio (wide "bed", tall "church", square "badge"); a
  /// fixed box + BoxFit.contain keeps every one within the same footprint so
  /// none reads as oversized.
  static const double _chipIconSize = 18;

  /// White monochrome rendering of a place type's icon (from the loaded icon
  /// set), capped to [_chipIconSize] in both dimensions, falling back to a
  /// generic pin when no icon is configured.
  static Widget _placeTypeIcon(int? iconId, List<IconModel> icons) {
    final svg =
        icons.firstWhereOrNull((i) => i.id == iconId)?.renderableSvgData;
    if (svg == null) {
      return const Icon(Icons.place, size: _chipIconSize, color: Colors.white);
    }
    return SizedBox(
      width: _chipIconSize,
      height: _chipIconSize,
      child: SvgPicture.string(
        svg,
        fit: BoxFit.contain,
        colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
        errorBuilder: (context, error, stackTrace) =>
            const Icon(Icons.place, size: _chipIconSize, color: Colors.white),
      ),
    );
  }

  /// Brief confirmation shown above the compact place-type filter after a tap.
  static Widget buildPlaceTypeSelectionFeedback(
    BuildContext context,
    String? label,
  ) {
    if (label == null || label.isEmpty) return const SizedBox.shrink();

    return Positioned(
      left: 24,
      right: 24,
      bottom: 72,
      child: IgnorePointer(
        child: Center(
          child: Material(
            color: ThemeConfig.appBarColor(),
            borderRadius: BorderRadius.circular(12),
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Shows the selected path‑group’s title in a pill overlay with matching border.
  static Widget buildSelectedGroupTitle(
    BuildContext context,
    PathGroupsModel? selectedGroup,
  ) {
    if (ResponsiveService.isMobile(context) ||
        selectedGroup == null ||
        selectedGroup.title == null) {
      return const SizedBox.shrink();
    }
    final pathColor = selectedGroup.color != null
        ? Color(int.parse(selectedGroup.color!.replaceFirst('#', '0x')))
        : Colors.blue;

    return Positioned(
      top: 24,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: pathColor, width: 3),
          ),
          constraints: const BoxConstraints(maxWidth: 200),
          child: Text(
            selectedGroup.title!,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 17, fontWeight: FontWeight.bold, color: Colors.black),
          ),
        ),
      ),
    );
  }
}
