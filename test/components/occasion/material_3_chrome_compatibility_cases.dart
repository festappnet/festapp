import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/occasion/occasion_navigation_bar.dart';
import 'package:fstapp/components/single_data_grid/data_grid_helper.dart';
import 'package:fstapp/theme_config.dart';

void main() {
  setUpAll(() async {
    final loader = FontLoader(ThemeConfig.fontFamily)
      ..addFont(rootBundle.load('fonts/Futura PT Book.ttf'));
    await loader.load();
  });
  testWidgets('occasion navigation retains the original size and selection',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: ThemeConfig.theme(),
        home: Scaffold(
          bottomNavigationBar: OccasionNavigationBar(
              selectedIndex: 0,
              onDestinationSelected: (_) {},
              destinations: const [
                NavigationDestination(
                    icon: Icon(Icons.calendar_month), label: 'Program'),
                NavigationDestination(icon: Icon(Icons.map), label: 'Mapa'),
              ]),
        )));
    expect(tester.getSize(find.byType(NavigationBar)).height,
        kBottomNavigationBarHeight);
    expect(
        NavigationBarTheme.of(tester.element(find.byType(NavigationBar)))
            .indicatorColor,
        Colors.transparent);
    expect(
        IconTheme.of(tester.element(find.byIcon(Icons.calendar_month))).color,
        ThemeConfig.seed2);
  });
  testWidgets('secondary tabs retain the previous typography and dimensions',
      (tester) async {
    Future<void> pump(ThemeData theme) async {
      await tester.pumpWidget(MaterialApp(
          theme: theme,
          home: DefaultTabController(
              length: 2,
              child: Scaffold(
                  body: Builder(
                      builder: (context) => Align(
                          alignment: Alignment.topLeft,
                          child: TabBar(isScrollable: true, tabs: [
                            DataGridHelper.buildTab(
                                context, Icons.place, 'Místa'),
                            DataGridHelper.buildTab(
                                context, Icons.timeline, 'Cesty')
                          ])))))));
      await tester.pumpAndSettle();
    }

    await pump(
        ThemeData(useMaterial3: false, fontFamily: ThemeConfig.fontFamily));
    final previousLabel = tester.getSize(find.text('Místa'));
    final previousBar = tester.getSize(find.byType(TabBar));
    await pump(ThemeConfig.theme());
    expect(tester.getSize(find.text('Místa')), previousLabel);
    expect(tester.getSize(find.byType(TabBar)).height, previousBar.height);
  });
}
