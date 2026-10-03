import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/occasion/occasion_navigation_bar.dart';
import 'package:fstapp/theme_config.dart';
import 'package:fstapp/components/_shared/app_panel_helper.dart';
import 'package:fstapp/components/single_data_grid/admin_page_helper.dart';
import 'package:fstapp/widgets/buttons_helper.dart';

const destinations = [
  NavigationDestination(icon: Icon(Icons.calendar_month), label: 'Program'),
  NavigationDestination(icon: Icon(Icons.map), label: 'Mapa'),
  NavigationDestination(
    icon: Badge(label: Text('99+'), child: Icon(Icons.notifications)),
    label: 'Novinky',
  ),
  NavigationDestination(icon: Icon(Icons.info), label: 'Více'),
  NavigationDestination(icon: Icon(Icons.search), label: 'Vyhledávání'),
];

void main() {
  for (final dark in [false, true]) {
    for (final width in [320.0, 1280.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
            'navigation and actions: dark=$dark width=$width scale=$scale',
            (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(width, 900);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final light = ThemeConfig.theme();
          var active = 0;
          final taps = <int>[];
          await tester.pumpWidget(MaterialApp(
            theme:
                dark ? ThemeConfig.theme(brightness: Brightness.dark) : light,
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(width, 900),
                textScaler: TextScaler.linear(scale),
                padding: const EdgeInsets.only(bottom: 24),
              ),
              child: StatefulBuilder(builder: (context, setState) {
                return Scaffold(
                  appBar: AppBar(title: const Text('Český program')),
                  bottomNavigationBar: OccasionNavigationBar(
                    selectedIndex: active,
                    destinations: destinations,
                    onDestinationSelected: (index) {
                      taps.add(index);
                      // Search remains modal; all other taps reach the shell,
                      // including reselections of the retained map section.
                      if (index != 4) setState(() => active = index);
                    },
                  ),
                  body: ListView(children: [
                    TextField(
                        decoration: const InputDecoration(
                            labelText: 'Jméno účastníka')),
                    ButtonsHelper.primaryButton(
                      context: context,
                      width: 250,
                      label: 'Pokračovat k objednávce vstupenek',
                      onPressed: () {},
                    ),
                    ButtonsHelper.bigButton(
                      context: context,
                      label: 'Administrace události',
                      onPressed: () {},
                    ),
                    ButtonsHelper.actionButton(
                      context: context,
                      label: 'Přihlásit se na tuto událost',
                      icon: Icons.login,
                      onPressed: () {},
                    ),
                    const SizedBox(key: Key('content-end'), height: 16),
                  ]),
                );
              }),
            ),
          ));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.drag(find.byType(ListView), const Offset(0, -1000));
          await tester.pumpAndSettle();
          expect(
              tester.getRect(find.byKey(const Key('content-end'))).bottom,
              lessThanOrEqualTo(
                  tester.getRect(find.byType(NavigationBar)).top));
          expect(find.text('99+'), findsOneWidget);

          await tester.tap(find.text('Mapa'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Mapa'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Vyhledávání'));
          await tester.pumpAndSettle();
          expect(taps, [1, 1, 4]);
          expect(
              tester
                  .widget<NavigationBar>(find.byType(NavigationBar))
                  .selectedIndex,
              1);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  for (final dark in [false, true]) {
    for (final width in [320.0, 1280.0]) {
      testWidgets(
          'admin tabs keep contrast and grow with text: dark=$dark width=$width',
          (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 800);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final light = ThemeConfig.theme();
        final theme =
            dark ? ThemeConfig.theme(brightness: Brightness.dark) : light;
        await tester.pumpWidget(MaterialApp(
          theme: theme,
          home: MediaQuery(
            data: MediaQueryData(
                size: Size(width, 800), textScaler: TextScaler.linear(2)),
            child: DefaultTabController(
              length: 2,
              child: Builder(builder: (context) {
                final appBar = AppPanelHelper.buildAdaptiveAdminAppBar(context,
                    activeTabs: [
                      AdminTabDefinition(
                          label: 'Účastníci',
                          icon: Icons.people,
                          widget: const SizedBox()),
                      AdminTabDefinition(
                          label: 'Objednávky vstupenek',
                          icon: Icons.confirmation_number,
                          widget: const SizedBox()),
                    ],
                    tabController: DefaultTabController.of(context)) as AppBar;
                // Exercise the production tab strip without unrelated tenant
                // pickers and authentication widgets in the toolbar.
                return Scaffold(appBar: AppBar(bottom: appBar.bottom));
              }),
            ),
          ),
        ));
        final tabs = tester.widget<TabBar>(find.byType(TabBar));
        expect(tester.getTopLeft(find.byType(TabBar)).dx, 0);
        expect(tester.getSize(find.byType(TabBar)).width, width);
        expect(tabs.labelColor, theme.appBarTheme.foregroundColor);
        expect(tabs.preferredSize.height, greaterThan(kTextTabBarHeight));
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
      'deep-linked modal suppresses its selected label and icon styling',
      (tester) async {
    final theme = ThemeConfig.theme();
    await tester.pumpWidget(MaterialApp(
      theme: theme,
      home: Scaffold(
        bottomNavigationBar: OccasionNavigationBar(
          selectedIndex: 4,
          destinations: destinations,
          suppressSelection: true,
          onDestinationSelected: (_) {},
        ),
      ),
    ));
    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.indicatorColor, Colors.transparent);
    expect(bar.labelTextStyle!.resolve({WidgetState.selected})!.color,
        theme.navigationBarTheme.labelTextStyle!.resolve({})!.color);
    final effective =
        NavigationBarTheme.of(tester.element(find.byType(NavigationBar)));
    expect(effective.iconTheme!.resolve({WidgetState.selected})!.color,
        theme.navigationBarTheme.iconTheme!.resolve({})!.color);
  });
}
