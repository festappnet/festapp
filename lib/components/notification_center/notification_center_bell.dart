import 'package:fstapp/data_services/authorization_capabilities.dart';
import 'package:fstapp/components/navigation/route_visibility.dart';
import 'dart:async';
import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/components/navigation/root_route_navigation.dart';
import 'package:fstapp/components/email_delivery/email_delivery_history.dart';
import 'notification_center_controller.dart';
import 'notification_center_panel.dart';
import 'notification_center_strings.dart';
import 'notification_center_rollout.dart';

class NotificationCenterBell extends StatefulWidget {
  const NotificationCenterBell({super.key, this.color});
  final Color? color;
  @override
  State<NotificationCenterBell> createState() => _NotificationCenterBellState();
}

class _NotificationCenterBellState extends State<NotificationCenterBell>
    with WidgetsBindingObserver {
  final controller = NotificationCenterController();
  final focus = FocusNode();
  StreamSubscription<AuthState>? auth;
  StackRouter? _root;
  bool _resumed = true;
  bool _rolloutVisible = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    RightsService.occasionLinkModelNotifier.addListener(_rightsChanged);
    auth = Supabase.instance.client.auth.onAuthStateChange
        .listen((_) => _contextChanged());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final root = context.router.root;
    if (_root != root) {
      _root?.removeListener(_routeChanged);
      _root = root;
      root.addListener(_routeChanged);
    }
    _routeChanged();
  }

  void _routeChanged() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _contextChanged();
    });
  }

  void _rightsChanged() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _contextChanged(invalidate: true);
    });
  }

  void _contextChanged({bool invalidate = false}) {
    if (!mounted) return;
    final account = Supabase.instance.client.auth.currentUser;
    final userId = account?.id;
    final profile = RightsService.currentUser();
    final email = profile?.id == userId
        ? profile?.email ?? account?.email
        : account?.email;
    _rolloutVisible =
        userId != null && NotificationCenterRollout.isVisibleTo(email);
    if (!_rolloutVisible) {
      controller.configure(userId: null, organizationId: null);
      return;
    }
    final visible = isVisibleRouteInstance(context);
    controller.setForeground(_resumed && visible);
    if (!visible) return;
    final path = context.router.root.urlState.uri.pathSegments;
    final current = RightsService.currentOccasion();
    // Unit administration must never inherit the previous occasion's priority.
    final occasion =
        path.isNotEmpty && path.first == current?.link ? current?.id : null;
    controller.configure(
        userId: userId,
        organizationId:
            RightsService.currentUnit()?.organization ?? AppConfig.organization,
        occasionId: occasion,
        invalidate: invalidate);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    _contextChanged();
  }

  Future<void> _open() async {
    _contextChanged();
    if (!_rolloutVisible) return;
    unawaited(controller.open());
    NotificationItem? target;
    await showDialog<void>(
        context: context,
        builder: (dialogContext) => NotificationCenterPanel(
            controller: controller,
            onDetail: (item) {
              target = item;
              Navigator.of(dialogContext).pop();
            }));
    if (!mounted) return;
    controller.close();
    focus.requestFocus();
    if (target != null) await _detail(target!);
  }

  Future<void> _detail(NotificationItem item) async {
    final data = item.data;
    final link = item.occasionLink;
    if (data['messageId'] != null) {
      if (link != null) {
        await pushRootPath(
            context.router.root,
            Uri(pathSegments: [
              '',
              link,
              'reservations',
              'orders',
              'email-history'
            ], queryParameters: {
              'messageId': data['messageId'].toString()
            }).toString());
      } else {
        await showDialog<void>(
            context: context,
            builder: (_) => EmailDeliveryHistory(
                organizationId: controller.organization,
                messageId: data['messageId'].toString()));
      }
      return;
    }
    if (link != null && data['relatedOrders'] == true) {
      await pushRootPath(
          context.router.root,
          Uri(pathSegments: ['', link, 'reservations', 'orders', 'current'])
              .toString());
      return;
    }
    if (link != null && data['orderId'] is int) {
      await pushRootPath(
          context.router.root,
          Uri(
                  pathSegments: ['', link, 'reservations', 'orders', 'current'],
                  queryParameters: {'orderId': data['orderId'].toString()})
              .toString());
      return;
    }
    final account = data['bankAccountId'];
    final unit = data['unitId'];
    if (account is int &&
        unit is int &&
        RightsService.hasBankCapability(
            account, AuthorizationCapabilities.bankSyncManage)) {
      await pushRootPath(context.router.root,
          '/unit/$unit/edit/bank-accounts/$account/connection');
      return;
    }
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(NotificationCenterStrings.text('unavailable'))));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: controller,
      builder: (context, _) => !_rolloutVisible || !controller.enabled
          ? const SizedBox.shrink()
          : IconButton(
              focusNode: focus,
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              tooltip: NotificationCenterStrings.text(
                  controller.unread ? 'unread' : 'title'),
              onPressed: _open,
              icon: Badge(
                  isLabelVisible: controller.unread,
                  smallSize: 8,
                  child: Icon(Icons.notifications_none, color: widget.color)),
            ));
  @override
  void dispose() {
    RightsService.occasionLinkModelNotifier.removeListener(_rightsChanged);
    WidgetsBinding.instance.removeObserver(this);
    _root?.removeListener(_routeChanged);
    auth?.cancel();
    controller.dispose();
    focus.dispose();
    super.dispose();
  }
}
