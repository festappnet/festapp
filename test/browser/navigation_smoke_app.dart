import 'package:fstapp/services/web_bootstrap_bridge.dart';
// Isolated browser fixture: real AutoRoute/platform history, no backend writes.
import 'package:flutter/material.dart';
import 'package:fstapp/config/url_strategy_web.dart';
import '../support/navigation_fixture.dart';

void main() {
  configureUrlStrategy();
  WidgetsFlutterBinding.ensureInitialized().ensureSemantics();
  final router = FixtureRouter(Access());
  runApp(MaterialApp.router(routerConfig: router.config()));
  WidgetsBinding.instance
      .addPostFrameCallback((_) => WebBootstrapBridge.markAppReady());
}
