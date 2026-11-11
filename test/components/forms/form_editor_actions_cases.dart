import 'package:fstapp/components/forms/form_strings.dart';
import 'package:fstapp/components/forms/widgets_editor/form_fields_generator.dart';
import 'package:fstapp/components/html/editable_html_field.dart';
import 'package:fstapp/components/html/rich_html_editor.dart';
import 'package:fstapp/components/forms/sale_opening_strings.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:super_editor/super_editor.dart';
import 'package:fstapp/components/forms/widgets_editor/product_type_editor.dart';
import 'package:fstapp/components/forms/widgets_editor/ticket_product_editor_row.dart';
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
    'outline scrolls vertically without animating ancestor tab pages',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final pages = PageController(initialPage: 1);
      addTearDown(pages.dispose);
      RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
        capabilities: {AuthorizationCapabilities.formsWrite: true},
      );
      addTearDown(() => RightsService.occasionLinkModelNotifier.value = null);
      await _environment.pumpWidget(tester, MaterialApp(
        builder: DependencyMaterialBridge.builder,
        home: PageView(
          controller: pages,
          children: [
            const SizedBox(),
            FormEditorContent(
              formLink: 'ples',
              loadBundle: (_) async => FormEditBundle(
                form: FormEditorDraft(
                  link: 'ples', occasionId: 1, isOpen: true, data: {},
                  header: '<p>Vítejte na plese</p>',
                  relatedFields: [for (var i = 1; i <= 8; i++)
                    FormFieldDraft(id: i, type: 'text', title: 'Otázka $i')],
                ),
                productTypes: [], products: [], availableBankAccounts: [],
              ),
            ),
            const SizedBox(),
          ],
        ),
      ));
      await tester.pumpAndSettle();
      final horizontalOffset = pages.position.pixels;
      final outline = find.byKey(const ValueKey('form-editor-outline'));
      final vertical = tester.widget<SingleChildScrollView>(find.ancestor(
        of: find.byType(FormFieldsGenerator),
        matching: find.byType(SingleChildScrollView),
      ).first).controller!;
      final save = find.descendant(of: find.byType(EditorActionBar),
        matching: find.widgetWithText(FilledButton, CommonStrings.save));
      Future<void> navigate(String label) async {
        await tester.tap(find.descendant(of: outline, matching: find.text(label)));
        // A settled-only assertion misses a horizontal animation that snaps back.
        for (var frame = 0; frame < 8; frame++) {
          await tester.pump(const Duration(milliseconds: 40));
          expect(pages.position.pixels, closeTo(horizontalOffset, 0.01));
        }
        expect(tester.widget<FilledButton>(save).onPressed, isNull);
      }
      await navigate('Otázka 4');
      final fieldOffset = vertical.offset;
      expect(fieldOffset, greaterThan(0));
      expect(tester.widget<TextFormField>(find.widgetWithText(
        TextFormField, 'Otázka 4')).initialValue, 'Otázka 4');
      await navigate(FormStrings.formIntroduction);
      expect(vertical.offset, lessThan(fieldOffset));
      await navigate(FormStrings.availability);
      expect(vertical.offset, lessThanOrEqualTo(12));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgetsWithEnvironment(
    () => _environment,
    'layout C preserves active HTML and field drafts across widths and guards both previews',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
        capabilities: {AuthorizationCapabilities.formsWrite: true},
      );
      addTearDown(() => RightsService.occasionLinkModelNotifier.value = null);
      final field = FormFieldDraft(id: 4, type: 'text', title: 'Poznámka');
      await _environment.pumpWidget(
        tester,
        MaterialApp(
          builder: DependencyMaterialBridge.builder,
          home: FormEditorContent(
            formLink: 'ples',
            loadBundle: (_) async => FormEditBundle(form: FormEditorDraft(
              link: 'ples',
              occasionId: 1,
              header: '<p>Vítejte na plese</p>',
              relatedFields: [field],
              data: {},
            ), productTypes: [], products: [], availableBankAccounts: []),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final outline = find.byKey(const ValueKey('form-editor-outline'));
      final header = find.byKey(const ValueKey('form-header'));
      final generatorState = tester.state(find.byType(FormFieldsGenerator));
      final headerState = tester.state(header);
      final save = find.descendant(
        of: find.byType(EditorActionBar),
        matching: find.widgetWithText(FilledButton, CommonStrings.save),
      );
      expect(outline, findsOneWidget);
      expect(
        tester.getTopLeft(find.text(FormStrings.formOpenMessage)).dy,
        lessThan(tester.getTopLeft(header).dy),
      );
      expect(
        tester.getTopLeft(header).dy,
        lessThan(tester.getTopLeft(find.byType(FormFieldsGenerator)).dy),
      );
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      final outlineField = find.descendant(
        of: outline,
        matching: find.text('Poznámka'),
      );
      await tester.tap(outlineField);
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      final title = find.widgetWithText(TextFormField, 'Poznámka');
      await tester.ensureVisible(title);
      await tester.enterText(title, 'Doprovod');
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: outline, matching: find.text('Doprovod')),
        findsOneWidget,
      );
      await tester.ensureVisible(header);
      await tester.tap(
        find.descendant(of: header, matching: find.byIcon(Icons.edit)),
      );
      await tester.pumpAndSettle();
      final rich = find.descendant(
        of: header,
        matching: find.byType(RichHtmlEditor),
      );
      final controller = tester.widget<RichHtmlEditor>(rich).controller;
      final node = controller.editor.document.first as TextNode;
      controller.editor.execute([
        InsertTextRequest(
          documentPosition: DocumentPosition(
            nodeId: node.id,
            nodePosition: TextNodePosition(offset: node.text.length),
          ),
          textToInsert: ' - těšíme se na Vás',
          attributions: {},
        ),
      ]);
      await tester.pumpAndSettle();
      final draftHtml = controller.html;
      for (final width in [390.0, 1099.0, 1600.0]) {
        tester.view.physicalSize = Size(width, 1800);
        await tester.pumpAndSettle();
        expect(outline, width < 1100 ? findsNothing : findsOneWidget);
        expect(tester.state(header), same(headerState));
        expect(
          tester.state(find.byType(FormFieldsGenerator)),
          same(generatorState),
        );
        expect(
          tester.widget<RichHtmlEditor>(rich).controller,
          same(controller),
        );
        expect(controller.html, draftHtml);
        expect(field.definition.title, 'Doprovod');
        expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
        expect(tester.takeException(), isNull);
      }
      for (final label in [FormStrings.formPreview, FormStrings.publicPage]) {
        final action = find.text(label);
        await tester.ensureVisible(action);
        await tester.tap(action);
        await tester.pumpAndSettle();
        expect(
          find.text(SaleOpeningStrings.text('unsavedChanges')),
          findsOneWidget,
        );
        await tester.tap(find.text(CommonStrings.keepEditing));
        await tester.pumpAndSettle();
        expect(controller.html, draftHtml);
      }
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      tester.view.physicalSize = const Size(1100, 1800);
      await tester.pumpAndSettle();
      expect(outline, findsNothing);
      expect(controller.html, draftHtml);
      expect(tester.takeException(), isNull);
    },
  );
  for (final mode in ['read-only', 'prototype', 'embedded']) {
    testWidgetsWithEnvironment(
      () => _environment,
      'layout C retains the $mode shell and permissions',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 1800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        RightsService.occasionLinkModelNotifier.value = null;
        final bundle = FormEditBundle(form: FormEditorDraft(
          link: 'ples',
          occasionId: 1,
          relatedFields: [
            FormFieldDraft(id: 4, type: 'text', title: 'Poznámka'),
          ],
          data: {},
        ), productTypes: [], products: [], availableBankAccounts: []);
        await _environment.pumpWidget(
          tester,
          MaterialApp(
            builder: DependencyMaterialBridge.builder,
            home: mode == 'read-only'
                ? FormEditorContent(
                    formLink: 'ples',
                    loadBundle: (_) async => bundle,
                  )
                : Scaffold(
                    body: SingleChildScrollView(
                      child: SizedBox(
                        height: 1500,
                        child: FormEditorContent.prototype(
                          bundle: bundle,
                          embedded: mode == 'embedded',
                          onPrototypeSave: (_) {},
                        ),
                      ),
                    ),
                  ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(FormFieldsGenerator), findsOneWidget);
        expect(find.byType(FloatingActionButton), findsNothing);
        if (mode == 'read-only') {
          expect(
            tester
                .widget<EditableHtmlField>(
                  find.byKey(const ValueKey('form-header')),
                )
                .enabled,
            isFalse,
          );
          expect(
            tester
                .widget<FormFieldsGenerator>(find.byType(FormFieldsGenerator))
                .editingEnabled,
            isFalse,
          );
        } else {
          expect(find.text(FormStrings.formPreview), findsNothing);
          expect(find.text(FormStrings.publicPage), findsNothing);
          expect(find.byType(EditorActionBar), findsNothing);
          if (mode == 'embedded') {
            expect(
              find.byKey(const ValueKey('form-editor-outline')),
              findsNothing,
            );
            expect(find.byType(BottomAppBar), findsNothing);
          }
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgetsWithEnvironment(
    () => _environment,
    'responses read each source once and refresh once on tab return',
    (tester) async {
      var fieldsReads = 0, ordersReads = 0;
      final form = FormEditorDraft(
        id: 1,
        link: 'selected',
        title: 'Selected',
        waitlistEnabled: true,
        capacity: FormCapacityModel.fromJson({
          'enabled': true,
          'limit': 46,
          'occupiedPeople': 5,
          'waitingPeople': 0,
          'remainingPublic': 41,
        }),
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
      // Responses start directly with the grid, even for capacity-limited forms.
      expect(
        tester
            .getTopLeft(find.byType(SingleTableDataGrid<FormResponseModel>))
            .dy,
        0,
      );
      expect(find.textContaining('Obsazenost:'), findsNothing);
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
    'product group edits update the actual Save button and revert cleanly',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
        capabilities: {AuthorizationCapabilities.formsWrite: true},
        occasionUser: OccasionUserModel(isEditorOrder: true),
      );
      addTearDown(() => RightsService.occasionLinkModelNotifier.value = null);
      final product = ProductModel(
        id: 10,
        title: 'Bez odvozu',
        price: 0,
        currencyCode: 'CZK',
        isHidden: false,
      );
      final group = ProductTypeModel(
        id: 3,
        title: 'Odvoz',
        products: [product],
      );
      final field = FormFieldDraft(
        id: 5,
        title: 'Odvoz',
        type: 'product_type',
        productType: group,
        isTicketField: true,
        isRequired: false,
        isHidden: false,
        data: {},
      );
      final form = FormEditorDraft(
        occasionId: 1,
        link: 'test',
        relatedFields: [
          FormFieldDraft(id: 4, type: 'ticket', data: {'max_tickets': 1}),
          field,
        ],
      );
      await _environment.pumpWidget(
        tester,
        MaterialApp(
          builder: DependencyMaterialBridge.builder,
          home: FormEditorContent(
            formLink: 'test',
            loadBundle: (_) async => FormEditBundle(
              form: form,
              productTypes: [group],
              products: [product],
              availableBankAccounts: [],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final save = find.widgetWithText(FilledButton, 'Common.save'.tr());
      void expectSave(bool enabled) => expect(
        tester.widget<FilledButton>(save).onPressed,
        enabled ? isNotNull : isNull,
      );
      Future<void> editAndRestore(
        Finder input,
        String changed,
        String original,
      ) async {
        await tester.ensureVisible(input);
        await tester.enterText(input, changed);
        await tester.pumpAndSettle();
        expectSave(true);
        await tester.enterText(input, original);
        await tester.pumpAndSettle();
        expectSave(false);
      }

      expectSave(false);
      final row = find.byType(TicketProductEditorRow);
      Finder productInput(String label) => find.descendant(
        of: row,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is TextField && widget.decoration?.labelText == label,
        ),
      );
      await editAndRestore(productInput('Název'), 'Žimrovice', 'Bez odvozu');
      await editAndRestore(productInput('Cena'), '150', '0');
      await editAndRestore(
        find.byWidgetPredicate(
          (widget) =>
              widget is TextField &&
              widget.decoration?.labelText == FormStrings.productTypeTitle,
        ),
        'Doprava domů',
        'Odvoz',
      );
      final groupEditor = find.byType(ProductTypeEditor);
      final toggles = find.descendant(
        of: groupEditor,
        matching: find.byWidgetPredicate(
          (widget) => widget is Switch || widget is Checkbox,
        ),
      );
      for (var i = 0; i < toggles.evaluate().length; i++) {
        await tester.ensureVisible(toggles.at(i));
        await tester.tap(toggles.at(i));
        await tester.pumpAndSettle();
        expectSave(true);
        await tester.tap(toggles.at(i));
        await tester.pumpAndSettle();
        expectSave(false);
      }
      final defaultChoice = find.descendant(
        of: groupEditor,
        matching: find.byType(Radio<String>),
      );
      await tester.ensureVisible(defaultChoice);
      await tester.tap(defaultChoice);
      await tester.pumpAndSettle();
      expectSave(true);
      await tester.tap(defaultChoice);
      await tester.pumpAndSettle();
      expectSave(false);
      expect(tester.takeException(), isNull);
    },
  );
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
      final savedEmbedStyles = <bool>[];
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
              savedEmbedStyles.add(draft.definition.embedInheritStyle);
              return FormEditorDraft(
                aggregateVersion: draft.aggregateVersion + 1,
              )..definition = draft.definition;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (var i = 0; i < 2; i++) {
        await tester.tap(
          find.byKey(const ValueKey('form-embed-inherit-style')),
        );
        await tester.pumpAndSettle();
        final save = find.widgetWithText(FilledButton, 'Common.save'.tr());
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(tester.widget<FilledButton>(save).onPressed, isNull);
      }
      expect(savedVersions, [3, 4]);
      expect(savedEmbedStyles, [false, true]);
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
            await tester.tap(
              find.byKey(const ValueKey('form-embed-inherit-style')),
            );
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
                .widget<SwitchListTile>(
                  find.byKey(const ValueKey('form-embed-inherit-style')),
                )
                .value,
            true,
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
