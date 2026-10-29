import 'package:festapp_core/forms.dart';
import 'package:fstapp/components/eshop/db_orders.dart';
import 'package:fstapp/components/eshop/models/order_model.dart';
import 'package:fstapp/components/forms/views/form_responses_content.dart';
import 'package:fstapp/components/single_data_grid/admin_tab_activity.dart';
import 'package:fstapp/components/single_data_grid/single_table_data_grid.dart';
import 'package:fstapp/components/forms/models/form_response_model.dart';
import 'package:fstapp/widgets/dependency_material_bridge.dart';
import 'package:fstapp/data_services/authorization_capabilities.dart';

import '../../support/fixtures/widget_environment_fixture.dart';

import 'package:festapp_core/eshop.dart';
import 'package:fstapp/components/bank_accounts/bank_account_strings.dart';
import 'package:fstapp/components/unit/unit_model.dart';
import 'package:fstapp/components/forms/views/form_design_content.dart';
import 'package:fstapp/components/forms/views/form_settings_content.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/components/features/form_feature.dart';

import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/forms/db_forms.dart';
import 'package:fstapp/components/forms/models/form_editor_draft.dart';
import 'package:fstapp/components/forms/models/form_field_draft.dart';
import 'package:fstapp/components/_shared/editor_action_bar.dart';
import 'package:fstapp/components/forms/views/form_editor_content.dart';
import 'package:fstapp/components/occasion/occasion_link_model.dart';
import 'package:fstapp/components/users/occasion_user_model.dart';
import 'package:fstapp/data_services/rights_service.dart';

late WidgetEnvironmentFixture _environment;

late ValueNotifier<({int accountId, int revision})> _bankChanges;
void main() {
  setUp(() {
    _bankChanges = ValueNotifier((accountId: 0, revision: 0));
    addTearDown(_bankChanges.dispose);
  });
  WidgetEnvironmentFixture.register();
  setUpAll(() {
    _environment = WidgetEnvironmentFixture(
      locale: const Locale('cs'),
      translations: jsonDecode(
        File('assets/translations/cs.json').readAsStringSync(),
      ) as Map<String, dynamic>,
    );
  });
  testWidgetsWithEnvironment(
    () => _environment,
    'responses read each source once and refresh once on tab return',
    (tester) async {
      var fieldsReads = 0, ordersReads = 0;
      final form = FormEditorDraft(
        id: 1,
        link: 'selected',
        title: 'Selected',
      ).toBundle();
      final other = FormEditorDraft(id: 2, link: 'other').toBundle();
      final orders = [
        OrderModel(
          id: 1,
          form: form,
          orderSymbol: '1',
          state: 'ordered',
          data: {
            FormMetadata.metaFields: [
              {'42': 'Answer'},
            ],
          },
        ),
        OrderModel(id: 2, form: other, orderSymbol: '2', state: 'ordered'),
      ];
      late TabController tabs;
      await _environment.pumpWidget(
        tester,
        MaterialApp(
          builder: DependencyMaterialBridge.builder,
          home: Builder(
            builder: (context) {
              tabs = TabController(length: 2, vsync: tester);
              return Scaffold(
                body: TabBarView(
                  controller: tabs,
                  children: [
                    AdminTabActivity(
                      controller: tabs,
                      index: 0,
                      child: FormResponsesContent(
                        formLink: 'selected',
                        loadFields: (link) async {
                          expect(link, 'selected');
                          fieldsReads++;
                          return [
                            FormFieldDefinition(
                              id: 42,
                              title: 'Question',
                              type: FormMetadata.fieldTypeText,
                            ),
                          ];
                        },
                        loadOrders:
                            ({
                              String? occasionLink,
                              String? formLink,
                              bool includeOrderDetails = false,
                              bool includeSpots = false,
                              bool includeOrdersHistory = false,
                            }) async {
                              expect(formLink, 'selected');
                              expect(includeOrderDetails, isTrue);
                              ordersReads++;
                              return ReservationsBundle(
                                orders: orders,
                                forms: [form],
                              );
                            },
                      ),
                    ),
                    const Text('Other tab'),
                  ],
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final grid = tester
          .widget<SingleTableDataGrid<FormResponseModel>>(
            find.byType(SingleTableDataGrid<FormResponseModel>),
          )
          .controller;
      expect(fieldsReads, 1);
      expect(ordersReads, 1);
      expect(grid.rows, hasLength(1));
      expect(grid.rows.single.cells['42']!.value, 'Answer');
      tabs.index = 1;
      await tester.pumpAndSettle();
      tabs.index = 0;
      await tester.pumpAndSettle();
      expect(fieldsReads, 1);
      expect(ordersReads, 2);
      await grid.reloadData();
      await tester.pumpAndSettle();
      expect(fieldsReads, 1);
      expect(ordersReads, 3);
      expect(tester.takeException(), isNull);
      await _environment.pumpWidget(tester, const SizedBox.shrink());
      tabs.dispose();
    },
  );
  for (final canManage in [true, false]) {
    for (final hasCzkAccount in [true, false]) {
      testWidgetsWithEnvironment(
        () => _environment,
        'bank guidance handles missing currencies and access ($canManage, $hasCzkAccount)',
        (tester) async {
          tester.view.physicalSize = const Size(1600, 1400);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
            capabilities: {
              AuthorizationCapabilities.formsWrite: true,
              AuthorizationCapabilities.ordersWrite: true,
              AuthorizationCapabilities.occasionsWrite: true,
              AuthorizationCapabilities.bankAccountsUnitManage: canManage,
            },
            unit: UnitModel(id: 5),
            unitUser: OccasionUserModel(isEditor: canManage),
            occasionUser: OccasionUserModel(isEditor: true),
            occasion: OccasionModel(
              isOpen: true,
              isHidden: false,
              isPromoted: false,
              features: [FormFeature(code: 'form')],
            ),
          );
          addTearDown(
            () => RightsService.occasionLinkModelNotifier.value = null,
          );
          final accounts = hasCzkAccount
              ? [
                  BankAccountModel(
                    id: 1,
                    title: 'CZK account',
                    supportedCurrencies: ['CZK'],
                  ),
                ]
              : <BankAccountModel>[];
          final field = FormFieldDraft(
            productType: ProductTypeModel(
              products: [
                ProductModel(currencyCode: 'CZK'),
                ProductModel(currencyCode: 'EUR'),
              ],
            ),
          );
          await _environment.pumpWidget(
            tester,
            MaterialApp(
              builder: DependencyMaterialBridge.builder,
              home: FormSettingsContent(
                bankConnectionChanges: _bankChanges,
                formLink: 'test',
                loadBundle: (_) async => FormEditBundle(
                  form: FormEditorDraft(
                    link: 'test',
                    relatedFields: [field],
                    availableBankAccounts: accounts,
                    data: {},
                  ),
                  productTypes: [],
                  products: [],
                  availableBankAccounts: accounts,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            find.text(
              BankAccountStrings.missingAccountForCurrencies(
                hasCzkAccount ? 'EUR' : 'CZK, EUR',
              ),
            ),
            findsOneWidget,
          );
          expect(
            find.text(
              canManage
                  ? BankAccountStrings.addAccountForPayments
                  : BankAccountStrings.askManagerForPaymentAccount,
              findRichText: true,
            ),
            findsOneWidget,
          );
          final guidance = tester.widget<Text>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is Text &&
                  widget.textSpan?.toPlainText() ==
                      (canManage
                          ? BankAccountStrings.addAccountForPayments
                          : BankAccountStrings.askManagerForPaymentAccount),
            ),
          );

          final links = (guidance.textSpan! as TextSpan).children!
              .whereType<TextSpan>()
              .where((span) => span.recognizer != null);
          expect(links.length, canManage ? 1 : 0);
          if (canManage) {
            expect(links.single.text, BankAccountStrings.organizationSettings);
            expect(links.single.style?.decoration, TextDecoration.underline);
          }
          expect(find.text('Spravovat účty'), findsNothing);
          await _environment.pumpWidget(tester, const SizedBox.shrink());
        },
      );
    }
  }
  testWidgetsWithEnvironment(
    () => _environment,
    'failed loading leaves the spinner and retry recovers',
    (tester) async {
      var calls = 0;
      await _environment.pumpWidget(
        tester,
        MaterialApp(
          builder: DependencyMaterialBridge.builder,
          home: FormEditorContent(
            formLink: 'test',
            loadBundle: (_) async {
              calls++;
              if (calls == 1) return null;
              return FormEditBundle(
                form: FormEditorDraft(link: 'test', data: {}),
                productTypes: [],
                products: [],
                availableBankAccounts: [],
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Common.retry'.tr()), findsOneWidget);
      await tester.tap(find.text('Common.retry'.tr()));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.text('Common.retry'.tr()), findsNothing);
      expect(find.byType(EditorActionBar), findsOneWidget);
    },
  );
  testWidgetsWithEnvironment(
    () => _environment,
    'cancel in an embedded form must not remove the administration route',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
        capabilities: {
          AuthorizationCapabilities.formsWrite: true,
          AuthorizationCapabilities.ordersWrite: true,
          AuthorizationCapabilities.occasionsWrite: true,
        },
        occasionUser: OccasionUserModel(isEditorOrder: true),
      );
      addTearDown(() => RightsService.occasionLinkModelNotifier.value = null);
      final navigator = GlobalKey<NavigatorState>();
      await _environment.pumpWidget(
        tester,
        MaterialApp(
          builder: DependencyMaterialBridge.builder,
          navigatorKey: navigator,
          home: const Scaffold(body: Text('home')),
        ),
      );
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => FormEditorContent(
            formLink: 'test',
            loadBundle: (_) async => FormEditBundle(
              form: FormEditorDraft(
                link: 'test',
                relatedFields: [
                  FormFieldDraft(
                    id: 5,
                    title: 'Original title',
                    type: 'text',
                    data: {},
                  ),
                ],
                data: {},
              ),
              productTypes: [],
              products: [],
              availableBankAccounts: [],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final save = find.widgetWithText(FilledButton, 'Common.save'.tr());
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      final field = find.widgetWithText(TextFormField, 'Original title');
      await tester.ensureVisible(field);
      await tester.enterText(field, 'Changed title');
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Changed title'),
        'Original title',
      );
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Original title'),
        'Changed title',
      );
      await tester.pumpAndSettle();
      final discard = find.descendant(
        of: find.byType(EditorActionBar),
        matching: find.byType(TextButton),
      );
      await tester.tap(discard);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Common.keepEditing'.tr()));
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(TextFormField, 'Changed title'),
        findsOneWidget,
      );
      await tester.tap(discard);
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilledButton, 'Common.discardChanges'.tr()),
      );
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(TextFormField, 'Original title'),
        findsOneWidget,
      );
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      expect(find.byType(FormEditorContent), findsOneWidget);
    },
  );
  testWidgetsWithEnvironment(
    () => _environment,
    'design adopts authoritative receipt and uses its new version on the next save without a reload',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
        capabilities: {AuthorizationCapabilities.formsWrite: true},
      );
      addTearDown(() => RightsService.occasionLinkModelNotifier.value = null);
      var reads = 0;
      final savedVersions = <int>[];
      await _environment.pumpWidget(
        tester,
        MaterialApp(
          builder: DependencyMaterialBridge.builder,
          home: FormDesignContent(
            formLink: 'test',
            loadBundle: (_) async {
              reads++;
              return FormEditBundle(
                form: FormEditorDraft(
                  id: 1,
                  occasionId: 7,
                  aggregateVersion: 3,
                ),
                productTypes: [],
                products: [],
                availableBankAccounts: [],
              );
            },
            saveForm: (draft) async {
              savedVersions.add(draft.aggregateVersion);
              return FormEditorDraft(
                aggregateVersion: draft.aggregateVersion + 1,
              )..definition = draft.definition;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.byType(Switch).first);
        await tester.pumpAndSettle();
        final save = find.widgetWithText(FilledButton, 'Common.save'.tr());
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(tester.widget<FilledButton>(save).onPressed, isNull);
      }
      expect(savedVersions, [3, 4]);
      expect(reads, 1);
    },
  );
  for (final design in [true, false]) {
    testWidgetsWithEnvironment(
      () => _environment,
      '${design ? "design" : "settings"} discard restores data without closing the tab',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
          capabilities: {
            AuthorizationCapabilities.formsWrite: true,
            AuthorizationCapabilities.ordersWrite: true,
            AuthorizationCapabilities.occasionsWrite: true,
          },
          occasionUser: OccasionUserModel(isEditor: true),
          occasion: OccasionModel(
            isOpen: true,
            isHidden: false,
            isPromoted: false,
            features: [FormFeature(code: 'form')],
          ),
        );
        addTearDown(() => RightsService.occasionLinkModelNotifier.value = null);
        var closes = 0;
        Future<FormEditBundle?> load(String _) async => FormEditBundle(
          form: FormEditorDraft(
            link: 'test',
            title: 'Original title',
            relatedFields: [],
            data: {
              'design': <String, dynamic>{
                'primary_color': '#336699',
                'secondary_color': '#112233',
              },
            },
          ),
          productTypes: [],
          products: [],
          availableBankAccounts: [],
        );
        await _environment.pumpWidget(
          tester,
          MaterialApp(
            builder: DependencyMaterialBridge.builder,
            home: design
                ? FormDesignContent(
                    formLink: 'test',
                    loadBundle: load,
                    onActionCompleted: () => closes++,
                  )
                : FormSettingsContent(
                    bankConnectionChanges: _bankChanges,
                    formLink: 'test',
                    loadBundle: load,
                    onActionCompleted: () => closes++,
                  ),
          ),
        );
        await tester.pumpAndSettle();
        final save = find.widgetWithText(FilledButton, 'Common.save'.tr());
        expect(tester.widget<FilledButton>(save).onPressed, isNull);
        Future<void> edit() async {
          if (design) {
            await tester.tap(find.byType(SwitchListTile).first);
          } else {
            await tester.enterText(
              find.widgetWithText(TextFormField, 'Original title'),
              'Changed title',
            );
          }
          await tester.pumpAndSettle();
        }

        await edit();
        expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
        if (design) {
          await edit();
          expect(tester.widget<FilledButton>(save).onPressed, isNull);
          await edit();
        }
        await tester.tap(
          find.descendant(
            of: find.byType(EditorActionBar),
            matching: find.byType(TextButton),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.widgetWithText(FilledButton, 'Common.discardChanges'.tr()),
        );
        await tester.pumpAndSettle();
        expect(closes, 0);
        expect(tester.widget<FilledButton>(save).onPressed, isNull);
        if (design) {
          expect(
            tester
                .widget<SwitchListTile>(find.byType(SwitchListTile).first)
                .value,
            false,
          );
        } else {
          expect(
            find.widgetWithText(TextFormField, 'Original title'),
            findsOneWidget,
          );
        }
      },
    );
  }
}
