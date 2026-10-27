// Isolated visual fixture of the real notification panel; no backend calls.
import 'package:material_ui/material_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:fstapp/components/notification_center/notification_center_controller.dart';
import 'package:fstapp/components/notification_center/notification_center_panel.dart';
import 'package:fstapp/services/web_bootstrap_bridge.dart';
import 'package:fstapp/theme_config.dart';
import 'package:fstapp/widgets/dependency_material_bridge.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized().ensureSemantics();
  await EasyLocalization.ensureInitialized();
  final controller = NotificationCenterController(
    read: (_, params) async => {},
  );
  controller.snapshot = 7;
  controller.previousReadThrough = 4;
  controller.items = [
    NotificationItem.fromJson({
      'id': 'synthetic-email',
      'kind': 'email_problem',
      'section': 0,
      'sequence': 5,
      'occurredAt': '2026-10-23T18:30:00',
      'data': {
        'messageId': 'synthetic-message',
        'recipient': 'zakaznik@example.invalid',
        'messageKind': 'order_confirmation',
        'reason': 'bounce',
      },
    }),
    for (final entry in [
      ['form_closed', '2026-10-26T12:00:00'],
      ['order_created', '2026-10-26T10:08:00'],
      ['waitlist_registered', '2026-10-26T09:42:00'],
    ])
      NotificationItem.fromJson({
        'id': entry[0],
        'kind': entry[0],
        'section': 1,
        'sequence': 6,
        'occasionId': 1,
        'occasionTitle': 'Country bál 2026',
        'occasionLink': 'synthetic-event',
        'occurredAt': entry[1],
        'data': entry[0] == 'form_closed'
            ? {'title': 'Vstupenky', 'reason': 'schedule_end'}
            : {
                'relatedOrders': true,
                'activityCount': entry[0] == 'order_created' ? 35 : 1,
                'contact': {'name': 'Jan', 'surname': 'Novák'},
                'count': 2,
              },
      }),
  ];
  controller.occasions = [
    {'id': 1, 'title': 'Country bál 2026'},
  ];
  final dark = Uri.base.queryParameters['theme'] == 'dark';
  runApp(
    EasyLocalization(
      supportedLocales: const [Locale('cs')],
      startLocale: const Locale('cs'),
      path: 'assets/translations',
      child: Builder(
        builder: (context) => MaterialApp(
          debugShowCheckedModeBanner: false,
          builder: DependencyMaterialBridge.builder,
          theme: ThemeConfig.theme(
            brightness: dark ? Brightness.dark : Brightness.light,
          ),
          locale: context.locale,
          supportedLocales: context.supportedLocales,
          localizationsDelegates: [
            ...context.localizationDelegates,
            ...GlobalMaterialLocalizations.delegates,
          ],
          home: Scaffold(
            body: NotificationCenterPanel(
              controller: controller,
              anchor: const Rect.fromLTWH(500, 8, 48, 48),
              onDetail: (_) {},
            ),
          ),
        ),
      ),
    ),
  );
  WidgetsBinding.instance.addPostFrameCallback(
    (_) => WebBootstrapBridge.markAppReady(),
  );
}
