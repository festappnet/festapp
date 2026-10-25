import 'package:material_ui/material_ui.dart';

class MouseDetector extends StatefulWidget {
  final Widget Function(BuildContext context, bool mouseIsConnected) builder;

  const MouseDetector({super.key, required this.builder});

  @override
  State<MouseDetector> createState() => _MouseDetectorState();
}

class _MouseDetectorState extends State<MouseDetector> {
  bool _mouseIsConnected = false;

  @override
  initState() {
    super.initState();
    WidgetsBinding.instance.mouseTracker.addListener(_handleMouseTrackerChange);
    _mouseIsConnected = WidgetsBinding.instance.mouseTracker.mouseIsConnected;
  }

  @override
  dispose() {
    WidgetsBinding.instance.mouseTracker
        .removeListener(_handleMouseTrackerChange);
    super.dispose();
  }

  void _handleMouseTrackerChange() {
    setState(() {
      _mouseIsConnected = WidgetsBinding.instance.mouseTracker.mouseIsConnected;
    });
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _mouseIsConnected);
  }
}
