// PROTOTYPE: launch with `fvm flutter run -d web-server -t lib/components/occasion/prototype/occasion_setup_demo.dart`.
// This is a Flutter-only simulation. It stores mock drafts in this browser's
// localStorage, never calls Supabase, and is removed after the UX decision.
import 'dart:convert';
import 'dart:html' as html;
import 'dart:js' as js;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/components/_shared/admin_strings.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/blueprint/blueprint_configuration.dart';
import 'package:fstapp/components/blueprint/blueprint_group.dart';
import 'package:fstapp/components/blueprint/blueprint_model.dart';
import 'package:fstapp/components/blueprint/blueprint_object_model.dart';
import 'package:fstapp/components/blueprint/views/blueprint_editor_tab.dart';
import 'package:fstapp/components/eshop/models/product_model.dart';
import 'package:fstapp/components/forms/models/form_model.dart';
import 'package:fstapp/components/forms/views/create_or_copy_dialog.dart';
import 'package:fstapp/components/forms/views/form_editor_content.dart';
import 'package:fstapp/components/forms/widgets_view/form_helper.dart';
import 'package:fstapp/services/utilities_all.dart';
import 'package:fstapp/theme_config.dart';
import 'package:fstapp/widgets/time_data_range_picker.dart';

import 'occasion_form_draft.dart';

const _storageKey = 'festapp_occasion_setup_flutter_demo_v4';
List<String> get _steps => [
      'Zdroj',
      'Základ',
      'Common.content'.tr(),
      'FeatureForm.title'.tr(),
      CommonStrings.blueprint,
      'Kontrola',
    ];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();
  runApp(EasyLocalization(
    supportedLocales: const [Locale('cs')],
    path: 'assets/translations',
    fallbackLocale: const Locale('cs'),
    useOnlyLangCode: true,
    child: const OccasionSetupDemoApp(),
  ));
}

class OccasionSetupDemoApp extends StatelessWidget {
  const OccasionSetupDemoApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Festapp · Simulace průvodce',
        debugShowCheckedModeBanner: false,
        theme: ThemeConfig.theme(),
        localizationsDelegates: context.localizationDelegates,
        supportedLocales: context.supportedLocales,
        locale: context.locale,
        home: const _DemoHome(),
      );
}

class _DemoHome extends StatefulWidget {
  const _DemoHome();

  @override
  State<_DemoHome> createState() => _DemoHomeState();
}

class _DemoHomeState extends State<_DemoHome> {
  List<Map<String, dynamic>> _drafts = [];
  String? _activeId;

  @override
  void initState() {
    super.initState();
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      js.context.callMethod('markFestappAppReady');
    });
  }

  void _load() {
    try {
      final raw = html.window.localStorage[_storageKey];
      if (raw != null) {
        _drafts = (jsonDecode(raw) as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        return;
      }
    } catch (_) {
      // The demo still works in memory if browser storage is disabled.
    }
    _drafts = [_newDraft(sample: true)];
    _save();
  }

  Map<String, dynamic> _newDraft({bool sample = false}) => {
        'id': DateTime.now().microsecondsSinceEpoch.toString(),
        'title': sample ? 'Konference 2027' : '',
        'link': sample ? 'konference2027' : '',
        'start': sample
            ? '2027-05-14T10:00:00.000'
            : DateTime.now().add(const Duration(days: 30)).toIso8601String(),
        'end': sample
            ? '2027-05-16T18:00:00.000'
            : DateTime.now().add(const Duration(days: 33)).toIso8601String(),
        'linkManuallyChanged': false,
        'source': sample ? 'Konference 2026' : 'Od nuly',
        'copyProgram': sample,
        'copyInformation': sample,
        'copyEmails': false,
        'formEnabled': true,
        'formOrigin': sample ? 'Konference 2026' : null,
        'formDraft': sample
            ? serializeDraftForm(sampleSourceForm('Konference 2026', 2026))
            : null,
        'bank': 'Automaticky podle měny',
        'deadline': '7',
        'reminders': false,
        'tone': 'FeatureFormSettings.toneInherit'.tr(namedArgs: {
          'tone': 'FeatureFormSettings.toneFormal'.tr(),
        }),
        'blueprintMode': sample ? 'Převzít' : 'Bez plánku',
        'blueprintObjects': sample ? _sampleSeats() : <Map<String, dynamic>>[],
        'blueprintGroups': [
          {'id': 1, 'title': 'A'}
        ],
        'blueprintWidth': 12,
        'blueprintHeight': 8,
        'reviewed': false,
        'reviewConfirmed': false,
        'created': false,
        'step': sample ? 2 : 0,
        'completed': sample ? [0, 1] : <int>[],
        'updated': DateTime.now().toIso8601String(),
      };

  List<Map<String, dynamic>> _sampleSeats() => [
        for (var col = 1; col <= 6; col++)
          {
            'x': col,
            'y': 2,
            'type': 'spot',
            'title': 'A$col',
            'state': 'available',
            'group': 1
          },
      ];

  Map<String, dynamic>? get _active {
    for (final draft in _drafts) {
      if (draft['id'] == _activeId) return draft;
    }
    return null;
  }

  void _save() {
    try {
      html.window.localStorage[_storageKey] = jsonEncode(_drafts);
    } catch (_) {}
  }

  void _change(void Function(Map<String, dynamic>) update,
      {bool changesConfiguration = false}) {
    final draft = _active;
    if (draft == null) return;
    setState(() {
      update(draft);
      draft['updated'] = DateTime.now().toIso8601String();
      if (changesConfiguration && draft['reviewed'] == true) {
        draft['reviewed'] = false;
        (draft['completed'] as List).remove(5);
      }
      if (changesConfiguration) {
        draft['reviewConfirmed'] = false;
        for (var step = 0; step < 5; step++) {
          if (!_stepReady(draft, step)) {
            (draft['completed'] as List).remove(step);
          }
        }
      }
      _save();
    });
  }

  void _start() {
    final draft = _newDraft();
    setState(() {
      _drafts.insert(0, draft);
      _activeId = draft['id'] as String;
      _save();
    });
  }

  bool _stepReady(Map<String, dynamic> d, int step) {
    switch (step) {
      case 0:
        return true;
      case 1:
        final start = DateTime.tryParse(d['start'] as String);
        final end = DateTime.tryParse(d['end'] as String);
        return (d['title'] as String).trim().isNotEmpty &&
            Utilities.isValidUrl(d['link'] as String) &&
            start != null &&
            end != null &&
            !end.isBefore(start);
      case 2:
        return true;
      case 3:
        if (d['formEnabled'] == false) return true;
        final formData = d['formDraft'];
        if (formData is! Map) return false;
        return (formData['title'] as String? ?? '').trim().isNotEmpty &&
            Utilities.isValidUrl(formData['link'] as String? ?? '') &&
            (formData['fields'] as List? ?? []).isNotEmpty;
      case 4:
        if (d['blueprintMode'] == 'Bez plánku') return true;
        return d['formEnabled'] == true &&
            (d['blueprintObjects'] as List).isNotEmpty;
      default:
        return false;
    }
  }

  int _progress(Map<String, dynamic> d) {
    final complete = (d['completed'] as List).cast<int>();
    return ((complete.length / _steps.length) * 100).round();
  }

  void _advance() {
    final d = _active!;
    final step = d['step'] as int;
    if (step == 5) return;
    if (!_stepReady(d, step)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(step == 3
              ? 'Založ nebo převezmi formulář a doplň jeho pole.'
              : step == 4
                  ? 'V editoru plánku přidej alespoň jedno místo.'
                  : 'Doplň povinné údaje tohoto kroku.')));
      return;
    }
    _change((x) {
      if (!(x['completed'] as List).contains(step)) {
        (x['completed'] as List).add(step);
      }
      x['step'] = step + 1;
    });
  }

  void _review() {
    final d = _active!;
    if (d['reviewConfirmed'] != true) return;
    final issues = _reviewIssues(d);
    if (issues.isNotEmpty) {
      setState(() => d['step'] = issues.first.key);
      return;
    }
    for (var step = 0; step < 5; step++) {
      if (!_stepReady(d, step)) {
        setState(() => d['step'] = step);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ještě dokonči krok ${_steps[step]}.')));
        return;
      }
    }
    _change((x) {
      x['completed'] = [0, 1, 2, 3, 4, 5];
      x['reviewed'] = true;
    });
  }

  void _openBlueprint() {
    final d = _active!;
    final plan = _planFromDraft(d);
    Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => Scaffold(
        appBar:
            AppBar(title: Text('${CommonStrings.blueprint} · návrh události')),
        body: BlueprintTab.prototype(
          prototypeBlueprint: plan,
          onPrototypeSave: (saved) {
            _change((x) {
              x['blueprintObjects'] =
                  (saved.objects ?? []).map((o) => o.toJson()).toList();
              x['blueprintGroups'] =
                  (saved.groups ?? []).map((g) => g.toJson()).toList();
              x['blueprintWidth'] = saved.configuration?.width ?? 12;
              x['blueprintHeight'] = saved.configuration?.height ?? 8;
            }, changesConfiguration: true);
          },
        ),
      ),
    ));
  }

  BlueprintModel _planFromDraft(Map<String, dynamic> d) {
    final groups = (d['blueprintGroups'] as List)
        .map((g) =>
            BlueprintGroupModel.fromJson(Map<String, dynamic>.from(g as Map)))
        .toList();
    final objects = (d['blueprintObjects'] as List)
        .map((o) =>
            BlueprintObjectModel.fromJson(Map<String, dynamic>.from(o as Map)))
        .toList();
    for (final obj in objects) {
      for (final group in groups) {
        if (obj.groupId == group.id) {
          obj.group = group;
          group.objects.add(obj);
        }
      }
    }
    final product = ProductModel(
        id: 1,
        title: 'Vstupenka se sedadlem',
        price: 690,
        currencyCode: 'CZK',
        productTypeString: ProductModel.spotType);
    for (final group in groups) {
      group.product = product;
    }
    final plan = BlueprintModel(
      title: 'Plán sálu',
      configuration: BlueprintConfiguration(
          width: d['blueprintWidth'] as int,
          height: d['blueprintHeight'] as int),
      objects: objects,
      groups: groups,
      products: [product],
    );
    plan.assignAllSpotsWithBlueprint();
    return plan;
  }

  Widget _card(Widget child) => Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 0,
      child: Padding(padding: const EdgeInsets.all(18), child: child));

  Widget _home() {
    final drafts = _drafts.where((d) => d['created'] != true).toList();
    final created = _drafts.where((d) => d['created'] == true).toList();
    return ListView(padding: const EdgeInsets.all(24), children: [
      Row(children: [
        Expanded(
            child: Text('Common.events'.tr(),
                style: Theme.of(context).textTheme.headlineMedium)),
        ElevatedButton.icon(
            onPressed: _start,
            icon: const Icon(Icons.add),
            label: Text(AdministrationStrings.newOccasionButton)),
      ]),
      const SizedBox(height: 8),
      const Text(
          'Flutter simulace · koncepty se uchovají pouze v tomto prohlížeči.'),
      const SizedBox(height: 25),
      Text('Rozpracované koncepty',
          style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 6),
      const Text('Nejsou veřejné. Kdykoliv se vrať k průvodci.'),
      const SizedBox(height: 10),
      if (drafts.isEmpty) _card(const Text('Zatím žádný koncept.')),
      for (final d in drafts)
        Card(
          elevation: 0,
          color: const Color(0xfffff5df),
          shape: RoundedRectangleBorder(
            side: const BorderSide(color: Color(0xffd59a39), width: 1.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListTile(
            leading: const Icon(Icons.edit_note, color: Color(0xff89540a)),
            title: Row(children: [
              Flexible(
                  child: Text((d['title'] as String).isEmpty
                      ? 'ActivitiesComponentStrings.textUntitledActivity'.tr()
                      : d['title'] as String)),
              const SizedBox(width: 10),
              const Chip(label: Text('KONCEPT')),
            ]),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    'Soukromý koncept · ${_progress(d)} % hotovo · poslední krok: ${_steps[d['step'] as int]}'),
                const SizedBox(height: 6),
                LinearProgressIndicator(value: _progress(d) / 100),
                const SizedBox(height: 5),
                const Text('Pokračovat v nastavení',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => setState(() => _activeId = d['id'] as String),
          ),
        ),
      const SizedBox(height: 25),
      Text('Ostatní události', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      for (final title in ['Letní slavnost 2026', 'Podzimní festival 2026'])
        _card(ListTile(
          leading: const Icon(Icons.event_available),
          title: Text(title),
          subtitle: const Text('Běžná událost'),
        )),
      for (final event in created)
        _card(ListTile(
          leading: const Icon(Icons.lock_outline),
          title: Text(event['title'] as String),
          subtitle: const Text('Vytvořená soukromá událost'),
        )),
    ]);
  }

  Widget _textField(Map<String, dynamic> d, String keyName, String label,
          {TextInputType? keyboardType}) =>
      TextFormField(
        key: ValueKey('${d['id']}-$keyName'),
        initialValue: d[keyName] as String? ?? '',
        decoration: InputDecoration(
            labelText: label, border: const OutlineInputBorder()),
        keyboardType: keyboardType,
        onChanged: (v) =>
            _change((x) => x[keyName] = v, changesConfiguration: true),
      );

  Widget _choice(Map<String, dynamic> d, String keyName, String label,
          List<String> options) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: DropdownButtonFormField<String>(
          key: ValueKey('${d['id']}-$keyName-${d[keyName]}'),
          initialValue: d[keyName] as String,
          decoration: InputDecoration(
              labelText: label, border: const OutlineInputBorder()),
          items: options
              .map((o) => DropdownMenuItem(value: o, child: Text(o)))
              .toList(),
          onChanged: (v) => _change((x) {
            x[keyName] = v;
            if (keyName == 'source' && v != 'Od nuly') {
              x['copyProgram'] = true;
              x['copyInformation'] = true;
              x['blueprintMode'] = 'Převzít';
              x['blueprintObjects'] = _sampleSeats();
            }
          }, changesConfiguration: true),
        ),
      );

  Widget _switch(Map<String, dynamic> d, String keyName, String label) =>
      SwitchListTile(
        title: Text(label),
        value: d[keyName] == true,
        onChanged: (v) =>
            _change((x) => x[keyName] = v, changesConfiguration: true),
      );

  Future<void> _chooseForm() async {
    final current = _active;
    if (current == null) return;
    if (current['formDraft'] != null) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Nahradit formulář v konceptu?'),
          content:
              const Text('Dosavadní úpravy formuláře se při výměně zahodí.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(CommonStrings.back)),
            ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text('Common.confirm'.tr())),
          ],
        ),
      );
      if (replace != true || !mounted) return;
    }
    final result = await showDialog<dynamic>(
      context: context,
      builder: (context) => CreateOrCopyFormDialog(existingForms: [
        sampleSourceForm('Konference 2026', 2026),
        sampleSourceForm('Letní slavnost 2025', 2025),
      ]),
    );
    if (!mounted || result == null) return;
    final form = result is FormModel ? result : blankDraftForm();
    _change((draft) {
      draft['formDraft'] = serializeDraftForm(form);
      draft['formOrigin'] =
          result is FormModel ? form.occasionModel?.title : null;
    }, changesConfiguration: true);
  }

  void _openForm() {
    final draft = _active;
    if (draft == null || draft['formDraft'] is! Map) return;
    final bundle =
        draftFormBundle(Map<String, dynamic>.from(draft['formDraft'] as Map));
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (context) => Scaffold(
        appBar: AppBar(title: Text('FeatureForm.title'.tr())),
        body: FormEditorContent.prototype(
          bundle: bundle,
          onPrototypeSave: (saved) => _change((x) {
            x['formDraft'] = serializeDraftForm(saved.form);
          }, changesConfiguration: true),
        ),
      ),
    ));
  }

  Widget _formTextField(
      Map<String, dynamic> draft, String field, String label) {
    final form = Map<String, dynamic>.from(draft['formDraft'] as Map);
    return TextFormField(
      key: ValueKey('${draft['id']}-form-$field'),
      initialValue: form[field] as String? ?? '',
      decoration: InputDecoration(labelText: label),
      onChanged: (value) => _change((x) {
        (x['formDraft'] as Map)[field] = value;
      }, changesConfiguration: true),
    );
  }

  Widget _basics(Map<String, dynamic> d) {
    final start = DateTime.tryParse(d['start'] as String);
    final end = DateTime.tryParse(d['end'] as String);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TextFormField(
        key: ValueKey('${d['id']}-title'),
        initialValue: d['title'] as String,
        decoration:
            InputDecoration(labelText: AdministrationStrings.titleLabel),
        onChanged: (value) => _change((x) {
          x['title'] = value;
          if (x['linkManuallyChanged'] != true && value.trim().isNotEmpty) {
            final firstWord = Utilities.removeDiacritics(value.trim())
                .split(' ')
                .first
                .toLowerCase();
            final year = DateTime.tryParse(x['end'] as String)?.year ??
                DateTime.now().year;
            x['link'] = '$firstWord$year';
          }
        }, changesConfiguration: true),
      ),
      const SizedBox(height: 14),
      TextFormField(
        key: ValueKey('${d['id']}-link-${d['link']}'),
        initialValue: d['link'] as String,
        decoration: InputDecoration(labelText: AdministrationStrings.linkLabel),
        onChanged: (value) => _change((x) {
          x['link'] = value;
          x['linkManuallyChanged'] = true;
        }, changesConfiguration: true),
      ),
      const SizedBox(height: 18),
      TimeDateRangePicker(
        start: start,
        end: end,
        minDate: DateTime(2000),
        maxDate: DateTime(2101),
        onStartChanged: (value) => _change((x) {
          x['start'] = value?.toIso8601String() ?? '';
          if (value != null && end != null && value.isAfter(end)) {
            x['end'] = value.toIso8601String();
          }
        }, changesConfiguration: true),
        onEndChanged: (value) => _change((x) {
          x['end'] = value?.toIso8601String() ?? '';
          if (value != null && start != null && value.isBefore(start)) {
            x['start'] = value.toIso8601String();
          }
        }, changesConfiguration: true),
      ),
      const SizedBox(height: 16),
      Text(AdministrationStrings.eventAvailableAt),
      SelectableText('${AppConfig.webLink}/#/${d['link']}'),
      const SizedBox(height: 14),
      _card(const Text(
          'Koncept zůstává skrytý a zavřený i po dokončení průvodce.')),
    ]);
  }

  List<MapEntry<int, String>> _reviewIssues(Map<String, dynamic> d) {
    final issues = <MapEntry<int, String>>[];
    if ((d['title'] as String).trim().isEmpty) {
      issues.add(const MapEntry(1, 'Chybí název události.'));
    }
    if (!Utilities.isValidUrl(d['link'] as String)) {
      issues.add(const MapEntry(1, 'Odkaz události není platný.'));
    }
    final start = DateTime.tryParse(d['start'] as String);
    final end = DateTime.tryParse(d['end'] as String);
    if (start == null || end == null || end.isBefore(start)) {
      issues.add(const MapEntry(1, 'Zkontroluj začátek a konec události.'));
    }
    if (d['formEnabled'] == true) {
      final formData = d['formDraft'];
      if (formData is! Map) {
        issues
            .add(const MapEntry(3, 'Chybí formulář. Založ jej nebo převezmi.'));
      } else {
        final form = draftFormBundle(Map<String, dynamic>.from(formData));
        if ((form.form.title ?? '').trim().isEmpty ||
            !Utilities.isValidUrl(form.form.link ?? '')) {
          issues
              .add(const MapEntry(3, 'Doplň název a platný odkaz formuláře.'));
        }
        if (form.form.relatedFields
            .where((field) => field.isTicketField != true)
            .isEmpty) {
          issues.add(const MapEntry(3, 'Formulář nemá žádná pole.'));
        }
        if (form.form.relatedFields
                .any((field) => field.type == FormHelper.fieldTypeTicket) &&
            form.products.isEmpty) {
          issues
              .add(const MapEntry(3, 'Formulář se vstupenkami nemá produkty.'));
        }
      }
    }
    if (d['blueprintMode'] != 'Bez plánku') {
      if (d['formEnabled'] != true || d['formDraft'] == null) {
        issues.add(const MapEntry(4, 'Plánek potřebuje formulář.'));
      }
      if ((d['blueprintObjects'] as List).isEmpty) {
        issues.add(const MapEntry(4, 'Plánek zatím nemá žádná místa.'));
      }
    }
    return issues;
  }

  String _dateForReview(String? raw) {
    final value = DateTime.tryParse(raw ?? '');
    if (value == null) return 'Neuvedeno';
    final localizations = MaterialLocalizations.of(context);
    return '${localizations.formatMediumDate(value)} ${value.year} · ${TimeOfDay.fromDateTime(value).format(context)}';
  }

  Widget _reviewRow(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: LayoutBuilder(builder: (context, constraints) {
          final labelWidget =
              Text(label, style: Theme.of(context).textTheme.bodySmall);
          if (constraints.maxWidth < 540) {
            return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [labelWidget, SelectableText(value)]);
          }
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 205, child: labelWidget),
            Expanded(child: SelectableText(value)),
          ]);
        }),
      );

  Widget _reviewSection(Map<String, dynamic> d, int step, String title,
      List<Widget> children, List<MapEntry<int, String>> issues) {
    final hasIssue = issues.any((issue) => issue.key == step) ||
        (step == 5 && d['reviewed'] != true);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(
            color: hasIssue ? const Color(0xffd59a39) : Colors.black12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(hasIssue ? Icons.error_outline : Icons.check_circle_outline,
              color: hasIssue ? const Color(0xffad721b) : Colors.green),
          const SizedBox(width: 9),
          Expanded(
              child:
                  Text(title, style: Theme.of(context).textTheme.titleMedium)),
          if (step < 5)
            TextButton.icon(
              onPressed: () => _change((x) => x['step'] = step),
              icon: const Icon(Icons.edit_outlined, size: 17),
              label: Text(CommonStrings.edit),
            ),
        ]),
        const Divider(),
        ...children,
      ]),
    );
  }

  Widget _reviewBody(Map<String, dynamic> d) {
    final issues = _reviewIssues(d);
    final formData = d['formDraft'];
    final form = formData is Map
        ? draftFormBundle(Map<String, dynamic>.from(formData))
        : null;
    final groups = d['blueprintGroups'] as List;
    final seatCount = (d['blueprintObjects'] as List).length;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Kontrola před vytvořením události',
          style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 8),
      Text(
          '${5 - issues.map((issue) => issue.key).toSet().length} z 5 nastavení bez chyby · ${(d['completed'] as List).length} z 6 kroků potvrzeno${d['reviewed'] == true ? '' : ' · čeká finální kontrola'}'),
      const SizedBox(height: 18),
      if (issues.isNotEmpty)
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xfffff5df),
            borderRadius: BorderRadius.circular(8),
          ),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Co ještě doplnit',
                style: Theme.of(context).textTheme.titleMedium),
            for (final issue in issues)
              ListTile(
                dense: true,
                leading:
                    const Icon(Icons.error_outline, color: Color(0xffad721b)),
                title: Text(issue.value),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _change((x) => x['step'] = issue.key),
              ),
          ]),
        ),
      _reviewSection(
          d,
          0,
          'Zdroj a převzetí',
          [
            _reviewRow('Zdrojová událost', d['source'] as String),
          ],
          issues),
      _reviewSection(
          d,
          1,
          'Událost',
          [
            _reviewRow(AdministrationStrings.titleLabel, d['title'] as String),
            _reviewRow(AdministrationStrings.linkLabel,
                '${AppConfig.webLink}/#/${d['link']}'),
            _reviewRow(
                CommonStrings.start, _dateForReview(d['start'] as String)),
            _reviewRow(CommonStrings.end, _dateForReview(d['end'] as String)),
          ],
          issues),
      _reviewSection(
          d,
          2,
          CommonStrings.content,
          [
            _reviewRow('FeatureForm.title'.tr(),
                d['formEnabled'] == true ? 'Zapnuto' : 'Vypnuto'),
            _reviewRow(CommonStrings.schedule,
                d['copyProgram'] == true ? 'Převzít' : 'Bez převzetí'),
            _reviewRow('FeatureInformation.information'.tr(),
                d['copyInformation'] == true ? 'Převzít' : 'Bez převzetí'),
            _reviewRow('Šablony e-mailů',
                d['copyEmails'] == true ? 'Převzít' : 'Bez převzetí'),
          ],
          issues),
      _reviewSection(
          d,
          3,
          'FeatureForm.title'.tr(),
          [
            if (d['formEnabled'] != true)
              const Text('Formulář není součástí události.')
            else if (form == null)
              const Text('Formulář ještě nebyl vytvořen.')
            else ...[
              _reviewRow(
                  'Původ',
                  d['formOrigin'] == null
                      ? 'Nový formulář'
                      : 'Kopie z události ${d['formOrigin']}'),
              _reviewRow('FeatureFormSettings.labelFormTitle'.tr(),
                  form.form.title ?? ''),
              _reviewRow('FeatureFormSettings.labelFormLink'.tr(),
                  form.form.link ?? ''),
              _reviewRow('Stav', 'Zavřený'),
              Text(
                  'Pole formuláře (${form.form.relatedFields.where((field) => field.isTicketField != true).length})',
                  style: Theme.of(context).textTheme.titleSmall),
              for (final field in form.form.relatedFields
                  .where((field) => field.isTicketField != true))
                _reviewRow(
                    field.title ??
                        FormHelper.fieldTypeToLocale(field.type ?? ''),
                    '${FormHelper.fieldTypeToLocale(field.type ?? '')} · ${field.isRequired == true ? 'povinné' : 'nepovinné'}${field.isHidden == true ? ' · skryté' : ''}${field.options.isEmpty ? '' : ' · možnosti: ${field.options.map((option) => option.title).join(', ')}'}'),
              const SizedBox(height: 6),
              Text('${CommonStrings.products} (${form.products.length})',
                  style: Theme.of(context).textTheme.titleSmall),
              if (form.products.isEmpty) const Text('Žádné produkty'),
              for (final type in form.productTypes) ...[
                Text(type.title ?? '',
                    style: Theme.of(context).textTheme.bodySmall),
                for (final product in type.products ?? <ProductModel>[])
                  _reviewRow(product.title ?? '',
                      '${product.price?.toStringAsFixed(0) ?? '0'} ${product.currencyCode ?? 'CZK'} · limit ${product.maximum?.toString() ?? 'bez limitu'}'),
              ],
              const SizedBox(height: 6),
              _reviewRow('BankAccount.bankAccount'.tr(), d['bank'] as String),
              _reviewRow('FeatureFormSettings.labelDeadlineDays'.tr(),
                  '${d['deadline']}'),
              _reviewRow('FeatureFormSettings.labelEnableReminders'.tr(),
                  d['reminders'] == true ? 'Zapnuto' : 'Vypnuto'),
              _reviewRow('FeatureFormSettings.labelCommunicationTone'.tr(),
                  d['tone'] as String),
            ],
          ],
          issues),
      _reviewSection(
          d,
          4,
          CommonStrings.blueprint,
          [
            _reviewRow('Způsob', d['blueprintMode'] as String),
            if (d['blueprintMode'] != 'Bez plánku') ...[
              _reviewRow('Rozměry',
                  '${d['blueprintWidth']} × ${d['blueprintHeight']}'),
              _reviewRow(
                  'Skupiny',
                  groups
                      .map((group) => (group as Map)['title']?.toString() ?? '')
                      .join(', ')),
              _reviewRow('Místa', '$seatCount'),
              _reviewRow(
                  'Vazba na formulář', form?.form.title ?? 'Chybí formulář'),
            ],
          ],
          issues),
      _reviewSection(
          d,
          5,
          'Soukromí a dokončení',
          [
            const Text(
                'Koncept je neveřejný. Vytvořená událost zůstane skrytá a formulář zavřený. Zveřejnění je samostatný krok.'),
            const SizedBox(height: 8),
            const Text(
                'Simulace zatím neověřuje dostupnost odkazů ani bankovní účet na serveru.'),
          ],
          issues),
      if (d['reviewed'] != true) ...[
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: d['reviewConfirmed'] == true,
          onChanged: issues.isEmpty
              ? (value) => _change((x) => x['reviewConfirmed'] = value == true)
              : null,
          title: const Text('Prošel/prošla jsem zobrazené nastavení.'),
          subtitle: const Text('Potvrzení zpřístupní dokončení kontroly.'),
        ),
        ElevatedButton.icon(
          onPressed:
              issues.isEmpty && d['reviewConfirmed'] == true ? _review : null,
          icon: const Icon(Icons.fact_check),
          label: const Text('Potvrdit kontrolu'),
        ),
      ] else ...[
        const Text(
            '100 % znamená dokončené nastavení. Koncept je stále neveřejný.'),
        const SizedBox(height: 10),
        OutlinedButton(
            onPressed: () {
              _change((x) => x['created'] = true);
              setState(() => _activeId = null);
            },
            child: const Text('Simulovat vytvoření soukromé události')),
      ],
    ]);
  }

  Widget _body(Map<String, dynamic> d) {
    switch (d['step'] as int) {
      case 0:
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Jak chceš začít?',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          _choice(d, 'source', 'Zdroj',
              ['Od nuly', 'Letní slavnost 2026', 'Konference 2026']),
          const Text(
              'Kopie přenese jen vybrané nastavení. Objednávky, účastníci a rezervace zůstanou ve zdroji.'),
        ]);
      case 1:
        return _basics(d);
      case 2:
        return Column(children: [
          _switch(d, 'formEnabled', 'Registrace a prodej'),
          _switch(d, 'copyProgram',
              '${CommonStrings.schedule} a ${CommonStrings.places}'),
          _switch(d, 'copyInformation', 'FeatureInformation.information'.tr()),
          ExpansionTile(
              title: Text('FormsFeature.additionalSettings'.tr()),
              subtitle: const Text('Šablony e-mailů a menší volby'),
              children: [
                _switch(d, 'copyEmails', 'Převzít e-mailové šablony')
              ]),
        ]);
      case 3:
        if (d['formEnabled'] == false) {
          return const Text('Formulář je vypnutý.');
        }
        final formData = d['formDraft'];
        final formBundle = formData is Map
            ? draftFormBundle(Map<String, dynamic>.from(formData))
            : null;
        final fields = formBundle?.form.relatedFields
                .where((field) => field.isTicketField != true)
                .length ??
            0;
        final products = formBundle?.products.length ?? 0;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (formBundle == null)
            ElevatedButton.icon(
              onPressed: _chooseForm,
              icon: const Icon(Icons.add),
              label: Text('FormsFeature.createNewForm'.tr()),
            )
          else ...[
            if (d['formOrigin'] != null)
              Text('Převzato z události ${d['formOrigin']}'),
            _formTextField(
                d, 'title', 'FeatureFormSettings.labelFormTitle'.tr()),
            const SizedBox(height: 10),
            _formTextField(d, 'link', 'FeatureFormSettings.labelFormLink'.tr()),
            const SizedBox(height: 10),
            Text('$fields polí · $products produktů'),
            const SizedBox(height: 12),
            Wrap(spacing: 10, children: [
              ElevatedButton.icon(
                onPressed: _openForm,
                icon: const Icon(Icons.edit_note),
                label: Text('FormsFeature.editContent'.tr()),
              ),
              OutlinedButton.icon(
                onPressed: _chooseForm,
                icon: const Icon(Icons.swap_horiz),
                label: Text('FormsFeature.createNewForm'.tr()),
              ),
            ]),
          ],
          const SizedBox(height: 14),
          _choice(d, 'bank', '${'BankAccount.bankAccount'.tr()} pro CZK',
              ['Automaticky podle měny', '123456789/0100']),
          ExpansionTile(
            title: const Text('Platební a komunikační detaily'),
            subtitle: Text('Splatnost ${d['deadline']} dní · tón ${d['tone']}'),
            children: [
              _textField(
                  d, 'deadline', 'FeatureFormSettings.labelDeadlineDays'.tr(),
                  keyboardType: TextInputType.number),
              _switch(d, 'reminders',
                  'FeatureFormSettings.labelEnableReminders'.tr()),
              _choice(d, 'tone',
                  'FeatureFormSettings.labelCommunicationTone'.tr(), [
                'FeatureFormSettings.toneInherit'.tr(namedArgs: {
                  'tone': 'FeatureFormSettings.toneFormal'.tr(),
                }),
                'FeatureFormSettings.toneFormal'.tr(),
                'FeatureFormSettings.toneInformal'.tr(),
              ]),
            ],
          ),
        ]);
      case 4:
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _choice(d, 'blueprintMode', CommonStrings.blueprint,
              ['Bez plánku', 'Nový', 'Převzít']),
          if (d['blueprintMode'] != 'Bez plánku') ...[
            Text('${(d['blueprintObjects'] as List).length} míst v plánu'),
            const SizedBox(height: 12),
            ElevatedButton.icon(
                onPressed: _openBlueprint,
                icon: const Icon(Icons.grid_on),
                label: const Text('Otevřít editor plánku')),
            const SizedBox(height: 12),
            const Text(
                'Stejný editor jako v administraci. V simulaci ukládá jen do konceptu v prohlížeči.'),
          ],
        ]);
      default:
        return _reviewBody(d);
    }
  }

  Widget _wizard(Map<String, dynamic> d) {
    final step = d['step'] as int;
    return Column(children: [
      Material(
        color: Theme.of(context).cardColor,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                  child: Text(
                      'KONCEPT · ${d['title'].toString().isEmpty ? 'ActivitiesComponentStrings.textUntitledActivity'.tr() : d['title']}',
                      style: Theme.of(context).textTheme.titleLarge)),
              Text('${_progress(d)} %'),
            ]),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: _progress(d) / 100, minHeight: 8),
            const SizedBox(height: 9),
            const Text('Koncept se průběžně ukládá v tomto prohlížeči.'),
            const SizedBox(height: 12),
            SizedBox(
              height: 40,
              child: ListView(scrollDirection: Axis.horizontal, children: [
                for (var i = 0; i < _steps.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 7),
                    child: ChoiceChip(
                      label: Text('${i + 1}. ${_steps[i]}'),
                      selected: i == step,
                      onSelected: (_) => _change((x) => x['step'] = i),
                    ),
                  ),
              ]),
            ),
          ]),
        ),
      ),
      Expanded(
        child: ListView(padding: const EdgeInsets.all(20), children: [
          Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: step == 5 ? 960 : 760),
              child: _card(Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('${step + 1}. ${_steps[step]}',
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 18),
                  _body(d),
                ],
              )),
            ),
          ),
        ]),
      ),
      Material(
        color: Theme.of(context).cardColor,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            TextButton.icon(
                onPressed: () => setState(() => _activeId = null),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Odejít do seznamu')),
            const Spacer(),
            if (step > 0)
              TextButton(
                  onPressed: () => _change((x) => x['step'] = step - 1),
                  child: Text(CommonStrings.back)),
            if (step < 5)
              ElevatedButton(
                  onPressed: _advance,
                  child: Text(CommonStrings.continueAction)),
          ]),
        ),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Festapp · Simulace založení události'),
          actions: const [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(child: Text('DEMO · bez databáze')),
            )
          ],
        ),
        body: _active == null ? _home() : _wizard(_active!),
      );
}
