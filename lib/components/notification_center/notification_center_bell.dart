import 'dart:convert';

import 'package:fstapp/services/exception_handler.dart';
import 'package:fstapp/components/email_delivery/order_email_issue.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:fstapp/data_services/authorization_capabilities.dart';
import 'package:fstapp/components/navigation/route_visibility.dart';

import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/components/navigation/root_route_navigation.dart';
import 'package:fstapp/components/email_delivery/email_delivery_history.dart';

import 'notification_center_controller.dart';
import 'notification_item_presenter.dart';
import 'notification_detail_target.dart';
import 'notification_center_panel.dart';
import 'notification_center_strings.dart';

/// A dedicated asset avoids stale cached MaterialIcons subsets after a release.
class NotificationBellIcon extends StatelessWidget {
  const NotificationBellIcon({super.key, required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    'assets/icons/notification-bell.svg',
    width: 24,
    height: 24,
    colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    excludeFromSemantics: true,
  );
}

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
  final _bellKey = GlobalKey();
  StreamSubscription<AuthState>? auth;
  StackRouter? _root;
  bool _resumed = true;
  bool _authenticated = false;
  Future<bool>? _waitingForContext;
  @override
  void initState() {
    super.initState();
    OrderEmailIssue.changes.addListener(_deliveryChanged);
    WidgetsBinding.instance.addObserver(this);
    RightsService.occasionLinkModelNotifier.addListener(_rightsChanged);
    auth = Supabase.instance.client.auth.onAuthStateChange.listen(
      (_) => _contextChanged(),
    );
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

  bool _contextUpdateScheduled = false, _pendingInvalidation = false;

  void _scheduleContextUpdate({bool invalidate = false}) {
    _pendingInvalidation |= invalidate;
    if (_contextUpdateScheduled) return;
    _contextUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _contextUpdateScheduled = false;
      final invalidate = _pendingInvalidation;
      _pendingInvalidation = false;
      if (mounted) _contextChanged(invalidate: invalidate);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _routeChanged() => _scheduleContextUpdate();

  void _deliveryChanged() {
    controller.refresh();
  }

  void _rightsChanged() => _scheduleContextUpdate(invalidate: true);

  void _contextChanged({bool invalidate = false}) {
    if (!mounted) return;
    final account = Supabase.instance.client.auth.currentUser;
    final userId = account?.id;
    _authenticated = userId != null;
    if (!_authenticated) {
      controller.configure(userId: null, organizationId: null);
      return;
    }
    final pendingContext = RightsService.pendingContextUpdate;
    if (pendingContext != null) {
      // Capability invalidation and the final context both notify listeners.
      // Discard private state immediately, but read the badge only once the
      // authoritative context has finished loading.
      controller.setForeground(false);
      controller.configure(userId: null, organizationId: null);
      if (!identical(_waitingForContext, pendingContext)) {
        _waitingForContext = pendingContext;
        pendingContext.then(
          (loaded) {
            if (!mounted || !identical(_waitingForContext, pendingContext)) {
              return;
            }
            _waitingForContext = null;
            if (loaded) _scheduleContextUpdate(invalidate: true);
          },
          onError: (Object _, StackTrace _) {
            if (identical(_waitingForContext, pendingContext)) {
              _waitingForContext = null;
            }
          },
        );
      }
      return;
    }
    final visible = isVisibleRouteInstance(context);
    if (!visible || !_resumed) controller.setForeground(false);
    if (!visible) return;
    final path = context.router.root.urlState.uri.pathSegments;
    final current = RightsService.currentOccasion();
    // Unit administration must never inherit the previous occasion's priority.
    final occasion = path.isNotEmpty && path.first == current?.link
        ? current?.id
        : null;
    controller.configure(
      userId: userId,
      organizationId:
          RightsService.currentUnit()?.organization ?? AppConfig.organization,
      occasionId: occasion,
      invalidate: invalidate,
    );
    controller.setForeground(_resumed);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    if (_resumed) {
      // Merge resume with context invalidations queued while frames were paused.
      _scheduleContextUpdate();
    } else {
      controller.setForeground(false);
    }
  }

  Future<void> _open() async {
    _contextChanged();
    if (!_authenticated) return;
    unawaited(controller.open());
    final desktop = MediaQuery.sizeOf(context).width >= 720;
    final bell = _bellKey.currentContext?.findRenderObject() as RenderBox?;
    final overlay =
        Navigator.of(
              context,
              rootNavigator: true,
            ).overlay!.context.findRenderObject()
            as RenderBox;
    final anchor = bell == null
        ? null
        : bell.localToGlobal(Offset.zero, ancestor: overlay) & bell.size;
    NotificationItem? target;
    Map<String, dynamic>? selection;
    await showDialog<void>(
      context: context,
      barrierColor: desktop ? Colors.transparent : Colors.black54,
      builder: (dialogContext) => NotificationCenterPanel(
        controller: controller,
        anchor: anchor,
        onDetail: (item) {
          selection = controller.selectionScope(item);
          if (item.isSummary && selection == null) {
            unawaited(controller.open());
            return;
          }
          target = item;
          Navigator.of(dialogContext).pop();
        },
      ),
    );
    if (!mounted) return;
    controller.close();
    focus.requestFocus();
    if (target != null) await _detail(target!, selection);
  }

  Future<void> _detail(
    NotificationItem item,
    Map<String, dynamic>? selection,
  ) async {
    final data = item.data;
    if (data['relatedOrders'] != true) {
      await ExceptionHandler.guard(
        context,
        futureFunction: () => controller.markRead(item),
      );
    }
    if (!mounted) return;
    final link = item.occasionLink;
    if (link != null && data['orderId'] is int) {
      await pushRootPath(
        context.router.root,
        Uri(
          pathSegments: ['', link, 'reservations', 'orders', 'current'],
          queryParameters: {
            'orderId': data['orderId'].toString(),
            if (data['messageId'] != null)
              'orderMessageId': data['messageId'].toString(),
          },
        ).toString(),
      );
      return;
    }
    if (data['messageId'] != null) {
      if (link != null) {
        await pushRootPath(
          context.router.root,
          Uri(
            pathSegments: ['', link, 'reservations', 'orders', 'email-history'],
            queryParameters: {'messageId': data['messageId'].toString()},
          ).toString(),
        );
      } else {
        await showDialog<void>(
          context: context,
          builder: (_) => EmailDeliveryHistory(
            organizationId: controller.organization,
            messageId: data['messageId'].toString(),
          ),
        );
      }
      return;
    }
    if (link != null && data['relatedOrders'] == true) {
      await pushRootPath(
        context.router.root,
        Uri(
          pathSegments: ['', link, 'reservations', 'orders', 'current'],
          queryParameters: selection != null
              ? {'notificationGroup': jsonEncode(selection)}
              : null,
        ).toString(),
      );
      return;
    }
    if (NotificationItemPresenter(item).hasFormDetail) {
      final user = controller.user;
      final organization = controller.organization;
      await ExceptionHandler.guard(
        context,
        futureFunction: () async {
          final path = await notificationFormDetailPath(item);
          if (!mounted ||
              controller.user != user ||
              controller.organization != organization) {
            return;
          }
          if (path != null) {
            await pushRootPath(context.router.root, path);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(NotificationCenterStrings.text('unavailable')),
              ),
            );
          }
        },
      );
      return;
    }
    final account = data['bankAccountId'];
    final unit = data['unitId'];
    if (account is int &&
        unit is int &&
        RightsService.hasBankCapability(
          account,
          AuthorizationCapabilities.bankSyncManage,
        )) {
      await pushRootPath(
        context.router.root,
        '/unit/$unit/edit/bank-accounts/$account/connection',
      );
      return;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(NotificationCenterStrings.text('unavailable'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => !_authenticated || !controller.enabled
        ? const SizedBox.shrink()
        : IconButton(
            key: _bellKey,
            focusNode: focus,
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            tooltip: NotificationCenterStrings.text(
              controller.unread ? 'unread' : 'title',
            ),
            onPressed: _open,
            icon: Badge(
              isLabelVisible: controller.unread,
              smallSize: 8,
              child: NotificationBellIcon(
                color:
                    widget.color ??
                    Theme.of(context).appBarTheme.foregroundColor ??
                    Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
  );
  @override
  void dispose() {
    RightsService.occasionLinkModelNotifier.removeListener(_rightsChanged);
    WidgetsBinding.instance.removeObserver(this);
    _root?.removeListener(_routeChanged);
    auth?.cancel();
    controller.dispose();
    focus.dispose();
    OrderEmailIssue.changes.removeListener(_deliveryChanged);
    super.dispose();
  }
}
