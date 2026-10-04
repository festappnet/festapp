import 'package:flutter/material.dart';
import 'package:auto_route/auto_route.dart';

/// Explicit visibility boundary for retained administration tabs.
class AdminTabActivity extends InheritedNotifier<TabController> {
  final int index;
  final List<String>? routeNames;
  final bool parentActive;
  const AdminTabActivity(
      {super.key,
      required TabController controller,
      this.index = 0,
      this.routeNames,
      this.parentActive = true,
      required super.child})
      : super(notifier: controller);

  @override
  bool updateShouldNotify(covariant AdminTabActivity oldWidget) =>
      parentActive != oldWidget.parentActive ||
      index != oldWidget.index ||
      super.updateShouldNotify(oldWidget);

  static bool isActive(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<AdminTabActivity>();
    if (scope == null) return true;
    var index = scope.index;
    if (scope.routeNames != null) {
      index = -1;
      RouteData? route = context.routeData;
      while (route != null && index < 0) {
        index = scope.routeNames!.indexOf(route.name);
        route = route.parent;
      }
    }
    return scope.parentActive && (index < 0 || scope.notifier!.index == index);
  }
}
