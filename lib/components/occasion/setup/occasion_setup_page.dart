import 'package:fstapp/widgets/app_dialog.dart';
import 'dart:async';
import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/styles/styles_config.dart';
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
import 'package:fstapp/widgets/time_data_range_picker.dart';

import 'occasion_form_draft.dart';
import 'package:fstapp/components/forms/db_forms.dart';
import 'package:fstapp/components/features/ticket_feature.dart';
import 'package:fstapp/components/features/feature_constants.dart';
import 'package:fstapp/components/ticket_layout/views/ticket_settings.dart';
import 'package:fstapp/components/_shared/editor_draft_scope.dart';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/services/dialog_helper.dart';
import 'occasion_setup_draft.dart';
import 'occasion_setup_strings.dart';
import 'package:fstapp/services/exception_handler.dart';

List<String> get _steps => [
      'Zdroj',
      'Základ',
      AppConfig.isAppSupported ? 'Common.content'.tr() : 'Vstupenka',
      'FeatureForm.title'.tr(),
      AppConfig.isAppSupported ? CommonStrings.blueprint : 'Nastavení plateb',
      'Kontrola',
      CommonStrings.blueprint,
    ];

class OccasionSetupPage extends StatefulWidget {
  final OccasionSetupDraft draft;
  const OccasionSetupPage({super.key, required this.draft});
  static Future<void> open(
      BuildContext context, OccasionSetupDraft draft) async {
    final initialized = await ExceptionHandler.guard(context,
        futureFunction: () => OccasionSetupDrafts(Supabase.instance.client)
            .initializeDefaults(draft));
    if (initialized == null || !context.mounted) return;
    await Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) => OccasionSetupPage(draft: initialized)));
  }

  @override
  State<OccasionSetupPage> createState() => _OccasionSetupPageState();
}

class _OccasionSetupPageState extends State<OccasionSetupPage> {
  final _store = OccasionSetupDrafts(Supabase.instance.client);
  late OccasionSetupDraft _stored;
  late Map<String, dynamic> _data;
  late TextEditingController _linkController;
  int _editEpoch = 0;
  int _formEpoch = 0;
  TicketFeature? _ticketFeature;
  FormEditBundle? _inlineFormBundle;
  List<Map<String, dynamic>> _sources = [];
  String? _sourceError;
  bool _loadingSources = true;
  Timer? _debounce;
  Future<bool>? _pending;
  bool _dirty = false;
  bool _allowPop = false;
  bool _conflict = false;
  String? _error;
  Map<String, dynamic>? get _active => _data;

  @override
  void initState() {
    super.initState();
    _stored = widget.draft;
    _data = {
      'id': _stored.id,
      'title': '',
      'link': '',
      'start': _stored.data['start_time'] ??
          DateTime.now().add(const Duration(days: 30)).toIso8601String(),
      'end': _stored.data['end_time'] ??
          DateTime.now().add(const Duration(days: 33)).toIso8601String(),
      'source': 'Od nuly',
      'linkManuallyChanged': false,
      'copyProgram': false,
      'copyInformation': false,
      'copyEmails': false,
      'formEnabled': true,
      'formOrigin': null,
      'formDraft': null,
      'bank': 'Automaticky podle měny',
      'deadline': '7',
      'reminders': false,
      'tone': 'FeatureFormSettings.toneInherit'
          .tr(namedArgs: {'tone': 'FeatureFormSettings.toneFormal'.tr()}),
      'blueprintMode': 'Bez plánku',
      'blueprintObjects': <Map<String, dynamic>>[],
      'blueprintGroups': <Map<String, dynamic>>[],
      'blueprintWidth': 12,
      'blueprintHeight': 8,
      'reviewed': false,
      'reviewConfirmed': false,
      'completed': <int>[],
      ..._stored.data,
      'step': _stored.data['step'] ?? 0,
    };
    _ensureDefaultForm(_data);
    _restrictToSupportedFeatures(_data);
    _linkController = TextEditingController(text: _data['link'] as String);
    _loadSources();
  }

  Future<void> _loadSources() async {
    if (mounted) {
      setState(() {
        _loadingSources = true;
        _sourceError = null;
      });
    }
    try {
      final rows = await Supabase.instance.client.rpc(
          'get_occasion_setup_sources',
          params: {'p_unit': _data['sourceUnitId'] ?? _stored.unit});
      if (mounted) {
        setState(() {
          _sources =
              (rows as List).map((r) => Map<String, dynamic>.from(r)).toList();
        });
        if (_data['sourceId'] != null &&
            _data['sourceSelectionPending'] != true) {
          final source = _sources
              .where((s) => (s['occasion'] as Map)['id'] == _data['sourceId'])
              .firstOrNull;
          if (source != null) {
            _change((x) => x['source'] = _sourceLabel(source));
          }
        }
        if (_data['sourceSelectionPending'] == true) {
          final selected = _sources
              .where((s) => (s['occasion'] as Map)['id'] == _data['sourceId'])
              .firstOrNull;
          if (selected != null) {
            _change((x) {
              _applySource(x, _sourceLabel(selected));
              x.remove('sourceSelectionPending');
            });
          }
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() => _sourceError = 'Předlohy se nepodařilo načíst.');
      }
    } finally {
      if (mounted) setState(() => _loadingSources = false);
    }
  }

  String _sourceLabel(Map<String, dynamic> source) {
    final o = source['occasion'] as Map;
    final date = DateTime.tryParse(o['start_time'] as String? ?? '');
    final formatted = date == null
        ? ''
        : DateFormat.yMd(context.locale.toString()).format(date);
    return '${o['title']} ($formatted)';
  }

  List<FormModel> get _sourceForms => [
        for (final source in _sources)
          for (final raw in source['forms'] as List)
            FormModel.fromJson(Map<String, dynamic>.from(raw))
              ..occasionModel = OccasionModel.fromJson(
                  Map<String, dynamic>.from(source['occasion']))
      ];

  void _ensureDefaultForm(Map<String, dynamic> draft) {
    final existing = draft['formDraft'];
    if (existing is Map &&
        (draft['formDefaultsInitialized'] == true ||
            (existing['fields'] as List? ?? []).isNotEmpty)) {
      draft['formDefaultsInitialized'] = true;
      return;
    }
    draft['formDefaultsInitialized'] = true;
    draft['formDraft'] = serializeDraftForm(defaultDraftForm(
        Map<String, dynamic>.from(draft['defaultConfiguration'] as Map)));
    draft['formDefaultsFollowEvent'] = true;
    _adoptFormSettings(draft);
  }

  void _restrictToSupportedFeatures(Map<String, dynamic> draft) {
    if (AppConfig.isAppSupported) return;
    final version = draft['ticketFlowVersion'] as int? ?? 0;
    if (version < 4) {
      draft['ticketFlowVersion'] = 4;
      if (version < 2) (draft['completed'] as List? ?? []).remove(4);
      if (version < 3) (draft['completed'] as List? ?? []).remove(2);
      (draft['completed'] as List? ?? []).remove(5);
      if (version < 3 && draft['step'] == 2) draft['step'] = 3;
      draft['reviewed'] = false;
      draft['reviewConfirmed'] = false;
    }
    draft['formEnabled'] = true;
    draft['copyProgram'] = false;
    draft['copyInformation'] = false;
    draft['copyEmails'] = false;
    draft.remove('sourceProgram');
    draft.remove('sourceInformation');
  }

  void _applySource(Map<String, dynamic> draft, String label) {
    _ticketFeature = null;
    _inlineFormBundle = null;
    _formEpoch++;
    draft.remove('ticketDraft');
    draft['formDefaultsFollowEvent'] = label == 'Od nuly';
    draft['source'] = label;
    draft['copyProgram'] = false;
    draft['copyInformation'] = false;
    draft['copyEmails'] = false;
    draft['sourceId'] = null;
    draft['formDraft'] = null;
    draft['formOrigin'] = null;
    draft['blueprintObjects'] = <Map<String, dynamic>>[];
    draft['blueprintGroups'] = <Map<String, dynamic>>[];
    draft['blueprintBackground'] = null;
    draft['blueprintMode'] = 'Bez plánku';
    draft['sourceProgram'] = <dynamic>[];
    draft['sourceInformation'] = <dynamic>[];
    draft['completed'] = <int>[];
    if (label == 'Od nuly') {
      _ensureDefaultForm(draft);
      return;
    }
    final source = _sources.firstWhere((s) => _sourceLabel(s) == label);
    draft['sourceId'] = (source['occasion'] as Map)['id'];
    final ticket = ((source['occasion'] as Map)['features'] as List? ?? [])
        .whereType<Map>()
        .where((f) => f['code'] == FeatureConstants.ticket)
        .firstOrNull;
    if (ticket != null) draft['ticketDraft'] = jsonDecode(jsonEncode(ticket));
    if (AppConfig.isAppSupported) {
      draft['sourceProgram'] = source['program'];
      draft['sourceInformation'] = source['information'];
      draft['copyProgram'] = (source['program'] as List).isNotEmpty;
      draft['copyInformation'] = (source['information'] as List).isNotEmpty;
    }
    final forms = source['forms'] as List;
    if (forms.isNotEmpty) {
      draft['formDraft'] = jsonDecode(jsonEncode(forms.first));
      draft['formOrigin'] = (source['occasion'] as Map)['title'];
      draft['formEnabled'] = true;
      _adoptFormSettings(draft);
    }
    final plans = source['blueprints'] as List;
    final selectedForm = forms.isEmpty ? null : forms.first as Map;
    final selected = plans
        .where((p) => (p as Map)['id'] == selectedForm?['blueprint'])
        .firstOrNull;
    if (selected is Map) _applyBlueprint(draft, selected);
    _ensureDefaultForm(draft);
  }

  void _adoptFormSettings(Map<String, dynamic> draft) {
    final form = draft['formDraft'] as Map?;
    if (form == null) return;
    final seconds = form['deadline_duration_seconds'] as num?;
    draft['deadline'] =
        seconds == null ? '7' : (seconds / 86400).round().toString();
    final data = form['data'] as Map? ?? {};
    draft['reminders'] = data[FormModel.metaIsReminderEnabled] == true;
    final tone = data[FormHelper.metaCommunicationTone];
    draft['tone'] = tone == 'formal'
        ? 'FeatureFormSettings.toneFormal'.tr()
        : tone == 'informal'
            ? 'FeatureFormSettings.toneInformal'.tr()
            : 'FeatureFormSettings.toneInherit'
                .tr(namedArgs: {'tone': 'FeatureFormSettings.toneFormal'.tr()});
  }

  void _persistFormControls(Map<String, dynamic> draft) {
    final form = draft['formDraft'];
    if (form is! Map) return;
    final days = int.tryParse(draft['deadline'] as String? ?? '');
    if (days != null && days > 0) {
      form['deadline_duration_seconds'] = days * 86400;
    }
    final data = Map<String, dynamic>.from(form['data'] as Map? ?? {});
    data[FormModel.metaIsReminderEnabled] = draft['reminders'] == true;
    final tone = draft['tone'];
    if (tone == 'FeatureFormSettings.toneFormal'.tr()) {
      data[FormHelper.metaCommunicationTone] = 'formal';
    } else if (tone == 'FeatureFormSettings.toneInformal'.tr()) {
      data[FormHelper.metaCommunicationTone] = 'informal';
    } else {
      data.remove(FormHelper.metaCommunicationTone);
    }
    form['data'] = data;
  }

  void _applyBlueprint(Map<String, dynamic> draft, Map plan) {
    draft['blueprintMode'] = 'Převzít';
    draft['blueprintObjects'] = jsonDecode(jsonEncode(plan['objects'] ?? []));
    draft['blueprintGroups'] = jsonDecode(jsonEncode(plan['groups'] ?? []));
    final dimensions = (plan['configuration'] as Map?)?['dimensions'] as Map?;
    draft['blueprintWidth'] = dimensions?['width'] ?? 12;
    draft['blueprintHeight'] = dimensions?['height'] ?? 8;
    draft['blueprintBackground'] = plan['background_svg'];
    draft['blueprintTitle'] = plan['title'];
  }

  void _save() {
    _dirty = true;
    _debounce?.cancel();
    if (!_conflict && _error == null) {
      _debounce = Timer(const Duration(milliseconds: 600), _flush);
    }
  }

  void _change(void Function(Map<String, dynamic>) update,
      {bool changesConfiguration = false}) {
    setState(() {
      final oldTitle = _data['title'];
      final oldLink = _data['link'];
      update(_data);
      if (_data['formDefaultsFollowEvent'] == true &&
          _data['formDraft'] is Map) {
        final form = _data['formDraft'] as Map;
        if (_data['title'] != oldTitle &&
            (_data['title'] as String).isNotEmpty) {
          form['title'] = _data['title'];
          _inlineFormBundle?.form.title = _data['title'];
        }
        if (_data['link'] != oldLink && (_data['link'] as String).isNotEmpty) {
          form['link'] = _data['link'];
          _inlineFormBundle?.form.link = _data['link'];
        }
      }
      _restrictToSupportedFeatures(_data);
      if (changesConfiguration) _persistFormControls(_data);
      if (changesConfiguration) {
        _data['reviewed'] = false;
        _data['reviewConfirmed'] = false;
        (_data['completed'] as List).remove(5);
        for (final step
            in OccasionSetupDraft.supportedSteps.where((s) => s != 5)) {
          if (!_stepReady(_data, step)) {
            (_data['completed'] as List).remove(step);
          }
        }
      }
      _save();
    });
  }

  Future<bool> _flush() {
    _debounce?.cancel();
    if (_pending != null) return _pending!;
    if (_conflict) return Future.value(false);
    final operation = _drain();
    _pending = operation;
    if (mounted) setState(() {});
    return operation.whenComplete(() {
      _pending = null;
      if (mounted) setState(() {});
    });
  }

  Future<bool> _drain() async {
    while (_dirty) {
      _restrictToSupportedFeatures(_data);
      final snapshot = Map<String, dynamic>.from(jsonDecode(jsonEncode(_data)));
      _dirty = false;
      try {
        _stored = await _store.save(_stored, snapshot, snapshot['step'] as int);
        _error = null;
      } catch (e) {
        _dirty = true;
        _conflict = e is PostgrestException && e.code == '40001';
        _error = _conflict
            ? OccasionSetupStrings.conflict
            : OccasionSetupStrings.saveFailed;
        return false;
      }
    }
    return true;
  }

  Future<void> _leave() async {
    // Also persist the normalized full payload for an untouched new draft.
    _dirty = true;
    if (!await _flush() || !mounted) return;
    setState(() => _allowPop = true);
    Navigator.of(context).pop();
  }

  Future<void> _reload() async {
    final confirmed = await DialogHelper.showConfirmationDialog(context,
        OccasionSetupStrings.reload, OccasionSetupStrings.reloadConfirm);
    if (confirmed != true || !mounted) return;
    try {
      final rows = await _store.list(_stored.unit);
      final current = rows.firstWhere((d) => d.id == _stored.id);
      if (!mounted) return;
      setState(() {
        _stored = current;
        _data = Map.of(current.data);
        _inlineFormBundle = null;
        _ensureDefaultForm(_data);
        _restrictToSupportedFeatures(_data);
        _linkController.text = _data['link'] as String? ?? '';
        _editEpoch++;
        _formEpoch++;
        _ticketFeature = null;
        _dirty = false;
        _conflict = false;
        _error = null;
      });
    } catch (_) {
      if (mounted) setState(() => _error = OccasionSetupStrings.saveFailed);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _linkController.dispose();
    super.dispose();
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
        return AppConfig.isAppSupported
            ? _blueprintReady(d)
            : _paymentsReady(d);
      case 6:
        return _blueprintReady(d);
      default:
        return false;
    }
  }

  bool _blueprintReady(Map<String, dynamic> d) =>
      d['blueprintMode'] == 'Bez plánku' ||
      (d['formEnabled'] == true && (d['blueprintObjects'] as List).isNotEmpty);

  bool _paymentsReady(Map<String, dynamic> d) =>
      (int.tryParse(d['deadline'] as String? ?? '') ?? 0) > 0;

  int _progress(Map<String, dynamic> d) {
    return ((OccasionSetupDraft.completedCount(d) /
                OccasionSetupDraft.supportedSteps.length) *
            100)
        .round();
  }

  void _advance() {
    final d = _active!;
    final step = d['step'] as int;
    if (step == 5) return;
    if (!_stepReady(d, step)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(step == 3
              ? 'Založ nebo převezmi formulář a doplň jeho pole.'
              : step == 6
                  ? 'V editoru plánku přidej alespoň jedno místo.'
                  : step == 4
                      ? (AppConfig.isAppSupported
                          ? 'V editoru plánku přidej alespoň jedno místo.'
                          : 'Doplň splatnost jako kladný počet dní.')
                      : 'Doplň povinné údaje tohoto kroku.')));
      return;
    }
    _change((x) {
      if (!(x['completed'] as List).contains(step)) {
        (x['completed'] as List).add(step);
      }
      final steps = OccasionSetupDraft.supportedSteps;
      x['step'] = steps[steps.indexOf(step) + 1];
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
    for (final step in OccasionSetupDraft.supportedSteps.where((s) => s != 5)) {
      if (!_stepReady(d, step)) {
        setState(() => d['step'] = step);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ještě dokonči krok ${_steps[step]}.')));
        return;
      }
    }
    _change((x) {
      x['completed'] = OccasionSetupDraft.supportedSteps;
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
              x['blueprintBackground'] = saved.backgroundSvg;
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
    final formData = d['formDraft'];
    final products = formData is Map
        ? draftFormBundle(Map<String, dynamic>.from(formData)).products
        : <ProductModel>[];
    for (final obj in objects) {
      obj.product = products.where((p) => p.id == obj.spotProduct).firstOrNull;
    }
    for (final group in groups) {
      group.product = group.objects
          .map((o) => o.product)
          .whereType<ProductModel>()
          .firstOrNull;
    }
    final plan = BlueprintModel(
      title: d['blueprintTitle'] as String? ?? 'Plán sálu',
      backgroundSvg: d['blueprintBackground'] as String?,
      configuration: BlueprintConfiguration(
          width: d['blueprintWidth'] as int,
          height: d['blueprintHeight'] as int),
      objects: objects,
      groups: groups,
      products: products,
    );
    plan.assignAllSpotsWithBlueprint();
    return plan;
  }

  Widget _card(Widget child) => Card(
      semanticContainer: false,
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 0,
      child: Padding(padding: const EdgeInsets.all(18), child: child));

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
            if (keyName == 'source') _applySource(x, v!);
            if (keyName == 'blueprintMode' && v == 'Nový') {
              x['blueprintObjects'] = <Map<String, dynamic>>[];
              x['blueprintGroups'] = <Map<String, dynamic>>[];
              x['blueprintBackground'] = null;
              x['blueprintWidth'] = 12;
              x['blueprintHeight'] = 8;
            }
            if (keyName == 'blueprintMode' && v == 'Převzít') {
              final source = _sources
                  .where((s) => (s['occasion'] as Map)['id'] == x['sourceId'])
                  .firstOrNull;
              final plans = source?['blueprints'] as List? ?? [];
              if (plans.isNotEmpty) _applyBlueprint(x, plans.first as Map);
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
        builder: (context) => AppAlertDialog(
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
      builder: (context) => CreateOrCopyFormDialog(existingForms: _sourceForms),
    );
    if (!mounted || result == null) return;
    final form = result is FormModel
        ? result
        : defaultDraftForm(
            Map<String, dynamic>.from(_data['defaultConfiguration'] as Map));
    _change((draft) {
      _formEpoch++;
      _inlineFormBundle = null;
      draft['formDefaultsFollowEvent'] = false;
      draft['formDraft'] = serializeDraftForm(form);
      _adoptFormSettings(draft);
      draft['formOrigin'] =
          result is FormModel ? form.occasionModel?.title : null;
      if (result is FormModel && form.blueprint != null) {
        for (final source in _sources) {
          final plans = source['blueprints'] as List;
          final selected = plans
              .where((p) => (p as Map)['id'] == form.blueprint)
              .firstOrNull;
          if (selected is Map) _applyBlueprint(draft, selected);
        }
      }
    }, changesConfiguration: true);
  }

  Widget _formTextField(
      Map<String, dynamic> draft, String field, String label) {
    final form = Map<String, dynamic>.from(draft['formDraft'] as Map);
    return TextFormField(
      key: ValueKey('${draft['id']}-form-$_formEpoch-$field'),
      initialValue: form[field] as String? ?? '',
      decoration: InputDecoration(labelText: label),
      onChanged: (value) => _change((x) {
        x['formDefaultsFollowEvent'] = false;
        (x['formDraft'] as Map)[field] = value;
        if (field == 'title') _inlineFormBundle?.form.title = value;
        if (field == 'link') _inlineFormBundle?.form.link = value;
      }, changesConfiguration: true),
    );
  }

  Widget _basics(Map<String, dynamic> d) {
    final start = DateTime.tryParse(d['start'] as String);
    final end = DateTime.tryParse(d['end'] as String);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TextFormField(
        key: ValueKey('${d['id']}-title-$_editEpoch'),
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
            _linkController.text = x['link'] as String;
          }
        }, changesConfiguration: true),
      ),
      const SizedBox(height: 14),
      TextFormField(
        key: ValueKey('${d['id']}-link-$_editEpoch'),
        controller: _linkController,
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
        issues.add(MapEntry(
            AppConfig.isAppSupported ? 4 : 6, 'Plánek potřebuje formulář.'));
      }
      if ((d['blueprintObjects'] as List).isEmpty) {
        issues.add(MapEntry(AppConfig.isAppSupported ? 4 : 6,
            'Plánek zatím nemá žádná místa.'));
      }
    }
    if (!AppConfig.isAppSupported && !_paymentsReady(d)) {
      issues.add(const MapEntry(4, 'Splatnost musí být kladný počet dní.'));
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
          if (step != 5)
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
          '${OccasionSetupDraft.supportedSteps.length - 1 - issues.map((issue) => issue.key).toSet().length} z ${OccasionSetupDraft.supportedSteps.length - 1} nastavení bez chyby · ${OccasionSetupDraft.completedCount(d)} z ${OccasionSetupDraft.supportedSteps.length} kroků potvrzeno${d['reviewed'] == true ? '' : ' · čeká finální kontrola'}'),
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
      if (AppConfig.isAppSupported)
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
              if (AppConfig.isAppSupported) ...[
                _reviewRow('BankAccount.bankAccount'.tr(), d['bank'] as String),
                _reviewRow('FeatureFormSettings.labelDeadlineDays'.tr(),
                    '${d['deadline']}'),
                _reviewRow('FeatureFormSettings.labelEnableReminders'.tr(),
                    d['reminders'] == true ? 'Zapnuto' : 'Vypnuto'),
                _reviewRow('FeatureFormSettings.labelCommunicationTone'.tr(),
                    d['tone'] as String),
              ],
            ],
          ],
          issues),
      if (!AppConfig.isAppSupported)
        _reviewSection(
            d,
            2,
            'Vstupenka',
            [
              _reviewRow(
                  'Vzhled',
                  (d['ticketDraft'] as Map?)?['layout'] == null
                      ? 'Výchozí šablona'
                      : 'Uložený návrh'),
            ],
            issues),
      if (!AppConfig.isAppSupported)
        _reviewSection(
            d,
            4,
            'Nastavení plateb',
            [
              _reviewRow('BankAccount.bankAccount'.tr(), d['bank'] as String),
              _reviewRow('FeatureFormSettings.labelDeadlineDays'.tr(),
                  '${d['deadline']}'),
              _reviewRow('FeatureFormSettings.labelEnableReminders'.tr(),
                  d['reminders'] == true ? 'Zapnuto' : 'Vypnuto'),
              _reviewRow('FeatureFormSettings.labelCommunicationTone'.tr(),
                  d['tone'] as String),
            ],
            issues),
      _reviewSection(
          d,
          AppConfig.isAppSupported ? 4 : 6,
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
                'Před vytvořením události bude potřeba ověřit dostupnost odkazů a platební nastavení.'),
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
              _leave();
            },
            child: const Text('Uložit dokončený koncept')),
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
          if (_loadingSources) const LinearProgressIndicator(),
          if (_sourceError != null)
            TextButton(
                onPressed: _loadSources,
                child: Text('$_sourceError Zkusit znovu')),
          _choice(d, 'source', 'Zdroj', [
            'Od nuly',
            ..._sources.map(_sourceLabel),
            if (d['source'] != 'Od nuly' &&
                !_sources.any((s) => _sourceLabel(s) == d['source']))
              d['source'] as String
          ]),
          if (_sources.isEmpty && !_loadingSources && _sourceError == null)
            const Text('V této jednotce zatím nejsou žádné uložené předlohy.'),
          const Text(
              'Kopie přenese jen vybrané nastavení. Objednávky, účastníci a rezervace zůstanou ve zdroji.'),
        ]);
      case 1:
        return _basics(d);
      case 2:
        if (!AppConfig.isAppSupported) return _ticketSettings(d);
        return Column(children: [
          _switch(d, 'formEnabled', 'Registrace a prodej'),
          _switch(d, 'copyProgram',
              '${CommonStrings.schedule} a ${CommonStrings.places}'),
          _switch(d, 'copyInformation', 'FeatureInformation.information'.tr()),
          if (d['copyProgram'] == true)
            ExpansionTile(
                title: Text(
                    '${CommonStrings.schedule} · ${(d['sourceProgram'] as List? ?? []).length}'),
                children: [
                  for (final item in d['sourceProgram'] as List? ?? [])
                    ListTile(
                        title: Text((item as Map)['title']?.toString() ?? ''),
                        subtitle: Text(
                            _dateForReview(item['start_time']?.toString())))
                ]),
          if (d['copyInformation'] == true)
            ExpansionTile(
                title: Text(
                    '${'FeatureInformation.information'.tr()} · ${(d['sourceInformation'] as List? ?? []).length}'),
                children: [
                  for (final item in d['sourceInformation'] as List? ?? [])
                    ListTile(
                        title: Text((item as Map)['title']?.toString() ?? ''))
                ]),
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
            ? (_inlineFormBundle ??=
                draftFormBundle(Map<String, dynamic>.from(formData)))
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
              OutlinedButton.icon(
                onPressed: _chooseForm,
                icon: const Icon(Icons.swap_horiz),
                label: Text('FormsFeature.createNewForm'.tr()),
              ),
            ]),
          ],
          if (formBundle != null) ...[
            const SizedBox(height: 18),
            FormEditorContent.prototype(
              key: ValueKey('${d['id']}-inline-form-$_formEpoch'),
              embedded: true,
              bundle: formBundle,
              onPrototypeSave: (saved) => _change((x) {
                x['formDraft'] = serializeDraftForm(saved.form);
              }, changesConfiguration: true),
            ),
          ],
          const SizedBox(height: 14),
          if (AppConfig.isAppSupported) _paymentSettings(d),
        ]);
      case 4:
        return AppConfig.isAppSupported
            ? _blueprintSettings(d)
            : _paymentSettings(d);
      case 6:
        return _blueprintSettings(d);
      default:
        return _reviewBody(d);
    }
  }

  Widget _ticketSettings(Map<String, dynamic> d) {
    final feature = _ticketFeature ??= TicketFeature.fromJson(
        Map<String, dynamic>.from(d['ticketDraft'] as Map? ??
            {
              'code': FeatureConstants.ticket,
              'is_enabled': true,
            }));
    // Preview resources come from an authorized event; saved edits belong only
    // to this draft. The source event's feature configuration is never updated.
    final previewId = d['sourceId'] as int? ??
        (_sources.isEmpty
            ? null
            : (_sources.first['occasion'] as Map)['id'] as int);
    if (previewId == null) {
      return const Text('Pro náhled vstupenky zatím není dostupná předloha.');
    }
    return EditorDraftScope(
      onChanged: () => _change((x) => x['ticketDraft'] = feature.toJson(),
          changesConfiguration: true),
      child: TicketSettings(
        key: ValueKey('${d['id']}-ticket-$previewId-$_editEpoch'),
        feature: feature,
        occasionId: previewId,
        productEditing: false,
        borrowResourcesOnly: d['sourceId'] == null,
      ),
    );
  }

  Widget _paymentSettings(Map<String, dynamic> d) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _choice(d, 'bank', '${'BankAccount.bankAccount'.tr()} pro CZK',
            ['Automaticky podle měny']),
        const SizedBox(height: 10),
        ...[
          _textField(
              d, 'deadline', 'FeatureFormSettings.labelDeadlineDays'.tr(),
              keyboardType: TextInputType.number),
          _switch(
              d, 'reminders', 'FeatureFormSettings.labelEnableReminders'.tr()),
          _choice(
              d, 'tone', 'FeatureFormSettings.labelCommunicationTone'.tr(), [
            'FeatureFormSettings.toneInherit'.tr(namedArgs: {
              'tone': 'FeatureFormSettings.toneFormal'.tr(),
            }),
            'FeatureFormSettings.toneFormal'.tr(),
            'FeatureFormSettings.toneInformal'.tr(),
          ]),
        ],
      ]);

  Widget _blueprintSettings(Map<String, dynamic> d) {
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
        const Text('Úpravy plánku se ukládají do tohoto konceptu.'),
      ],
    ]);
  }

  Widget _stepSurface(int step, Widget child) => step == 3
      ? Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 18),
          child: child)
      : _card(child);

  Widget _wizard(Map<String, dynamic> d) {
    final step = d['step'] as int;
    return Stack(children: [
      Column(children: [
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
              Text(_error ??
                  (_pending != null || _dirty
                      ? OccasionSetupStrings.saving
                      : OccasionSetupStrings.saved)),
              if (_error != null)
                TextButton(
                    onPressed: _pending != null
                        ? null
                        : (_conflict ? _reload : _flush),
                    child: Text(_conflict
                        ? OccasionSetupStrings.reload
                        : OccasionSetupStrings.retry)),
              const SizedBox(height: 12),
              SizedBox(
                height: 40,
                child: ListView(scrollDirection: Axis.horizontal, children: [
                  for (final i in OccasionSetupDraft.supportedSteps)
                    Padding(
                      padding: const EdgeInsets.only(right: 7),
                      child: ChoiceChip(
                        label: Text(
                            '${OccasionSetupDraft.supportedSteps.indexOf(i) + 1}. ${_steps[i]}'),
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
          child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
              children: [
                Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                        maxWidth: step == 3
                            ? StylesConfig.formMaxWidth
                            : step == 5
                                ? 960
                                : 760),
                    child: _stepSurface(
                        step,
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                                '${OccasionSetupDraft.supportedSteps.indexOf(step) + 1}. ${_steps[step]}',
                                style:
                                    Theme.of(context).textTheme.headlineSmall),
                            const SizedBox(height: 18),
                            _body(d),
                          ],
                        )),
                  ),
                ),
              ]),
        ),
      ]),
      Positioned(
        left: 20,
        right: 20,
        bottom: 16,
        child: SafeArea(
          top: false,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Material(
              elevation: 8,
              shadowColor: Colors.black26,
              borderRadius: BorderRadius.circular(24),
              clipBehavior: Clip.antiAlias,
              color: Theme.of(context).cardColor,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      TextButton.icon(
                          onPressed: _pending != null ? null : _leave,
                          icon: const Icon(Icons.arrow_back),
                          label: const Text('Odejít do seznamu')),
                      if (step > 0)
                        TextButton(
                            onPressed: () => _change((x) {
                                  final steps =
                                      OccasionSetupDraft.supportedSteps;
                                  x['step'] = steps[steps.indexOf(step) - 1];
                                }),
                            child: Text(CommonStrings.back)),
                      if (step != 5)
                        ElevatedButton(
                            onPressed: _advance,
                            child: Text(CommonStrings.continueAction)),
                    ]),
              ),
            ),
          ),
        ),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: _allowPop,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _leave();
        },
        child: Scaffold(
          appBar: AppBar(title: Text(AdministrationStrings.addNewEventTitle)),
          body: _wizard(_data),
        ),
      );
}
