import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/icons/icons_strings.dart';
import 'package:fstapp/components/icons/place_type_model.dart';
import 'package:fstapp/components/features/feature_constants.dart';
import 'package:fstapp/components/map/icon_model.dart';
import 'package:fstapp/components/map/map_place_model.dart';
import 'package:fstapp/components/map/map_page_helper.dart';
import 'package:fstapp/components/map/map_location_pin_helper.dart';
import 'package:fstapp/components/map/map_scene.dart';
import 'package:fstapp/components/map/path_group_model.dart';
import 'package:fstapp/components/map/path_node.dart';
import 'package:fstapp/components/map/place_model.dart';
import 'package:fstapp/components/schedule/event_model.dart';
import 'package:latlong2/latlong.dart';

/// The place-type filter bar shown at the bottom of the map: one chip per
/// visible place type plus a trailing "Other" chip, single-select.
void main() {
  const otherCode = "__other__";

  final placeTypes = [
    PlaceTypeModel(id: 1, code: "ubytovani", title: "Ubytování", icon: 171),
    PlaceTypeModel(id: 2, code: "hl_prog", title: "Hlavní programy", icon: 180),
    PlaceTypeModel(id: 3, code: "dieceze", title: "Diecézní", icon: 999),
  ];

  final icons = [
    // A valid SVG so the icon chip exercises the SvgPicture.string path.
    IconModel(
      id: 171,
      data:
          '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"><rect width="10" height="10"/></svg>',
    ),
    IconModel(
      id: 180,
      data:
          '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"><circle cx="5" cy="5" r="5"/></svg>',
    ),
    // A matching legacy row without SVG still falls back to a generic pin.
    IconModel(id: 999),
  ];

  Future<void> pumpBar(
    WidgetTester tester, {
    required List<PlaceTypeModel> types,
    String? selectedCode,
    required void Function(String? code) onTap,
    bool showOther = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Builder(
                builder: (context) => MapPageHelper.buildPlaceTypeFilterBar(
                  context,
                  types,
                  selectedCode,
                  otherCode,
                  onTap,
                  icons,
                  showOther: showOther,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('empty place types renders nothing (no pill)', (tester) async {
    await pumpBar(tester, types: const [], selectedCode: null, onTap: (_) {});
    expect(find.byType(Tooltip), findsNothing);
  });

  testWidgets('renders one chip per type plus a trailing Other chip',
      (tester) async {
    await pumpBar(tester,
        types: placeTypes, selectedCode: "ubytovani", onTap: (_) {});

    // 3 type chips + 1 "Other" chip.
    expect(find.byType(Tooltip), findsNWidgets(placeTypes.length + 1));
    // Other chip uses the more-horiz glyph.
    expect(find.byIcon(Icons.more_horiz), findsOneWidget);
    // The type with an unknown icon id falls back to the generic pin.
    expect(find.byIcon(Icons.place), findsOneWidget);
  });

  testWidgets('hides Other chip when it has no visible places', (tester) async {
    await pumpBar(
      tester,
      types: placeTypes,
      selectedCode: "ubytovani",
      showOther: false,
      onTap: (_) {},
    );

    expect(find.byIcon(Icons.more_horiz), findsNothing);
    expect(find.byType(Tooltip), findsNWidgets(placeTypes.length));
  });

  test('Other availability ignores hidden places', () {
    MapPlacePresentation marker({required String? type, bool hidden = false}) {
      final place = MapPlaceModel(
        id: 1,
        title: 'Place',
        type: type,
        latLng: const LatLng(49.82, 18.26),
        isHidden: hidden,
      );
      return MapPlacePresentation(
        place: place,
        coordinate: place.latLng,
        pinColorValue: Colors.blue.toARGB32(),
      );
    }

    expect(
      MapPageHelper.hasOtherVisiblePlaces(
        [marker(type: null, hidden: true)],
        placeTypes,
      ),
      isFalse,
    );
    expect(
      MapPageHelper.hasOtherVisiblePlaces(
        [marker(type: 'unlisted')],
        placeTypes,
      ),
      isTrue,
    );
    expect(
      MapPageHelper.hasOtherVisiblePlaces(
        [marker(type: 'ubytovani')],
        placeTypes,
      ),
      isFalse,
    );
  });

  testWidgets('place type names are not permanently shown in the compact bar',
      (tester) async {
    await pumpBar(tester,
        types: placeTypes, selectedCode: "ubytovani", onTap: (_) {});

    expect(find.text("Ubytování"), findsNothing);
    expect(find.text("Hlavní programy"), findsNothing);
    expect(find.text(IconsStrings.placeTypesOther), findsNothing);
  });

  testWidgets('selection feedback briefly shows the selected type name',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Builder(
                builder: (context) =>
                    MapPageHelper.buildPlaceTypeSelectionFeedback(
                  context,
                  "Hlavní programy",
                ),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text("Hlavní programy"), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is IgnorePointer && widget.ignoring,
      ),
      findsOneWidget,
    );
  });

  testWidgets('tapping a type chip reports that type code', (tester) async {
    String? tapped;
    await pumpBar(tester,
        types: placeTypes, selectedCode: "ubytovani", onTap: (c) => tapped = c);

    await tester.tap(find.byTooltip("Hlavní programy"));
    expect(tapped, "hl_prog");
  });

  testWidgets('tapping the Other chip reports the other-bucket code',
      (tester) async {
    String? tapped;
    await pumpBar(tester,
        types: placeTypes, selectedCode: "ubytovani", onTap: (c) => tapped = c);

    // Untranslated in the test env, the tooltip is the raw key.
    await tester.tap(find.byTooltip(IconsStrings.placeTypesOther));
    expect(tapped, otherCode);
  });

  testWidgets('selected chip is highlighted while others are transparent',
      (tester) async {
    await pumpBar(tester,
        types: placeTypes, selectedCode: "hl_prog", onTap: (_) {});

    Color? chipColor(String tooltip) {
      final container = tester.widget<Container>(
        find.descendant(
          of: find.byTooltip(tooltip),
          matching: find.byType(Container),
        ),
      );
      return (container.decoration as BoxDecoration).color;
    }

    // Selected chip has a visible (non-transparent) fill; an unselected one is transparent.
    expect(chipColor("Hlavní programy"), isNot(Colors.transparent));
    expect(chipColor("Ubytování"), Colors.transparent);
  });

  test('group paths stay semantic before direction-marker layout', () async {
    final places = [
      PlaceModel(
        id: 1,
        title: 'Start',
        latLng: {'lat': 49.82, 'lng': 18.26},
      ),
      PlaceModel(
        id: 2,
        title: 'End',
        latLng: {'lat': 49.8205, 'lng': 18.2605},
      ),
    ];
    final groups = [
      PathGroupsModel(
        id: 7,
        color: '#ff3366',
        pathData: [
          [PathNode.place(1), PathNode.place(2)],
        ],
      ),
    ];

    final paths = await MapPageHelper.loadGroupPaths(places, groups);

    expect(paths.keys, [7]);
    expect(paths[7], hasLength(1));
    expect(paths[7]!.first.kind, MapPathKind.main);
    expect(paths[7]!.first.points, hasLength(2));
    expect(paths[7]!.first.colorValue, const Color(0xffff3366).toARGB32());
    expect(paths[7]!.every((path) => path.kind == MapPathKind.main), isTrue);
  });

  test('place popup requires meaningful HTML content', () {
    expect(MapPageHelper.hasMeaningfulPlaceDescription(null), isFalse);
    expect(MapPageHelper.hasMeaningfulPlaceDescription(''), isFalse);
    expect(
      MapPageHelper.hasMeaningfulPlaceDescription('<p><br></p>'),
      isFalse,
    );
    expect(
      MapPageHelper.hasMeaningfulPlaceDescription('<p>Stage details</p>'),
      isTrue,
    );
    expect(
      MapPageHelper.hasMeaningfulPlaceDescription('<p><img src="map.jpg"></p>'),
      isTrue,
    );
  });

  test('place popup includes nested program levels', () {
    final place = PlaceModel(id: 7, title: 'Stage');
    EventModel event(
      int id,
      String title, {
      List<int>? children,
      bool hidden = false,
      Map<String, dynamic>? data,
    }) =>
        EventModel(
          id: id,
          title: title,
          place: PlaceModel(id: 7, title: 'Stage'),
          startTime: DateTime(2026, 8, 7, 10, id),
          endTime: DateTime(2026, 8, 7, 11, id),
          childEventIds: children,
          isHidden: hidden,
          data: data,
        );
    final events = [
      event(1, 'Parent', children: [2]),
      event(2, 'Child', children: [3]),
      event(3, 'Grandchild'),
      event(4, 'Hidden', hidden: true),
      event(5, 'Counseling slot',
          data: {FeatureConstants.isCounselingSlot: true}),
      EventModel(
        id: 6,
        title: 'Later counseling slot',
        place: PlaceModel(id: 7, title: 'Stage'),
        startTime: DateTime(2026, 8, 7, 14),
        endTime: DateTime(2026, 8, 7, 15),
        data: {FeatureConstants.isCounselingSlot: true},
      ),
      EventModel(
        id: 7,
        title: 'Next-day counseling slot',
        place: PlaceModel(id: 7, title: 'Stage'),
        startTime: DateTime(2026, 8, 8, 9),
        endTime: DateTime(2026, 8, 8, 10),
        data: {FeatureConstants.isCounselingSlot: true},
      ),
      EventModel(
        id: 8,
        title: 'Friday counseling entry',
        startTime: DateTime(2026, 8, 7, 9),
        endTime: DateTime(2026, 8, 7, 9, 30),
        data: {FeatureConstants.counselingEntry: true},
      ),
      EventModel(
        id: 9,
        title: 'Saturday counseling entry',
        startTime: DateTime(2026, 8, 8, 8),
        endTime: DateTime(2026, 8, 8, 8, 30),
        data: {FeatureConstants.counselingEntry: true},
      ),
    ];

    final counseling = MapPageHelper.assignEventsToPlaces([place], events);

    expect(place.events.map((event) => event.title),
        ['Parent', 'Child', 'Grandchild']);
    expect(counseling[7], hasLength(2));
    expect(counseling[7]!.first.start, DateTime(2026, 8, 7, 10, 5));
    expect(counseling[7]!.first.end, DateTime(2026, 8, 7, 15));
    expect(counseling[7]!.first.entryEventId, 8);
    expect(counseling[7]!.last.start, DateTime(2026, 8, 8, 9));
    expect(counseling[7]!.last.end, DateTime(2026, 8, 8, 10));
    expect(counseling[7]!.last.entryEventId, 9);
  });

  test('place navigation uses the platform map protocol', () {
    final android = MapPageHelper.navigationUri(
      latitude: 49.8209,
      longitude: 18.2625,
      label: 'Main stage',
      isWeb: false,
      platform: TargetPlatform.android,
    );
    final ios = MapPageHelper.navigationUri(
      latitude: 49.8209,
      longitude: 18.2625,
      label: 'Main stage',
      isWeb: false,
      platform: TargetPlatform.iOS,
    );
    final web = MapPageHelper.navigationUri(
      latitude: 49.8209,
      longitude: 18.2625,
      label: 'Main stage',
      isWeb: true,
      platform: TargetPlatform.android,
    );

    expect(android.scheme, 'geo');
    expect(android.queryParameters['q'], '49.8209,18.2625 (Main stage)');
    expect(ios.host, 'maps.apple.com');
    expect(ios.queryParameters['daddr'], '49.8209,18.2625');
    expect(web.host, 'mapy.com');
    expect(web.queryParameters['id'], '18.2625,49.8209');
  });

  test('compact pins are exactly the places without a resolvable icon', () {
    expect(
      MapLocationPinHelper.hasCustomIcon(
        MapPlaceModel(
          id: 1,
          title: 'No icon',
          latLng: const LatLng(49.82, 18.26),
        ),
        icons,
      ),
      isFalse,
    );
    expect(
      MapLocationPinHelper.hasCustomIcon(
        MapPlaceModel(
          id: 2,
          title: 'Own icon',
          icon: 171,
          latLng: const LatLng(49.82, 18.26),
        ),
        icons,
      ),
      isTrue,
    );
    expect(
      MapLocationPinHelper.hasCustomIcon(
        MapPlaceModel(
          id: 3,
          title: 'Legacy icon without SVG',
          icon: 999,
          latLng: const LatLng(49.82, 18.26),
        ),
        icons,
      ),
      isFalse,
    );
  });
}
