// Offline visual smoke harness using production widgets and a mocked backend.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:fstapp/components/_shared/app_panel_helper.dart';
import 'package:fstapp/components/single_data_grid/admin_page_helper.dart';
import 'package:fstapp/components/occasion/occasion_navigation_bar.dart';
import 'package:fstapp/components/occasion/occasion_link_model.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/components/schedule/event_model.dart';
import 'package:fstapp/components/schedule/event_page.dart';
import 'package:fstapp/components/users/user_info_model.dart';
import 'package:fstapp/components/users/views/user_page.dart';
import 'package:fstapp/components/news/news_form_page.dart';
import 'package:fstapp/components/timeline/advanced_timeline_day_list.dart';
import 'package:fstapp/components/timeline/advanced_timeline_controller.dart';
import 'package:fstapp/components/timeline/schedule_helper.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/data_services/offline_data_service.dart';
import 'package:fstapp/services/connectivity_service.dart';
import 'package:fstapp/theme_config.dart';
import 'package:fstapp/services/web_bootstrap_bridge.dart';

late String fixtureSession;

final event = EventModel(
    id: 1,
    occasionId: 1,
    title: 'Česká přednáška o společném programu',
    description:
        '<p>Podrobný popis události s českými znaky. Přijďte se potkat a vyzkoušet společný program.</p>',
    startTime: DateTime(2026, 10, 3, 14),
    endTime: DateTime(2026, 10, 3, 15));

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  WidgetsBinding.instance.ensureSemantics();
  await EasyLocalization.ensureInitialized();
  tzdata.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation('Europe/Prague'));
  await Supabase.initialize(
      url: 'https://example.test',
      publishableKey: 'fixture-key',
      authOptions: const FlutterAuthClientOptions(
          persistSession: false,
          autoRefreshToken: false,
          detectSessionInUri: false),
      httpClient: MockClient((request) async {
        debugPrint('Fixture request: ${request.url.path}');
        return http.Response(
            jsonEncode(request.url.path.contains('/rpc/') ? {'data': []} : []),
            200,
            headers: {'content-type': 'application/json'},
            request: request);
      }));
  final expiry =
      DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
          1000;
  final payload = base64Url
      .encode(utf8.encode(jsonEncode({'exp': expiry, 'sub': 'fixture-user'})))
      .replaceAll('=', '');
  fixtureSession = jsonEncode({
    'access_token': 'eyJhbGciOiJIUzI1NiJ9.$payload.fixture',
    'refresh_token': 'fixture',
    'token_type': 'bearer',
    'expires_in': 3600,
    'expires_at': expiry,
    'user': {
      'id': 'fixture-user',
      'aud': 'authenticated',
      'email': 'ucastnik@example.test',
      'created_at': '2026-10-03T00:00:00Z',
      'app_metadata': {},
      'user_metadata': {}
    }
  });
  await Supabase.instance.client.auth.recoverSession(fixtureSession);
  RightsService.currentLink = 'fixture';
  RightsService.useOfflineVersion = true;
  ConnectivityService.isOfflineNotifier.value = true;
  RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
      code: 200,
      occasion: OccasionModel(
          id: 1,
          isOpen: true,
          isHidden: false,
          isPromoted: false,
          link: 'fixture',
          title: 'Česká událost'),
      userInfo: UserInfoModel(
          id: 'fixture-user',
          name: 'Žofie',
          surname: 'Česká',
          email: 'ucastnik@example.test',
          phone: '+420 123 456 789',
          companions: []));
  await OfflineDataService.saveAllEvents([event]);
  final cached = await OfflineDataService.getAllEvents();
  debugPrint('Fixture cached event count: ${cached.length}');
  if (cached.isEmpty) throw StateError('Fixture event did not round-trip');
  runApp(EasyLocalization(
      supportedLocales: const [Locale('cs')],
      path: 'assets/translations',
      startLocale: const Locale('cs'),
      fallbackLocale: const Locale('cs'),
      child: const FixtureApp()));
  WidgetsBinding.instance
      .addPostFrameCallback((_) => WebBootstrapBridge.markAppReady());
}

class FixtureApp extends StatefulWidget {
  const FixtureApp({super.key});
  @override
  State<FixtureApp> createState() => _FixtureAppState();
}

class _FixtureAppState extends State<FixtureApp> {
  bool dark = false;
  bool large = false;
  int page = 0;
  @override
  Widget build(BuildContext context) {
    final light = ThemeConfig.theme();
    return MaterialApp(
      locale: context.locale,
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      theme: light,
      darkTheme: ThemeConfig.theme(brightness: Brightness.dark),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      debugShowCheckedModeBanner: false,
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(large ? 2 : 1)),
          child: child!),
      home: Builder(
          builder: (context) => Scaffold(
                body: Column(children: [
                  Wrap(children: [
                    TextButton(
                        onPressed: () => setState(() => dark = !dark),
                        child: Text(dark ? 'Světlý režim' : 'Tmavý režim')),
                    TextButton(
                        onPressed: () => setState(() => large = !large),
                        child: Text(large ? 'Písmo 100 %' : 'Písmo 200 %')),
                  ]),
                  Expanded(
                      child: switch (page) {
                    0 => DayList(
                        dayGroup: TimeBlockGroup(
                            title: 'Odpoledne',
                            events: [TimeBlockItem.fromEventModel(event)]),
                        controller: AdvancedTimelineController(
                            events: [TimeBlockItem.fromEventModel(event)]),
                        openId: 1,
                        onToggle: (_) {}),
                    1 => EventPage(id: 1),
                    2 => const UserPage(),
                    3 => NewsFormPage(
                        editorOverride: const TextField(
                            maxLines: 4,
                            decoration:
                                InputDecoration(labelText: 'Obsah oznámení')),
                        onSubmit: (_) async {}),
                    _ => DefaultTabController(
                        length: 2,
                        child: Builder(
                            builder: (ctx) => Scaffold(
                                appBar: AppBar(
                                  title: const Text('Správa události'),
                                  // Render the production tab chrome without
                                  // tenant breadcrumbs requiring AutoRoute.
                                  bottom:
                                      (AppPanelHelper.buildAdaptiveAdminAppBar(
                                              ctx,
                                              activeTabs: [
                                                AdminTabDefinition(
                                                    label: 'Účastníci',
                                                    icon: Icons.people,
                                                    widget: const SizedBox()),
                                                AdminTabDefinition(
                                                    label:
                                                        'Objednávky vstupenek',
                                                    icon: Icons
                                                        .confirmation_number,
                                                    widget: const SizedBox()),
                                              ],
                                              tabController:
                                                  DefaultTabController.of(
                                                      ctx)) as AppBar)
                                          .bottom,
                                ),
                                body: const TabBarView(children: [
                                  ListTile(
                                      title: Text('Žofie Česká'),
                                      subtitle: Text('ucastnik@example.test')),
                                  ListTile(
                                      title: Text('Objednávka vstupenek'),
                                      subtitle: Text('Potvrzeno')),
                                ]))))
                  }),
                ]),
                bottomNavigationBar: OccasionNavigationBar(
                    selectedIndex: page,
                    onDestinationSelected: (index) async {
                      // Event detail is anonymous; the profile uses a fake
                      // local session. Both use only cached or mocked data.
                      if (index == 1) {
                        await Supabase.instance.client.auth
                            .signOut(scope: SignOutScope.local);
                      } else if (Supabase.instance.client.auth.currentSession ==
                          null) {
                        await Supabase.instance.client.auth
                            .recoverSession(fixtureSession);
                      }
                      if (mounted) setState(() => page = index);
                    },
                    destinations: const [
                      NavigationDestination(
                          icon: Icon(Icons.calendar_month), label: 'Program'),
                      NavigationDestination(
                          icon: Icon(Icons.event), label: 'Detail'),
                      NavigationDestination(
                          icon: Icon(Icons.person), label: 'Profil'),
                      NavigationDestination(
                          icon: Icon(Icons.edit), label: 'Formulář'),
                      NavigationDestination(
                          icon: Icon(Icons.settings), label: 'Správa'),
                    ]),
              )),
    );
  }
}
