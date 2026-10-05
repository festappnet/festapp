import 'package:fstapp/components/eshop/models/report_exchange_rates.dart';
// Isolated report smoke harness. Uses synthetic data and never contacts a backend.
import 'dart:convert';
import 'dart:typed_data';
import 'package:easy_localization/easy_localization.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/components/eshop/views/report_tab.dart';
import 'package:fstapp/services/web_bootstrap_bridge.dart';
import 'occasion_report_fixture.dart';
import 'package:fstapp/theme_config.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();
  WidgetsBinding.instance.ensureSemantics();
  if (const bool.fromEnvironment('REPORT_PREVIEW_NATIVE_EXPORT')) {
    final path = await FileSaver.instance.saveFile(
        name: 'occasion_report_native_smoke',
        bytes: Uint8List.fromList(utf8.encode(reportFixture().text)),
        fileExtension: 'txt',
        mimeType: MimeType.text);
    debugPrint('REPORT_NATIVE_EXPORT=$path');
  }
  WidgetsBinding.instance
      .addPostFrameCallback((_) => WebBootstrapBridge.markAppReady());
  runApp(EasyLocalization(
    supportedLocales: const [Locale('cs')],
    startLocale: const Locale('cs'),
    path: 'assets/translations',
    child: Builder(
        builder: (context) => MaterialApp(
              theme: ThemeConfig.theme(),
              darkTheme: ThemeConfig.theme(brightness: Brightness.dark),
              themeMode: Uri.base.queryParameters['theme'] == 'dark'
                  ? ThemeMode.dark
                  : ThemeMode.light,
              locale: context.locale,
              supportedLocales: context.supportedLocales,
              localizationsDelegates: context.localizationDelegates,
              home: Builder(
                  builder: (context) => MediaQuery(
                        data: MediaQuery.of(context).copyWith(
                            textScaler: TextScaler.linear(double.tryParse(
                                    Uri.base.queryParameters['scale'] ?? '') ??
                                1)),
                        child: ReportTab(
                            exchangeRateLoader: () async =>
                                ReportExchangeRates.fromJson({
                                  'source': 'CNB',
                                  'base': 'CZK',
                                  'date': '2026-10-02',
                                  'rates': {
                                    'EUR': {'amount': '1', 'rate': '24.5'}
                                  }
                                }),
                            occasionLink: 'synthetic',
                            identityKey: 'synthetic/org',
                            loader: (_) async => reportFixture()),
                      )),
            )),
  ));
}
