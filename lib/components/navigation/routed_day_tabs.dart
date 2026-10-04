import 'dart:async';
import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

/// Calendar identity in the occasion's timezone, independent of weekday/order.
abstract final class DayRouteSelection {
  static String format(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
  static DateTime? parse(String? value) {
    if (value == null || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value))
      return null;
    final date = DateTime.tryParse(value);
    return date != null && format(date) == value ? date : null;
  }

  static int resolve(List<DateTime> days, String? value, int fallback) {
    final parsed = parse(value);
    final index = parsed == null
        ? -1
        : days.indexWhere((day) => format(day) == format(parsed));
    return index >= 0 ? index : fallback.clamp(0, days.length - 1);
  }

  static Future<void> write(StackRouter root, String parameter, String? value,
      {bool replace = false}) async {
    final uri = root.urlState.uri;
    final query = Map<String, List<String>>.of(uri.queryParametersAll);
    if (value == null) {
      query.remove(parameter);
    } else {
      query[parameter] = [value];
    }
    final target = uri
        .replace(query: query.isEmpty ? '' : Uri(queryParameters: query).query)
        .toString();
    if (target == root.urlState.uri.toString()) return;
    if (replace) root.markUrlStateForReplace();
    await root
        .navigate(root.buildPageRoute(target, includePrefixMatches: false)!);
  }
}

/// TabController is a presentation mechanism; the router owns calendar state.
class RoutedDayTabs extends StatelessWidget {
  final List<DateTime> days;
  final int initialIndex;
  final String parameter;
  final Widget child;
  const RoutedDayTabs(
      {super.key,
      required this.days,
      required this.child,
      this.initialIndex = 0,
      this.parameter = 'day'});
  @override
  Widget build(BuildContext context) => DefaultTabController(
      length: days.length,
      initialIndex: initialIndex.clamp(0, days.length - 1),
      child: RoutedDayBinding(days: days, parameter: parameter, child: child));
}

class RoutedDayBinding extends StatefulWidget {
  final List<DateTime> days;
  final TabController? controller;
  final String parameter;
  final Widget child;
  const RoutedDayBinding(
      {super.key,
      required this.days,
      required this.child,
      this.controller,
      this.parameter = 'day'});
  @override
  State<RoutedDayBinding> createState() => _RoutedDayBindingState();
}

class _RoutedDayBindingState extends State<RoutedDayBinding> {
  StackRouter? _root;
  RouteData? _route;
  TabController? _controller;
  bool _fromRoute = false;
  String? _lastDay;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = context.findAncestorWidgetOfExactType<RouterScope>();
    final root = scope?.controller.root;
    if (_root != root) {
      _root?.removeListener(_sync);
      _root = root;
      _root?.addListener(_sync);
    }
    _route = context.findAncestorWidgetOfExactType<RouteDataScope>()?.routeData;
    _bind();
  }

  @override
  void didUpdateWidget(RoutedDayBinding oldWidget) {
    super.didUpdateWidget(oldWidget);
    _bind();
  }

  void _bind() {
    final controller = widget.controller ?? DefaultTabController.of(context);
    if (_controller != controller) {
      _controller?.removeListener(_changed);
      _controller = controller;
      _controller?.addListener(_changed);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _sync();
    });
  }

  bool get _active => _route?.isActive ?? true;
  void _sync() {
    if (!mounted || _root == null || !_active || widget.days.isEmpty) return;
    final value = _root!.urlState.uri.queryParameters[widget.parameter];
    final index =
        DayRouteSelection.resolve(widget.days, value, _controller!.index);
    _lastDay = DayRouteSelection.format(widget.days[index]);
    _fromRoute = true;
    _controller!.index = index;
    _fromRoute = false;
    if (value != _lastDay) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _active)
          unawaited(DayRouteSelection.write(_root!, widget.parameter, _lastDay,
              replace: true));
      });
    }
  }

  void _changed() {
    if (_fromRoute || _root == null || !_active || widget.days.isEmpty) return;
    final value = DayRouteSelection.format(widget.days[_controller!.index]);
    if (_lastDay == value) return;
    _lastDay = value;
    unawaited(DayRouteSelection.write(_root!, widget.parameter, value));
  }

  @override
  void dispose() {
    _root?.removeListener(_sync);
    _controller?.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
