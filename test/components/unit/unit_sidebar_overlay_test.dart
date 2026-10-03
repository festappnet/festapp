import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/app_router.gr.dart';
import 'package:fstapp/components/navigation/routed_tab_scaffold.dart';
import 'package:fstapp/components/unit/views/unit_admin_page.dart';

void main() {
  testWidgets('hovering the sidebar overlays content without resizing it', (
    tester,
  ) async {
    const contentKey = Key('unit-content');
    await tester.pumpWidget(
      MaterialApp(
        home: DefaultTabController(
          length: 2,
          child: Builder(
            builder: (context) => Scaffold(
              body: UnitAdministrationBody(
                controller: DefaultTabController.of(context),
                tabs: const [
                  RoutedTabDefinition(
                    slug: 'occasions',
                    route: UnitOccasionsRoute(),
                    label: 'Events',
                    icon: Icons.calendar_month,
                  ),
                  RoutedTabDefinition(
                    slug: 'users',
                    route: UnitUsersRoute(),
                    label: 'Users',
                    icon: Icons.people,
                  ),
                ],
                child: const ColoredBox(key: contentKey, color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
    final initialBounds = tester.getRect(find.byKey(contentKey));
    expect(initialBounds.left, SideMenu.collapsedWidth);
    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer(location: const Offset(400, 300));
    await pointer.moveTo(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(SideMenu)).width, SideMenu.expandedWidth);
    expect(tester.getRect(find.byKey(contentKey)), initialBounds);
    await tester.tap(find.text('Users'));
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(UnitAdministrationBody));
    expect(DefaultTabController.of(context).index, 1);
    await pointer.moveTo(const Offset(400, 300));
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byType(SideMenu)).width,
      SideMenu.collapsedWidth,
    );
    expect(tester.getRect(find.byKey(contentKey)), initialBounds);
    await pointer.removePointer();
  });
}
