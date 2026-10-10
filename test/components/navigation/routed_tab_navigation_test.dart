import 'package:fstapp/components/single_data_grid/admin_tab_activity.dart';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:fstapp/components/navigation/routed_day_tabs.dart';
import '../../support/navigation_fixture.dart';
import 'dart:async';
import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/app_router.gr.dart';
import 'package:fstapp/router_service.dart';
import 'package:fstapp/components/navigation/occasion_administration_boundary.dart';
import 'package:fstapp/components/navigation/retained_draft_guard.dart';

Future<void> mount(WidgetTester tester, FixtureRouter router, String path,
    {GlobalKey? frameKey}) async {
  await tester.pumpWidget(RepaintBoundary(
      key: frameKey,
      child: MaterialApp.router(
          theme: ThemeData(
              appBarTheme:
                  const AppBarTheme(backgroundColor: Color(0xff101828))),
          routerConfig: router.config(
              deepLinkBuilder: (link) => link.initial
                  ? DeepLink.path(path, includePrefixMatches: false)
                  : link))));
  await tester.pumpAndSettle();
}

class _ActivityProbe extends StatefulWidget {
  final ValueChanged<bool> changed;
  const _ActivityProbe(this.changed);
  @override
  State<_ActivityProbe> createState() => _ActivityProbeState();
}

class _ActivityProbeState extends State<_ActivityProbe> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    widget.changed(AdminTabActivity.isActive(context));
  }

  @override
  Widget build(BuildContext context) => const Text('CURRENT CONTENT');
}

void main() {
  testWidgets('clicking Orders from history returns to current orders',
      (tester) async {
    final router = FixtureRouter(Access());
    await mount(tester, router,
        '/occasion-a/reservations/orders/history?filter=one&filter=two');
    await tester.tap(find.text('Orders'));
    await tester.pumpAndSettle();
    expect(router.currentUrl,
        '/occasion-a/reservations/orders/current?filter=one&filter=two');
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('nested forms route follows the containing tab activity',
      (tester) async {
    final activity = <bool>[];
    final router = FixtureRouter(Access());
    router.formsListBuilder = (_) => _ActivityProbe(activity.add);
    await mount(tester, router, '/occasion-a/reservations/forms');
    expect(activity.last, isTrue);
    await tester.tap(find.text('Orders'));
    await tester.pumpAndSettle();
    expect(activity.last, isFalse);
    await tester.tap(find.text('Forms'));
    await tester.pumpAndSettle();
    expect(activity.last, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
      'retained nested route reports activity on inner and outer returns',
      (tester) async {
    final activity = <bool>[];
    final router = FixtureRouter(Access());
    router.ordersCurrentBuilder = (_) => _ActivityProbe(activity.add);
    await mount(tester, router, '/occasion-a/reservations/orders/current');
    expect(activity.last, isTrue);
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    expect(activity.last, isFalse);
    await tester.tap(find.text('Current'));
    await tester.pumpAndSettle();
    expect(activity.last, isTrue);
    await tester.tap(find.text('Report'));
    await tester.pumpAndSettle();
    expect(activity.last, isFalse);
    await tester.tap(find.text('Orders'));
    await tester.pumpAndSettle();
    expect(activity.last, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('occasion switch keeps header visible while destination loads',
      (tester) async {
    final pending = Completer<void>();
    final access = Access()
      ..beforeLoad =
          (link) => link == 'occasion-b' ? pending.future : Future.value();
    final router = FixtureRouter(access)
      ..showHeader = true
      ..loadingBuilder = (_) => Scaffold(
          appBar: AppBar(
              automaticallyImplyLeading: false,
              title: const Text('ADMIN HEADER')),
          body: const Center(child: CircularProgressIndicator()));
    final frameKey = GlobalKey();
    await mount(tester, router, '/occasion-a/reservations/orders/history',
        frameKey: frameKey);
    Future<void> expectPaintedHeader(String phase, int frame) async {
      final pixel = await tester.runAsync(() async {
        final boundary = frameKey.currentContext!.findRenderObject()
            as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final pixels =
            await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        final offset = (10 * image.width + 10) * 4;
        final rgba = pixels!.buffer.asUint8List(offset, 4).toList();
        image.dispose();
        return rgba;
      });
      expect(pixel, [16, 24, 40, 255],
          reason: 'Header must remain painted on $phase frame $frame');
    }

    final header = tester.getRect(find.text('ADMIN HEADER'));
    unawaited(RouterService.navigateToOccasionAdministration(
        tester.element(find.text('HISTORY CONTENT')),
        occasionLink: 'occasion-b'));
    for (var frame = 0; frame < 32; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      await expectPaintedHeader('context switch', frame);
    }
    expect(find.text('ADMIN HEADER'), findsOneWidget);
    expect(tester.getRect(find.text('ADMIN HEADER')), header);
    expect(find.text('HISTORY CONTENT'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    pending.complete();
    for (var frame = 0; frame < 24; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      await expectPaintedHeader('loading completion', frame);
    }
    await tester.pumpAndSettle();
    expect(find.text('ADMIN HEADER'), findsOneWidget);
    expect(find.text('HISTORY CONTENT'), findsOneWidget);
    expect(access.requests, ['occasion-a', 'occasion-b']);
  });

  testWidgets('denied context without a resolved link stops reloading',
      (tester) async {
    final access = Access();
    access.beforeLoad = (_) async {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      access.identity = null;
      access.notifyListeners();
      throw StateError('Access denied without an occasion');
    };
    final router = FixtureRouter(access);
    await tester.pumpWidget(MaterialApp.router(
        routerConfig: router.config(
            deepLinkBuilder: (_) => DeepLink.path(
                '/denied-occasion/reservations/orders/current'))));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(access.requests, ['denied-occasion']);
    expect(find.text('Access denied'), findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isFalse);
    access.beforeLoad = null;
    await tester.tap(find.byType(TextButton));
    await tester.pumpAndSettle();
    expect(access.requests, ['denied-occasion', 'denied-occasion']);
    expect(find.text('CURRENT CONTENT'), findsOneWidget);
  });

  testWidgets(
      'occasion switch preserves Report from the outer breadcrumb context',
      (tester) async {
    final access = Access();
    final router = FixtureRouter(access);
    await mount(tester, router, '/occasion-a/reservations/report');
    final context = tester.element(find.byType(OccasionAdministrationBoundary));
    unawaited(RouterService.navigateToOccasionAdministration(context,
        occasionLink: 'occasion-b'));
    await tester.pumpAndSettle();
    expect(router.currentUrl, '/occasion-b/reservations/report');
    expect(find.text('REPORT CONTENT'), findsOneWidget);
    expect(access.requests, ['occasion-a', 'occasion-b']);
  });

  testWidgets('occasion switch drops the previous form identity',
      (tester) async {
    final router = FixtureRouter(Access());
    await mount(
        tester, router, '/occasion-a/reservations/forms/second/responses');
    unawaited(RouterService.navigateToOccasionAdministration(
        tester.element(find.text('RESPONSES CONTENT')),
        occasionLink: 'occasion-b'));
    await tester.pumpAndSettle();
    expect(router.currentUrl, '/occasion-b/reservations/forms');
    expect(find.text('FORMS LIST'), findsOneWidget);
  });

  testWidgets('incoming browser history restores retained occasion context',
      (tester) async {
    final access = Access();
    final router = FixtureRouter(access);
    const target = '/occasion-a/reservations/orders/history';
    await mount(tester, router, target);
    unawaited(RouterService.navigateToOccasionAdministration(
        tester.element(find.text('HISTORY CONTENT')),
        occasionLink: 'occasion-b'));
    await tester.pumpAndSettle();
    await router.delegate().setNewRoutePath(UrlState(Uri.parse(target),
        router.matcher.match(target, includePrefixMatches: false)!));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(access.requests, ['occasion-a', 'occasion-b', 'occasion-a']);
    expect(find.text('HISTORY CONTENT'), findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('occasion breadcrumb switch settles and Back restores context',
      (tester) async {
    final access = Access();
    final router = FixtureRouter(access);
    await mount(tester, router, '/occasion-a/reservations/orders/history');
    final context = tester.element(find.text('HISTORY CONTENT'));
    unawaited(RouterService.navigateToOccasionAdministration(context,
        occasionLink: 'occasion-b'));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(access.requests, ['occasion-a', 'occasion-b']);
    expect(router.currentUrl, '/occasion-b/reservations/orders/history');
    expect(find.text('HISTORY CONTENT'), findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isFalse,
        reason: 'Breadcrumb switching must stop refreshing after loading');
    unawaited(RouterService.navigateToOccasionAdministration(
        tester.element(find.text('HISTORY CONTENT')),
        occasionLink: 'occasion-a'));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(access.requests, ['occasion-a', 'occasion-b', 'occasion-a']);
    expect(tester.binding.hasScheduledFrame, isFalse);
    await router.maybePop();
    await tester.pumpAndSettle();
    expect(router.currentUrl, '/occasion-b/reservations/orders/history');
    await router.maybePop();
    await tester.pumpAndSettle();
    expect(router.currentUrl, '/occasion-a/reservations/orders/history');
    expect(find.text('HISTORY CONTENT'), findsOneWidget);
    expect(access.requests,
        ['occasion-a', 'occasion-b', 'occasion-a', 'occasion-b', 'occasion-a']);
  });

  testWidgets(
      'deep links select history and parent clicks return to current orders',
      (tester) async {
    final router = FixtureRouter(Access());
    await mount(tester, router, '/occasion-a/reservations/orders/history');
    expect(find.text('HISTORY CONTENT'), findsOneWidget);
    await tester.tap(find.text('Current'));
    await tester.pumpAndSettle();
    expect(router.currentUrl, '/occasion-a/reservations/orders/current');
    await tester.tap(find.text('Current'));
    await tester.pumpAndSettle();
    expect(router.currentUrl, '/occasion-a/reservations/orders/current');
    await router.navigate(router.buildPageRoute(
        '/occasion-a/reservations/orders/history',
        includePrefixMatches: false)!);
    await tester.pumpAndSettle();
    expect(find.text('HISTORY CONTENT'), findsOneWidget);
    await tester.tap(find.text('Forms'));
    await tester.pumpAndSettle();
    expect(find.text('FORMS LIST'), findsOneWidget);
    await tester.tap(find.text('Orders'));
    await tester.pumpAndSettle();
    expect(router.currentUrl, '/occasion-a/reservations/orders/current');
  });
  testWidgets('feature-disabled direct link replaces with first available tab',
      (tester) async {
    final router = FixtureRouter(Access())..extra = false;
    await mount(tester, router, '/occasion-a/reservations/forms');
    expect(router.currentUrl, '/occasion-a/reservations/orders/current');
    expect(find.text('CURRENT CONTENT'), findsOneWidget);
  });
  testWidgets(
      'removing an active feature replaces it with an available section',
      (tester) async {
    final router = FixtureRouter(Access());
    await mount(tester, router, '/occasion-a/reservations/forms');
    router.extra = false;
    router.access.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('Forms'), findsNothing);
    expect(find.text('CURRENT CONTENT'), findsOneWidget);
    expect(router.currentUrl, '/occasion-a/reservations/orders/current');
  });
  testWidgets('unknown section stays locally not found', (tester) async {
    final router = FixtureRouter(Access());
    await mount(tester, router, '/occasion-a/reservations/unknown');
    expect(router.currentUrl, '/occasion-a/reservations/unknown');
    expect(find.text('Not found'), findsOneWidget);
  });
  testWidgets(
      'incoming unknown section is locally not found after visiting a valid tab',
      (tester) async {
    final router = FixtureRouter(Access());
    await mount(tester, router, '/occasion-a/reservations/orders/current');
    await router.navigateAll(router.matcher.match(
        '/occasion-a/reservations/unknown',
        includePrefixMatches: false)!);
    await tester.pumpAndSettle();
    expect(router.currentUrl, '/occasion-a/reservations/unknown');
    expect(find.text('Not found'), findsOneWidget);
  });
  testWidgets('denied access never creates a child', (tester) async {
    final router = FixtureRouter(Access()..allowed = false);
    await mount(tester, router, '/occasion-a/reservations/orders/history');
    expect(find.text('Access denied'), findsOneWidget);
    expect(find.text('HISTORY CONTENT'), findsNothing);
  });
  testWidgets('login retains full intended suffix and query', (tester) async {
    final router = FixtureRouter(Access()..signedIn = false);
    const target =
        '/occasion-a/reservations/forms/second/responses?day=2026-10-03';
    await mount(tester, router, target);
    final uri = Uri.parse(router.currentUrl);
    expect(uri.path, '/login');
    expect(uri.queryParameters['redirect'], target);
    router.access.signedIn = true;
    unawaited(router.replacePath(uri.queryParameters['redirect']!));
    await tester.pumpAndSettle();
    expect(router.currentUrl, target);
    expect(find.text('RESPONSES CONTENT'), findsOneWidget);
  });
  testWidgets('retained form subtabs preserve editor and cancelled leave',
      (tester) async {
    final router = FixtureRouter(Access());
    await mount(tester, router, '/occasion-a/reservations/forms/second/editor');
    await tester.enterText(find.byKey(const Key('draft-field')), 'unsaved');
    router.dirty = true;
    await tester.tap(find.text('Responses'));
    await tester.pumpAndSettle();
    expect(
        router.currentUrl, '/occasion-a/reservations/forms/second/responses');
    await tester.tap(find.text('Editor'));
    await tester.pumpAndSettle();
    expect(
        tester
                .widget<TextField>(find.byKey(const Key('draft-field')))
                .controller
                ?.text ??
            tester
                .state<EditableTextState>(find.byType(EditableText))
                .widget
                .controller
                .text,
        'unsaved');
    final old = router.currentUrl;
    final allowed = await RetainedDraftGuard.instance
        .confirmPath(router, Uri.parse('/occasion-a/reservations/forms'));
    expect(allowed, isFalse);
    expect(router.prompts, 1);
    expect(router.currentUrl, old);
    router.discard = true;
    final context = tester.element(find.byKey(const Key('draft-field')));
    await RetainedDraftGuard.instance.leaveOwner(
        context, () => context.router.replaceAll([const FormsListRoute()]));
    await tester.pumpAndSettle();
    expect(router.currentUrl, '/occasion-a/reservations/forms');
    expect(find.text('FORMS LIST'), findsOneWidget);
  });
  testWidgets(
      'calendar click and incoming URL drive date without losing other query',
      (tester) async {
    final router = FixtureRouter(Access());
    await mount(
        tester, router, '/calendar?day=2026-10-10&preview-day=2026-10-03');
    expect(find.text('SECOND DAY'), findsOneWidget);
    await tester.tap(find.text('3 October'));
    await tester.pumpAndSettle();
    expect(Uri.parse(router.currentUrl).queryParameters,
        {'day': '2026-10-03', 'preview-day': '2026-10-03'});
    await router.navigate(router.buildPageRoute(
        '/calendar?day=2026-10-10&preview-day=2026-10-03',
        includePrefixMatches: false)!);
    await tester.pumpAndSettle();
    expect(find.text('SECOND DAY'), findsOneWidget);
  });
  testWidgets(
      'rights revocation hides retained content and restored access reloads it',
      (tester) async {
    final access = Access();
    final router = FixtureRouter(access);
    await mount(tester, router, '/occasion-a/reservations/orders/history');
    access.allowed = false;
    access.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('Access denied'), findsOneWidget);
    expect(find.text('HISTORY CONTENT'), findsNothing);
    access.allowed = true;
    access.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('HISTORY CONTENT'), findsOneWidget);
  });
  testWidgets('invalid date replaces with a valid calendar day',
      (tester) async {
    final router = FixtureRouter(Access());
    await mount(
        tester, router, '/calendar?day=2026-02-30&preview-day=2026-10-10');
    expect(Uri.parse(router.currentUrl).queryParameters,
        {'day': '2026-10-03', 'preview-day': '2026-10-10'});
    expect(find.text('FIRST DAY'), findsOneWidget);
  });
  testWidgets(
      'query updates retain object identity and repeated unrelated values',
      (tester) async {
    final router = FixtureRouter(Access());
    await mount(tester, router,
        '/occasion-a/reservations/forms/second/responses?tag=a&tag=b');
    await DayRouteSelection.write(router, 'preview-day', '2026-10-10');
    await tester.pumpAndSettle();
    expect(Uri.parse(router.currentUrl).path,
        '/occasion-a/reservations/forms/second/responses');
    expect(Uri.parse(router.currentUrl).queryParametersAll['tag'], ['a', 'b']);
    expect(find.text('RESPONSES CONTENT'), findsOneWidget);
  });
  testWidgets('stale occasion completion cannot activate the old child',
      (tester) async {
    final blocker = Completer<void>();
    final access = Access()
      ..beforeLoad =
          (link) => link == 'occasion-a' ? blocker.future : Future.value();
    final router = FixtureRouter(access);
    await tester.pumpWidget(MaterialApp.router(
        routerConfig: router.config(
            deepLinkBuilder: (_) => const DeepLink.path(
                '/occasion-a/reservations/orders/history'))));
    await tester.pump();
    await router.navigate(router.buildPageRoute(
        '/occasion-b/reservations/orders/current',
        includePrefixMatches: false)!);
    await tester.pump();
    expect(router.currentUrl, '/occasion-b/reservations/orders/current');
    blocker.complete();
    await tester.pumpAndSettle();
    expect(find.text('HISTORY CONTENT'), findsNothing);
    expect(access.loadedLink, 'occasion-b');
    expect(find.text('CURRENT CONTENT'), findsOneWidget);
  });
}
