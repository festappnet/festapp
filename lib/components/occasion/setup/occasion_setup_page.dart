import '../../ticket_layout/ticket_delivery_strings.dart';
import 'occasion_setup_appearance.dart';
import 'occasion_setup_appearance_panel.dart';
import 'occasion_setup_form_preview.dart';
import '../../ticket_layout/ticket_layout_service.dart';
import '../../ticket_layout/models/ticket_layout.dart';
import 'occasion_setup_blueprint.dart';
import 'occasion_setup_copy_picker.dart';
import 'occasion_setup_form_link.dart';
import 'occasion_setup_sales.dart';
import 'occasion_setup_due_settings.dart';
import 'occasion_setup_communication_settings.dart';
import 'package:fstapp/components/bank_accounts/views/unit_bank_accounts_screen.dart';
import 'package:festapp_core/forms.dart';
import 'package:fstapp/widgets/app_dialog.dart';
import 'dart:async';
import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/styles/styles_config.dart';
import 'package:fstapp/components/_shared/admin_strings.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/blueprint/blueprint_model.dart';
import 'package:fstapp/components/blueprint/views/blueprint_editor_tab.dart';
import 'package:festapp_core/eshop.dart';
import 'package:fstapp/components/forms/views/form_editor_content.dart';
import 'package:fstapp/components/forms/widgets_view/form_helper.dart';
import 'package:fstapp/components/forms/views/form_public_link.dart';
import 'package:fstapp/components/forms/form_strings.dart';
import 'package:fstapp/widgets/time_data_range_picker.dart';

import 'occasion_form_draft.dart';
import 'package:fstapp/components/_shared/project_picker_widget.dart';
import 'package:fstapp/components/forms/db_forms.dart';
import 'package:fstapp/components/features/ticket_feature.dart';
import 'package:fstapp/components/features/feature_constants.dart';
import 'package:fstapp/components/ticket_layout/views/ticket_settings.dart';
import 'package:fstapp/components/_shared/editor_draft_scope.dart';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/services/dialog_helper.dart';
import 'occasion_setup_draft.dart';
import 'package:fstapp/router_service.dart';
import 'occasion_setup_strings.dart';
import 'occasion_setup_story.dart';
import 'occasion_setup_story_shell.dart';
import 'package:fstapp/components/unit/verification/unit_legal_profile_section.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/services/exception_handler.dart';

class OccasionSetupPage extends StatefulWidget {
  final OccasionSetupDraft draft;
  const OccasionSetupPage({super.key, required this.draft});
  static Future<void> open(
      BuildContext context, OccasionSetupDraft draft) async {
    final initialized = await ExceptionHandler.guard(context,
        futureFunction: () => OccasionSetupDrafts(Supabase.instance.client)
            .initializeDefaults(draft));
    if (initialized == null || !context.mounted) return;
    final link = await Navigator.of(context).push<String>(MaterialPageRoute(
        builder: (_) => OccasionSetupPage(draft: initialized)));
    if (link != null && context.mounted) {
      await RouterService.navigate(
          context, '/${Uri.encodeComponent(link)}/admin/settings');
    }
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
  int _sourceRequest = 0;
  bool _loadingDetail = false;
  bool _copyEvent = false;
  Map<String, dynamic>? _formUndo;
  int _configurationEpoch = 0;
  List<BankAccountModel> _bankAccounts = [];
  String? _paymentError;
  bool _loadingPayments = true;
  final Map<String, Future<Map<String, dynamic>>> _sourceRequests = {};
  String? _sourceError;
  bool _loadingSources = true;
  Timer? _debounce;
  Future<bool>? _pending;
  bool _dirty = false;
  bool _allowPop = false;
  bool _conflict = false;
  String? _error;
  String? _blueprintError;
  bool _finalizing = false;
  String? _finalizeCommand;
  OccasionSetupDraft? _finalizeDraft;
  String? _finalizeError;
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
          ((_stored.data['defaultConfiguration'] as Map)['occasion']
              as Map)['start_time'],
      'end': _stored.data['end_time'] ??
          ((_stored.data['defaultConfiguration'] as Map)['occasion']
              as Map)['end_time'],
      'source': 'Od nuly',
      'saleMode': 'preparation',
      'copyProgram': false,
      'copyInformation': false,
      'copyEmails': false,
      'formEnabled': true,
      'formOrigin': null,
      'formDraft': null,
      'bank': 'Automaticky podle měny',
      'deadline': '',
      'deadlineEdited': false,
      'reminders': false,
      'tone': 'FeatureFormSettings.toneInherit'
          .tr(namedArgs: {'tone': 'FeatureFormSettings.toneFormal'.tr()}),
      'blueprintMode': OccasionSetupBlueprint(_stored.data).modeId,
      'blueprintObjects': <Map<String, dynamic>>[],
      'blueprintGroups': <Map<String, dynamic>>[],
      'blueprintWidth': 12,
      'blueprintHeight': 8,
      'reviewed': false,
      'reviewConfirmed': false,
      'completed': <int>[],
      ..._stored.data,
      'step': _stored.data['step'] ?? 1,
    };
    _copyEvent = _data['sourceId'] != null;
    _ensureDefaultForm(_data);
    _restrictToSupportedFeatures(_data);
    OccasionSetupBlueprint.normalizeForm(_data);
    _adoptFormSettings(_data);
    OccasionSetupStory.normalize(_data, AppConfig.isAppSupported);
    if (_data['appearance'] == null &&
        _data['sourceId'] == null &&
        _data['formOrigin'] == null) {
      OccasionSetupAppearance.apply(_data, OccasionSetupAppearance.read(_data));
    }
    _linkController = TextEditingController(text: _data['link'] as String);
    _loadSources();
    _loadPayments();
    _save();
  }

  Future<void> _loadSources() async {
    setState(() {
      _loadingSources = true;
      _sourceError = null;
    });
    _sourceRequests.clear();
    try {
      final rows = await Supabase.instance.client.rpc(
          'get_occasion_setup_source_list',
          params: {'p_unit': _stored.unit, 'p_source_unit': null});
      if (!mounted) return;
      setState(() => _sources =
          (rows as List).map((r) => Map<String, dynamic>.from(r)).toList());
      final id = _data['sourceId'] as int?;
      if (id != null) {
        if (_data['sourceSelectionPending'] == true) {
          await _selectSource(id);
        } else {
          // Read-only refresh: a presentation label is not a draft edit.
          await _sourceDetail(id);
          if (!mounted || _data['sourceId'] != id) return;
        }
      }
    } catch (_) {
      if (mounted)
        setState(() => _sourceError = 'Předlohy se nepodařilo načíst.');
    } finally {
      if (mounted) setState(() => _loadingSources = false);
    }
  }

  Future<Map<String, dynamic>> _sourceDetail(int id) {
    // This page belongs to one authenticated unit context. Never share this
    // cache across pages/logins, and discard failed requests to allow retry.
    final key =
        '${Supabase.instance.client.auth.currentUser?.id}:${_stored.unit}:$id';
    return _sourceRequests.putIfAbsent(key, () async {
      try {
        final result = await Supabase.instance.client.rpc(
            'get_occasion_setup_source',
            params: {'p_unit': _stored.unit, 'p_occasion': id});
        return Map<String, dynamic>.from(result as Map);
      } catch (_) {
        _sourceRequests.remove(key);
        rethrow;
      }
    });
  }

  Future<void> _selectSource(int? id) async {
    final request = ++_sourceRequest;
    if (id == null) {
      _change((d) => _applySource(d, null), changesConfiguration: true);
      setState(() {
        _loadingDetail = false;
        _sourceError = null;
      });
      return;
    }
    setState(() {
      _loadingDetail = true;
      _sourceError = null;
    });
    try {
      final source = await _sourceDetail(id);
      if (!mounted || request != _sourceRequest) return;
      final staged = Map<String, dynamic>.from(jsonDecode(jsonEncode(_data)));
      _applySource(staged, source);
      OccasionSetupBlueprint.normalizeForm(staged);
      _change((d) {
        d.clear();
        d.addAll(staged);
        d.remove('sourceSelectionPending');
      }, changesConfiguration: true);
    } catch (e) {
      if (mounted && request == _sourceRequest)
        setState(() => _sourceError = e is FormatException
            ? e.message
            : 'Předlohu se nepodařilo načíst. Dosavadní nastavení zůstalo zachováno.');
    } finally {
      if (mounted && request == _sourceRequest)
        setState(() => _loadingDetail = false);
    }
  }

  Future<void> _pickSource() async {
    final items = _sources
        .map((s) =>
            OccasionModel.fromJson(Map<String, dynamic>.from(s['occasion'])))
        .toList();
    if (items.isEmpty) return;
    final selected =
        items.where((o) => o.id == _data['sourceId']).firstOrNull ??
            OccasionModel(isOpen: false, isHidden: true, isPromoted: false);
    final id = await showDialog<int>(
        context: context,
        builder: (dialogContext) => AppDialog(
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 560),
                child: ProjectPicker<OccasionModel>(
                  items: items,
                  selectedItem: selected,
                  itemTitleBuilder: (o) => o.title ?? '',
                  itemIdBuilder: (o) => o.id,
                  itemDateBuilder: (o) => o.startTime,
                  hintText: 'Hledat předlohu',
                  createNewText: 'Od nuly',
                  happeningNowText: 'Probíhající',
                  upcomingText: 'Nadcházející',
                  pastText: 'Proběhlé',
                  onDismiss: () {},
                  onItemSelected: (o) => Navigator.pop(dialogContext, o.id),
                ))));
    if (id != null && mounted) await _selectSource(id);
  }

  Future<void> _loadPayments() async {
    try {
      final result = await Supabase.instance.client.rpc(
          'get_occasion_setup_payment_context',
          params: {'p_unit': _stored.unit});
      if (mounted)
        setState(() {
          _bankAccounts = (result as List)
              .map((r) =>
                  BankAccountModel.fromJson(Map<String, dynamic>.from(r)))
              .toList();
          _paymentError = null;
        });
    } catch (_) {
      if (mounted)
        setState(() => _paymentError = 'Platební účty se nepodařilo načíst.');
    } finally {
      if (mounted) setState(() => _loadingPayments = false);
    }
  }

  Set<String> _paidCurrencies(Map<String, dynamic> d) => d['formDraft'] is Map
      ? draftFormBundle(Map<String, dynamic>.from(d['formDraft']))
          .products
          .where((p) => (p.price ?? 0) > 0)
          .map((p) => p.currencyCode ?? 'CZK')
          .toSet()
      : {};

  String _paymentRouteLabel(Map<String, dynamic> d, String currency) {
    final id = (d['formDraft'] as Map?)?['bank_account'];
    final account = _bankAccounts
        .where((a) =>
            (id == null || a.id == id) &&
            a.supportedCurrencies.contains(currency))
        .firstOrNull;
    return account == null
        ? '$currency: Není dostupný platný bankovní účet.'
        : '$currency: ${account.title ?? account.accountNumber}';
  }

  bool _paymentRouteReady(Map<String, dynamic> d) {
    final currencies = _paidCurrencies(d);
    if (currencies.isEmpty || d['formEnabled'] == false) return true;
    final payments =
        ((d['formDraft'] as Map?)?['data'] as Map?)?['payments'] as Map?;
    if (payments?['bankEnabled'] == false &&
        payments?['stripeConnectionId'] is String) return true;
    if (_loadingPayments || _paymentError != null) return false;
    final id = (d['formDraft'] as Map?)?['bank_account'];
    return currencies.every((currency) => _bankAccounts.any((a) =>
        (id == null || a.id == id) &&
        a.supportedCurrencies.contains(currency)));
  }

  Future<void> _suggestLink({required bool isForm}) async {
    final epoch = _sourceRequest;
    final form = _data['formDraft'] as Map?;
    final old = isForm ? (form?['link']) : _data['link'];
    final title = isForm ? (form?['title']) : _data['title'];
    final value = await ExceptionHandler.guard(context,
        futureFunction: () => Supabase.instance.client
                .rpc('suggest_public_link', params: {
              'p_kind': isForm ? 'form' : 'occasion',
              'p_title': title,
              'p_unit': _stored.unit
            }));
    if (!mounted ||
        value is! String ||
        epoch != _sourceRequest ||
        (isForm ? ((_data['formDraft'] as Map?)?['link']) : _data['link']) !=
            old) return;
    _change((d) {
      if (isForm) {
        (d['formDraft'] as Map)['link'] = value;
        _formEpoch++;
        _inlineFormBundle = null;
      } else {
        d['link'] = value;
        _linkController.text = value;
      }
    }, changesConfiguration: true);
  }

  String _sourceLabel(Map<String, dynamic> source) {
    final o = source['occasion'] as Map;
    final date = DateTime.tryParse(o['start_time'] as String? ?? '');
    final formatted = date == null
        ? ''
        : DateFormat.yMd(context.locale.toString()).format(date);
    return '${o['title']} ($formatted)';
  }

  Future<Map<String, dynamic>?> _pickConfiguration(String kind) async {
    final epoch = _configurationEpoch;
    final selected = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (_) => OccasionSetupCopyPicker(
            kind: kind,
            load: () async {
              final rows = _sources;
              return [
                for (final source in rows.whereType<Map>())
                  for (final item
                      in (source[kind] as List? ?? []).whereType<Map>())
                    {
                      ...Map<String, dynamic>.from(item),
                      'occasionId': (source['occasion'] as Map)['id'],
                      'occasionTitle': (source['occasion'] as Map)['title']
                    }
              ];
            }));
    if (!mounted || selected == null || epoch != _configurationEpoch)
      return null;
    try {
      final source = await _sourceDetail(selected['occasionId'] as int);
      if (!mounted || epoch != _configurationEpoch) return null;
      return {
        'source': source,
        'item': (source[kind] as List)
            .whereType<Map>()
            .firstWhere((item) => item['id'] == selected['id'])
      };
    } catch (error, stack) {
      debugPrint('Setup copy failed: $error\n$stack');
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(OccasionSetupStrings.story('copiesFailed'))));
      return null;
    }
  }

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
    draft['formEnabled'] = true;
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
    draft.remove('sourceProgram');
    draft.remove('sourceInformation');
  }

  void _applySource(Map<String, dynamic> draft, Map<String, dynamic>? source) {
    _ticketFeature = null;
    _inlineFormBundle = null;
    _formEpoch++;
    draft.remove('ticketDraft');
    draft['formDefaultsFollowEvent'] = source == null;
    draft['source'] = source == null ? 'Od nuly' : _sourceLabel(source);
    draft['copyProgram'] = false;
    draft['copyInformation'] = false;
    draft['copyEmails'] = false;
    draft['sourceId'] = null;
    draft['sourceFormId'] = null;
    draft['formDraft'] = null;
    draft['formLinkEdited'] = false;
    draft['formOrigin'] = null;
    draft['blueprintObjects'] = <Map<String, dynamic>>[];
    draft['blueprintGroups'] = <Map<String, dynamic>>[];
    draft['blueprintBackground'] = null;
    draft['blueprintMode'] = 'none';
    draft['sourceProgram'] = <dynamic>[];
    draft['sourceInformation'] = <dynamic>[];
    draft['completed'] = <int>[];
    if (source == null) {
      _ensureDefaultForm(draft);
      draft['eventKind'] = 'regular';
      draft['eventKindNeedsConfirmation'] = false;
      OccasionSetupAppearance.apply(draft,
          Map<String, dynamic>.from(OccasionSetupAppearance.presets.first));
      return;
    }
    draft['sourceId'] = (source['occasion'] as Map)['id'];
    draft.putIfAbsent('copy_locale', () => context.locale.languageCode);
    draft.putIfAbsent('copy_title_edited', () => false);
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
      draft['sourceFormId'] = (forms.first as Map)['id'];
      draft['formDraft'] = jsonDecode(jsonEncode(forms.first));
      (draft['formDraft'] as Map)['link'] = '';
      draft['formOrigin'] = (source['occasion'] as Map)['title'];
      draft['formEnabled'] = true;
      (draft['formDraft'] as Map)['bank_account'] = null;
      _adoptFormSettings(draft);
    }
    final plans = source['blueprints'] as List;
    final selectedForm = forms.isEmpty ? null : forms.first as Map;
    final selected = plans
        .where((p) => (p as Map)['id'] == selectedForm?['blueprint'])
        .firstOrNull;
    if (selected is Map) _applyBlueprint(draft, selected);
    _ensureDefaultForm(draft);
    draft['eventKind'] = selected is Map
        ? 'ball'
        : ticket != null
            ? 'concert'
            : 'regular';
    draft['eventKindNeedsConfirmation'] = false;
    draft.remove('appearance');
    draft['appearance'] = {
      ...OccasionSetupAppearance.read(draft),
      'id': 'custom',
      'preserveSource': true
    };
  }

  Map<String, dynamic> _inheritedSettings(Map<String, dynamic> draft) {
    final config = draft['defaultConfiguration'] as Map? ?? {};
    final feature = ((config['occasion'] as Map?)?['features'] as List? ?? [])
        .whereType<Map>()
        .where((f) => f['code'] == 'form')
        .firstOrNull;
    return {
      ...Map<String, dynamic>.from(
          config['communicationDefaults'] as Map? ?? {}),
      // Match queue_payment_reminders: form override > occasion form feature > defaults.
      'is_reminder_enabled': feature?['reminder_is_enabled'] ?? true,
      'reminder_interval_seconds':
          feature?['reminder_interval_seconds'] ?? 86400,
    };
  }

  void _adoptFormSettings(Map<String, dynamic> draft) {
    final form = draft['formDraft'] as Map?;
    if (form == null) return;
    final defaults = _inheritedSettings(draft);
    final features = ((draft['defaultConfiguration'] as Map?)?['occasion']
            as Map?)?['features'] as List? ??
        [];
    final feature =
        features.whereType<Map>().where((f) => f['code'] == 'form').firstOrNull;
    draft['deadline'] = OccasionSetupDueSettings.days(
        form['deadline_duration_seconds'] as num? ??
            feature?['deadline_duration_seconds'] as num? ??
            604800);
    draft['deadlineEdited'] = false;
    final data = form['data'] as Map? ?? {};
    draft['reminders'] = data[FormDefinition.metaIsReminderEnabled] ??
        defaults['is_reminder_enabled'] ??
        true;
    draft['communicationTone'] =
        data[FormMetadata.metaCommunicationTone] ?? 'inherit';
    draft['replyTo'] = data['reply_to'];
    draft['tone'] = draft['communicationTone'];
  }

  void _persistFormControls(Map<String, dynamic> draft) {
    final form = draft['formDraft'];
    if (form is! Map) return;
    // Due/reminder component writes canonical overrides only on explicit edits.
    final data = Map<String, dynamic>.from(form['data'] as Map? ?? {});
    final tone = draft['communicationTone'];
    if (tone == 'formal' || tone == 'informal') {
      data['communication_tone'] = tone;
    } else {
      data.remove('communication_tone');
    }
    if ((draft['replyTo'] as String? ?? '').trim().isNotEmpty) {
      data['reply_to'] = (draft['replyTo'] as String).trim();
    } else {
      data.remove('reply_to');
    }
    form['data'] = data;
    draft['tone'] = tone ?? 'inherit';
  }

  Future<Map<String, dynamic>> _loadEmailPreview(
      Map<String, dynamic> snapshot) async {
    if (!await _flush()) throw StateError('Draft save failed');
    if (snapshot['previewMessageType'] == 'order_tickets') {
      final data = await Supabase.instance.client
          .rpc('get_occasion_setup_email_preview', params: {
        'p_id': _stored.id,
        'p_expected_revision': _stored.revision,
        'p_tone': null,
        'p_reply_to': null,
        'p_message_type': 'order_tickets',
        'p_occasion': null,
        'p_delivery_mode': null,
      });
      return Map<String, dynamic>.from(data as Map);
    }
    final result = await Supabase.instance.client.functions
        .invoke('occasion-setup-email-preview', body: {
      'draftId': _stored.id,
      'revision': _stored.revision,
      'tone': snapshot['communicationTone'] == 'inherit'
          ? null
          : snapshot['communicationTone'],
      'replyTo': snapshot['replyTo'],
      'messageType': snapshot['previewMessageType'] ?? 'order_confirmation',
      'sampleTicketCount': snapshot['previewTicketCount'] ?? 1,
      'deliveryMode': (snapshot['ticketDraft'] as Map?)?['delivery_mode'] ??
          'pdf_attachment',
    });
    return Map<String, dynamic>.from(result.data as Map);
  }

  void _applyBlueprint(Map<String, dynamic> draft, Map plan) {
    OccasionSetupBlueprint(draft).importPlan(plan);
  }

  void _save() {
    if (_stored.isFinalized) return;
    _dirty = true;
    _debounce?.cancel();
    if (!_conflict && _error == null) {
      _debounce = Timer(const Duration(milliseconds: 600), _flush);
    }
  }

  void _change(void Function(Map<String, dynamic>) update,
      {bool changesConfiguration = false, bool invalidateUndo = true}) {
    if (_finalizeCommand != null) return;
    setState(() {
      update(_data);
      if (changesConfiguration && invalidateUndo) {
        _configurationEpoch++;
        _formUndo = null;
      }
      OccasionSetupStory.normalize(_data, AppConfig.isAppSupported);
      OccasionSetupBlueprint.normalizeForm(_data);
      if (_data['formDraft'] is Map) {
        (_data['formDraft'] as Map)['title'] = _data['title'];
        _inlineFormBundle?.form.definition =
            _inlineFormBundle!.form.definition.copyWith(title: _data['title']);
      }
      _restrictToSupportedFeatures(_data);
      if (changesConfiguration) _persistFormControls(_data);
      if (changesConfiguration) {
        _data['reviewed'] = false;
        _data['reviewConfirmed'] = false;
        (_data['completed'] as List).remove(5);
        for (final step in _requiredSteps.where((s) => s != 5)) {
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
      OccasionSetupBlueprint.normalizeForm(_data);
      OccasionSetupStory.normalize(_data, AppConfig.isAppSupported);
      _data['completedQuestions'] = [
        for (final q in _questions)
          if (!q.optional && _questionReady(_data, q)) q.key
      ];
      final snapshot = Map<String, dynamic>.from(jsonDecode(jsonEncode(_data)));
      _dirty = false;
      try {
        _stored = await _store.save(_stored, snapshot, snapshot['step'] as int);
        // Adopt server-owned copy title without overwriting typing during save.
        if (_data['title'] == snapshot['title'] &&
            _data['copy_title_edited'] != true &&
            _stored.data['title'] != snapshot['title']) {
          _data['title'] = _stored.data['title'];
          _editEpoch++;
        }
        _error = null;
      } catch (e) {
        if (e is PostgrestException &&
            (e.code == '22023' || e.code == '40001')) {
          try {
            final current = await _store.get(_stored.id);
            if (current.isFinalized) {
              // Another window completed this draft. Preserve its receipt and
              // allow this retained page to leave without another save.
              _stored = current;
              _dirty = false;
              _conflict = false;
              _error = null;
              return true;
            }
          } catch (_) {
            // A failed read cannot establish completion; keep the local edits.
          }
        }
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

  Future<void> _finalize() async {
    if (_finalizing) return;
    setState(() {
      _finalizing = true;
      _finalizeError = null;
    });
    try {
      if (_finalizeCommand == null) {
        if (!await _flush() || !mounted) return;
        _finalizeDraft = _stored;
        _finalizeCommand = OccasionSetupDrafts.newId();
      }
      final link = await _store.finalize(_finalizeDraft!, _finalizeCommand!);
      if (!mounted) return;
      setState(() => _allowPop = true);
      Navigator.of(context).pop(link);
    } catch (error) {
      if (error is PostgrestException &&
          error.code != null &&
          !error.code!.startsWith('08') &&
          error.code != '57014' &&
          !error.code!.startsWith('PGRST0')) {
        _finalizeCommand = null;
        _finalizeDraft = null;
      }
      if (mounted)
        setState(() => _finalizeError = OccasionSetupStrings.finalizeFailed);
    } finally {
      if (mounted) setState(() => _finalizing = false);
    }
  }

  Future<void> _leave() async {
    if (_finalizing) return;
    if (_finalizeCommand != null || _stored.isFinalized) {
      setState(() => _allowPop = true);
      Navigator.of(context).pop();
      return;
    }
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
      final current = await _store.get(_stored.id);
      if (!mounted) return;
      setState(() {
        _stored = current;
        _data = Map.of(current.data);
        _inlineFormBundle = null;
        _ensureDefaultForm(_data);
        OccasionSetupStory.normalize(_data, AppConfig.isAppSupported);
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
        return !_copyEvent || d['sourceId'] != null;
      case 1:
        final start = DateTime.tryParse(d['start'] as String);
        final end = DateTime.tryParse(d['end'] as String);
        return (d['title'] as String).trim().isNotEmpty &&
            isValidPublicSlug(d['link'] as String, allowEmpty: true) &&
            start != null &&
            end != null &&
            !end.isBefore(start);
      case 2:
        return true;
      case 3:
        if (d['formEnabled'] == false) return true;
        final formData = d['formDraft'];
        if (formData is! Map) return false;
        return OccasionSetupSales.valid(d, DateTime.now()) &&
            (!OccasionSetupStory.paid(d) || _paymentsReady(d)) &&
            _communicationReady(d) &&
            (formData['title'] as String? ?? '').trim().isNotEmpty &&
            isValidPublicSlug(formData['link'] as String? ?? '',
                allowEmpty: true) &&
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

  bool _communicationReady(Map<String, dynamic> d) {
    final reply = (d['replyTo'] as String? ?? '').trim();
    return reply.isEmpty ||
        RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(reply);
  }

  bool _blueprintReady(Map<String, dynamic> d) =>
      !OccasionSetupStory.seats(d) ||
      (OccasionSetupBlueprint(d).mode != SetupBlueprintMode.none &&
          OccasionSetupBlueprint(d).ready);

  bool _paymentsReady(Map<String, dynamic> d) => (d['formEnabled'] == false ||
      OccasionSetupDueSettings.validDays(d['deadline'] as String? ?? '') &&
          OccasionSetupDueSettings.validReminder(d,
              inheritedEnabled:
                  _inheritedSettings(d)['is_reminder_enabled'] as bool? ??
                      true) &&
          _paymentRouteReady(d));

  List<int> get _requiredSteps =>
      _questions.where((q) => !q.optional).map((q) => q.step).toSet().toList();

  int _progress(Map<String, dynamic> d) {
    final required = _questions.where((q) => !q.optional).toList();
    return (100 *
            required.where((q) => _questionReady(d, q)).length /
            required.length)
        .round();
  }

  bool get _showSource => _data['storyQuestion'] == 'source';
  List<OccasionSetupQuestion> get _questions =>
      OccasionSetupStory.questions(AppConfig.isAppSupported,
          data: _data, includeSource: _showSource);

  int _questionIndex(Map<String, dynamic> d) =>
      OccasionSetupStory.index(d, AppConfig.isAppSupported,
          includeSource: _showSource);

  void _goToQuestion(Map<String, dynamic> d, int index) {
    final question = _questions[index];
    d['step'] = question.step;
    d['storyQuestion'] = question.key;
    d['visitedQuestions'] = {
      ...(d['visitedQuestions'] as List? ?? []).cast<String>(),
      question.key
    }.toList();
  }

  bool _questionReady(Map<String, dynamic> d, OccasionSetupQuestion q) {
    if (q.key == 'review')
      return d['reviewed'] == true && d['reviewConfirmed'] == true;
    if (q.key == 'kind')
      return OccasionSetupStory.kinds.contains(d['eventKind']) &&
          d['eventKindNeedsConfirmation'] != true;
    if (q.key == 'appearance')
      return d['appearance'] is Map &&
          OccasionSetupAppearance.valid(d['appearance'] as Map);
    if (q.optional || d['formEnabled'] == false && q.step == 3) return true;
    if (q.key == 'saleTiming')
      return OccasionSetupSales.valid(d, DateTime.now());
    if (q.key == 'paymentTiming')
      return OccasionSetupDueSettings.validDays(
              d['deadline'] as String? ?? '') &&
          OccasionSetupDueSettings.validReminder(d,
              inheritedEnabled:
                  _inheritedSettings(d)['is_reminder_enabled'] as bool? ??
                      true);
    if (q.key == 'payments') return _paymentRouteReady(d);
    if (q.key == 'communication') return _communicationReady(d);
    if (q.key == 'form') {
      final form = d['formDraft'] as Map?;
      return form != null &&
          (form['title'] as String? ?? '').trim().isNotEmpty &&
          isValidPublicSlug(form['link'] as String? ?? '', allowEmpty: true) &&
          (form['fields'] as List? ?? []).isNotEmpty;
    }
    if (q.step != 1) return _stepReady(d, q.step);
    switch (q.key) {
      case 'name':
        return (d['title'] as String).trim().isNotEmpty;
      case 'start':
        return DateTime.tryParse(d['start'] as String) != null;
      case 'dates':
      case 'end':
        final start = DateTime.tryParse(d['start'] as String);
        final end = DateTime.tryParse(d['end'] as String);
        return start != null && end != null && !end.isBefore(start);
      default:
        return isValidPublicSlug(d['link'] as String, allowEmpty: true);
    }
  }

  void _advance() {
    final d = _active!;
    final index = _questionIndex(d);
    final question = _questions[index];
    if (index == _questions.length - 1) return;
    if (!_questionReady(d, question)) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(OccasionSetupStrings.story('incomplete'))));
      return;
    }
    _jump(_questions[index + 1].key);
  }

  void _review() {
    final d = _active!;
    if (d['reviewConfirmed'] != true) return;
    final issues = _reviewIssues(d);
    if (issues.isNotEmpty) {
      setState(() => d['step'] = issues.first.key);
      return;
    }
    final missing = _questions
        .where((q) => !q.optional && q.key != 'review' && !_questionReady(d, q))
        .firstOrNull;
    if (missing != null) {
      _jump(missing.key);
      return;
    }
    _change((x) {
      x['completed'] = _requiredSteps;
      x['reviewed'] = true;
    });
  }

  void _openBlueprint() {
    final plan = _planFromDraft(_active!);
    Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => Scaffold(
        appBar: AppBar(
            title: Text(OccasionSetupStrings.story('draftBlueprintTitle'))),
        body: BlueprintTab.prototype(
          prototypeBlueprint: plan,
          onPrototypeComplete: () => Navigator.of(context).pop(),
          onPrototypeSave: (saved) async {
            _change((x) => OccasionSetupBlueprint(x).writePlan(saved),
                changesConfiguration: true);
            if (!await _flush())
              throw StateError(
                  'Koncept se nepodařilo uložit. Zkuste uložit znovu.');
          },
        ),
      ),
    ));
  }

  BlueprintModel _planFromDraft(Map<String, dynamic> d) =>
      OccasionSetupBlueprint(d).plan();

  Future<void> _selectBlueprint() async {
    final picked = await _pickConfiguration('blueprints');
    if (picked == null || !mounted) return;
    try {
      final staged = _clone(_data);
      final source = picked['source'] as Map;
      final plan = picked['item'] as Map;
      final referencedForm = (source['forms'] as List)
          .whereType<Map>()
          .where((f) => f['blueprint'] == plan['id'])
          .firstOrNull;
      if (referencedForm != null) _replaceForm(staged, referencedForm, source);
      _applyBlueprint(staged, plan);
      staged['blueprintSourceOccasionId'] = (source['occasion'] as Map)['id'];
      _change((d) {
        d.clear();
        d.addAll(staged);
      }, changesConfiguration: true);
      setState(() {
        _inlineFormBundle = null;
        _formEpoch++;
        _blueprintError = null;
      });
    } catch (error) {
      if (mounted) setState(() => _blueprintError = error.toString());
    }
  }

  Map<String, dynamic> _clone(Map value) =>
      Map<String, dynamic>.from(jsonDecode(jsonEncode(value)));

  void _replaceForm(Map<String, dynamic> d, Map raw, Map source) {
    final form = _clone(raw);
    form['link'] = (d['formDraft'] as Map?)?['link'] ?? '';
    form['bank_account'] = null;
    d['formDraft'] = form;
    d.remove('appearance');
    d['appearance'] = {
      ...OccasionSetupAppearance.read(d),
      'id': 'custom',
      'preserveSource': true
    };
    d['formDefaultsFollowEvent'] = false;
    d['sourceFormId'] = form['id'];
    d['formOrigin'] = (source['occasion'] as Map)['title'];
    d['formSourceOccasionId'] = (source['occasion'] as Map)['id'];
    _adoptFormSettings(d);
    final plan = (source['blueprints'] as List)
        .whereType<Map>()
        .where((p) => p['id'] == form['blueprint'])
        .firstOrNull;
    if (plan != null) {
      _applyBlueprint(d, plan);
    } else {
      OccasionSetupBlueprint(d).clear();
    }
    OccasionSetupBlueprint.normalizeForm(d);
  }

  Future<void> _newBlueprint() async {
    // The modern venue catalog uses a different document contract. This legacy
    // editor offers an actual grid template plus an empty plan, with no preselection.
    final template = await showDialog<String>(
        context: context,
        builder: (c) => AppSimpleDialog(
                title:
                    Text(OccasionSetupStrings.story('chooseBlueprintTemplate')),
                children: [
                  for (final id in ['empty', 'rows'])
                    SimpleDialogOption(
                        onPressed: () => Navigator.pop(c, id),
                        child: Text(OccasionSetupStrings.story(id == 'empty'
                            ? 'emptyBlueprint'
                            : 'rowsBlueprint'))),
                ]));
    if (!mounted || template == null) return;
    _change((d) {
      OccasionSetupBlueprint(d).clear(create: true);
      if (template == 'rows') {
        final products = draftFormBundle(_clone(d['formDraft'] as Map))
            .products
            .where((p) => p.productTypeString == 'spot')
            .toList();
        {
          d['blueprintWidth'] = 12;
          d['blueprintHeight'] = 8;
          d['blueprintObjects'] = [
            for (var y = 1; y <= 4; y++)
              for (var x = 1; x <= 8; x++)
                {
                  'type': 'spot',
                  'x': x,
                  'y': y,
                  'title': '$y-$x',
                  'product': products.firstOrNull?.id
                }
          ];
        }
      }
    }, changesConfiguration: true);
    _openBlueprint();
  }

  Widget _switch(Map<String, dynamic> d, String keyName, String label) =>
      SwitchListTile(
        title: Text(label),
        value: d[keyName] == true,
        onChanged: (v) => _change((x) {
          x[keyName] = v;
          if (keyName == 'deadline') x['deadlineEdited'] = true;
        }, changesConfiguration: true),
      );

  Future<void> _chooseForm() async {
    final picked = await _pickConfiguration('forms');
    if (picked == null || !mounted) return;
    final previous = _clone(_data);
    try {
      final staged = _clone(_data);
      _replaceForm(staged, picked['item'] as Map, picked['source'] as Map);
      _change((d) {
        d.clear();
        d.addAll(staged);
      }, changesConfiguration: true);
      setState(() {
        _inlineFormBundle = null;
        _formEpoch++;
        _formUndo = previous;
      });
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  void _undoForm() {
    final previous = _formUndo;
    if (previous == null) return;
    _change((d) {
      // Restore the complete configuration only during the immediate transition.
      final step = d['step'];
      final question = d['storyQuestion'];
      d.clear();
      d.addAll(previous);
      d['step'] = step;
      d['storyQuestion'] = question;
    }, changesConfiguration: true);
    setState(() {
      _inlineFormBundle = null;
      _formEpoch++;
    });
  }

  Widget _draftFormLink(Map<String, dynamic> d) => OccasionSetupFormLink(
      key: ValueKey('${d['id']}-link-$_formEpoch'),
      draftId: _stored.id,
      title:
          (d['formDraft'] as Map)['title'] as String? ?? d['title'] as String,
      value: (d['formDraft'] as Map)['link'] as String? ?? '',
      automatic: d['formLinkEdited'] != true,
      onChanged: (value, automatic) => _change((x) {
            x['formLinkEdited'] = !automatic;
            (x['formDraft'] as Map)['link'] = value;
            _inlineFormBundle?.form.definition =
                _inlineFormBundle!.form.definition.copyWith(link: value);
          }, changesConfiguration: true, invalidateUndo: !automatic));

  Widget _basics(Map<String, dynamic> d) {
    final question = _questions[_questionIndex(d)].key;
    if (question == 'name') {
      return TextFormField(
        key: ValueKey('${d['id']}-title-$_editEpoch'),
        initialValue: d['title'] as String,
        decoration:
            InputDecoration(labelText: AdministrationStrings.titleLabel),
        onChanged: (value) => _change((x) {
          x['title'] = value;
          x['copy_title_edited'] = true;
        }, changesConfiguration: true),
      );
    }
    if (question == 'link') {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextFormField(
          controller: _linkController,
          decoration: InputDecoration(
              labelText: AdministrationStrings.linkLabel,
              suffixIcon: IconButton(
                  tooltip: 'Navrhnout dostupnou adresu',
                  icon: const Icon(Icons.auto_fix_high),
                  onPressed: () => _suggestLink(isForm: false))),
          onChanged: (value) =>
              _change((x) => x['link'] = value, changesConfiguration: true),
        ),
        const SizedBox(height: 16),
        PublicLink(link: d['link'] as String, isForm: false),
      ]);
    }
    if (question == 'dates')
      return Column(children: [
        _dateQuestion(d, 'start'),
        const SizedBox(height: 24),
        _dateQuestion(d, 'end'),
      ]);
    return _dateQuestion(d, question);
  }

  Widget _dateQuestion(Map<String, dynamic> d, String question) {
    final isStart = question == 'start';
    final value = DateTime.tryParse(d[question] as String);
    void update(DateTime selected) => _change((x) {
          x[question] = selected.toIso8601String();
          final end = DateTime.tryParse(x['end'] as String);
          if (isStart && end != null && selected.isAfter(end)) {
            x['end'] = selected.toIso8601String();
          }
        }, changesConfiguration: true);
    final start = DateTime.tryParse(d['start'] as String);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TimeDatePicker(
        date: value,
        time: value == null ? null : TimeOfDay.fromDateTime(value),
        dateLabel:
            OccasionSetupStrings.story(isStart ? 'startDate' : 'endDate'),
        timeLabel:
            OccasionSetupStrings.story(isStart ? 'startTime' : 'endTime'),
        minDate: DateTime(2000),
        maxDate: DateTime(2101),
        isValid: value != null &&
            (isStart || start == null || !value.isBefore(start)),
        onDateChanged: (day) => update(DateTime(day.year, day.month, day.day,
            value?.hour ?? 0, value?.minute ?? 0)),
        onTimeChanged: (time) {
          final day = value ?? DateTime.now();
          update(
              DateTime(day.year, day.month, day.day, time.hour, time.minute));
        },
      ),
      if (!isStart && value != null && start != null && value.isBefore(start))
        Text(OccasionSetupStrings.story('endBeforeStart'),
            style: TextStyle(color: Theme.of(context).colorScheme.error)),
    ]);
  }

  List<MapEntry<int, String>> _reviewIssues(Map<String, dynamic> d) {
    final issues = <MapEntry<int, String>>[];
    if ((d['title'] as String).trim().isEmpty) {
      issues.add(const MapEntry(1, 'Chybí název události.'));
    }
    if (!isValidPublicSlug(d['link'] as String, allowEmpty: true)) {
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
        if ((form.form.definition.title ?? '').trim().isEmpty ||
            !isValidPublicSlug(form.form.definition.link ?? '',
                allowEmpty: true)) {
          issues
              .add(const MapEntry(3, 'Doplň název a platný odkaz formuláře.'));
        }
        if (form.form.relatedFields
            .where((field) => field.definition.isTicketField != true)
            .isEmpty) {
          issues.add(const MapEntry(3, 'Formulář nemá žádná pole.'));
        }
        if (form.form.relatedFields.any((field) =>
                field.definition.type == FormMetadata.fieldTypeTicket) &&
            form.products.isEmpty) {
          issues
              .add(const MapEntry(3, 'Formulář se vstupenkami nemá produkty.'));
        }
      }
    }
    if (OccasionSetupStory.seats(d)) {
      if (d['formEnabled'] != true || d['formDraft'] == null) {
        issues.add(MapEntry(
            AppConfig.isAppSupported ? 4 : 6, 'Plánek potřebuje formulář.'));
      }
      if (!OccasionSetupBlueprint(d).ready ||
          OccasionSetupBlueprint(d).mode == SetupBlueprintMode.none) {
        issues.add(MapEntry(AppConfig.isAppSupported ? 4 : 6,
            'Plánek zatím nemá žádná místa.'));
      }
    }
    if (OccasionSetupStory.paid(d) && !_paymentsReady(d)) {
      issues.add(const MapEntry(
          4, 'Doplňte platný účet pro používané měny a nezápornou splatnost.'));
    }
    for (final q in _questions.where((q) => [
          'kind',
          'appearance',
          'saleTiming',
          'communication'
        ].contains(q.key))) {
      if (!_questionReady(d, q))
        issues.add(MapEntry(q.step, 'Dokonči ${_shortLabel(q.key)}.'));
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
              onPressed: () =>
                  _jump(_questions.firstWhere((q) => q.step == step).key),
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
    final seatCount = OccasionSetupBlueprint(d).seatCount;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Kontrola před vytvořením události',
          style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 8),
      Text(
          '${_questions.where((q) => !q.optional && q.key != 'review' && _questionReady(d, q)).length} z ${_questions.where((q) => !q.optional && q.key != 'review').length} nastavení bez chyby${d['reviewed'] == true ? '' : ' · čeká finální kontrola'}'),
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
                onTap: () => _jump(
                    _questions.firstWhere((q) => q.step == issue.key).key),
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
            if (AppConfig.isAppSupported)
              _reviewRow(
                  AdministrationStrings.linkLabel,
                  (d['link'] as String).isEmpty
                      ? FormStrings.automaticPublicLink
                      : publicLinkUrl(d['link'] as String, isForm: false)),
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
                  form.form.definition.title ?? ''),
              _reviewRow('FeatureFormSettings.labelFormLink'.tr(),
                  form.form.definition.link ?? ''),
              _reviewRow('Stav', 'Zavřený'),
              Text(
                  'Pole formuláře (${form.form.relatedFields.where((field) => field.definition.isTicketField != true).length})',
                  style: Theme.of(context).textTheme.titleSmall),
              for (final field in form.form.relatedFields
                  .where((field) => field.definition.isTicketField != true))
                _reviewRow(
                    field.definition.title ??
                        FormHelper.fieldTypeToLocale(
                            field.definition.type ?? ''),
                    '${FormHelper.fieldTypeToLocale(field.definition.type ?? '')} · ${field.definition.isRequired == true ? 'povinné' : 'nepovinné'}${field.definition.isHidden == true ? ' · skryté' : ''}${field.options.isEmpty ? '' : ' · možnosti: ${field.options.map((option) => option.title).join(', ')}'}'),
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
              if (AppConfig.isAppSupported && OccasionSetupStory.paid(d)) ...[
                _reviewRow(
                    'BankAccount.bankAccount'.tr(),
                    _paidCurrencies(d)
                        .map((c) => _paymentRouteLabel(d, c))
                        .join(' · ')),
                _reviewRow('FeatureFormSettings.labelDeadlineDays'.tr(),
                    '${d['deadline']}'),
                _reviewRow('FeatureFormSettings.labelEnableReminders'.tr(),
                    d['reminders'] == true ? 'Zapnuto' : 'Vypnuto'),
                _reviewRow(
                    'FeatureFormSettings.labelCommunicationTone'.tr(),
                    OccasionSetupStrings.story(
                        d['communicationTone'] == 'formal' ||
                                d['communicationTone'] == 'informal'
                            ? d['communicationTone'] as String
                            : 'inheritedSetting')),
              ],
            ],
          ],
          issues),
      if (OccasionSetupStory.tickets(d))
        _reviewSection(
            d,
            2,
            'Vzhled a vstupenka',
            [
              _reviewRow(
                  TicketDeliveryStrings.text('title'),
                  TicketDeliveryStrings.label(TicketDeliveryMode.parse(
                      (d['ticketDraft'] as Map?)?['delivery_mode'],
                      present: (d['ticketDraft'] as Map?)
                              ?.containsKey('delivery_mode') ??
                          false))),
              _reviewRow(
                  'Vzhled',
                  (d['ticketDraft'] as Map?)?['layout'] == null
                      ? 'Výchozí šablona'
                      : 'Uložený návrh'),
            ],
            issues),
      if (!AppConfig.isAppSupported && OccasionSetupStory.paid(d))
        _reviewSection(
            d,
            4,
            'Nastavení plateb',
            [
              _reviewRow(
                  'BankAccount.bankAccount'.tr(),
                  _paidCurrencies(d)
                      .map((c) => _paymentRouteLabel(d, c))
                      .join(' · ')),
              _reviewRow('FeatureFormSettings.labelDeadlineDays'.tr(),
                  '${d['deadline']}'),
              _reviewRow('FeatureFormSettings.labelEnableReminders'.tr(),
                  d['reminders'] == true ? 'Zapnuto' : 'Vypnuto'),
              _reviewRow(
                  'FeatureFormSettings.labelCommunicationTone'.tr(),
                  OccasionSetupStrings.story(
                      d['communicationTone'] == 'formal' ||
                              d['communicationTone'] == 'informal'
                          ? d['communicationTone'] as String
                          : 'inheritedSetting')),
            ],
            issues),
      if (OccasionSetupStory.seats(d))
        _reviewSection(
            d,
            AppConfig.isAppSupported ? 4 : 6,
            CommonStrings.blueprint,
            [
              _reviewRow('Způsob', OccasionSetupBlueprint(d).label),
              if (OccasionSetupBlueprint(d).mode !=
                  SetupBlueprintMode.none) ...[
                _reviewRow('Rozměry',
                    '${d['blueprintWidth']} × ${d['blueprintHeight']}'),
                _reviewRow(
                    'Skupiny',
                    groups
                        .map((group) =>
                            (group as Map)['title']?.toString() ?? '')
                        .join(', ')),
                _reviewRow('Místa', '$seatCount'),
                _reviewRow('Vazba na formulář',
                    form?.form.definition.title ?? 'Chybí formulář'),
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
            Text(FormStrings.automaticPublicLink),
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
      ] else ...[
        const Text(
            '100 % znamená dokončené nastavení. Koncept je stále neveřejný.'),
        const SizedBox(height: 10),
        OutlinedButton(
            onPressed: _leave, child: const Text('Uložit dokončený koncept')),
        if (_finalizeError != null) Text(_finalizeError!),
      ],
    ]);
  }

  Widget _body(Map<String, dynamic> d) {
    if (_questions[_questionIndex(d)].optional) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(OccasionSetupStrings.story('verificationHint')),
        const SizedBox(height: 20),
        UnitLegalProfileSection(
          unitId: _stored.unit,
          canEdit: RightsService.isUnitManager(),
        ),
      ]);
    }

    final question = _questions[_questionIndex(d)].key;
    if (question == 'kind') return _kindSettings(d);
    if (question == 'appearance') return _appearanceSettings(d);
    if (question == 'saleTiming')
      return OccasionSetupSaleSettings(
          draft: d,
          onChanged: (update) => _change(update, changesConfiguration: true));
    if (question == 'paymentTiming')
      return OccasionSetupDueSettings(
          draft: d,
          inheritedDeadlineSeconds:
              (((d['defaultConfiguration'] as Map?)?['occasion']
                              as Map?)?['features'] as List? ??
                          [])
                      .whereType<Map>()
                      .where((f) => f['code'] == 'form')
                      .firstOrNull?['deadline_duration_seconds'] as num? ??
                  604800,
          inheritedRemindersEnabled:
              _inheritedSettings(d)['is_reminder_enabled'] as bool? ?? true,
          inheritedReminderSeconds:
              _inheritedSettings(d)['reminder_interval_seconds'] as num? ??
                  86400,
          onChanged: (update) => _change(update, changesConfiguration: true));
    if (question == 'communication')
      return OccasionSetupCommunicationSettings(
          draft: d,
          inheritedTone:
              _inheritedSettings(d)['communication_tone'] as String? ??
                  'formal',
          inheritedReplyTo: _inheritedSettings(d)['reply_to'] as String?,
          onChanged: (update) {
            _ticketFeature = null;
            _change(update, changesConfiguration: true);
          },
          loadPreview: _loadEmailPreview);
    if (question == 'payments') return _paymentSettings(d);
    switch (d['step'] as int) {
      case 0:
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (_loadingSources) const LinearProgressIndicator(),
          if (_sourceError != null)
            TextButton(
                onPressed: _loadSources,
                child: Text('$_sourceError Zkusit znovu')),
          RadioListTile<bool>(
              value: true,
              groupValue: !_copyEvent,
              title: Text(OccasionSetupStrings.story('newOccasion')),
              onChanged: (_) {
                setState(() => _copyEvent = false);
                _selectSource(null);
              }),
          RadioListTile<bool>(
              value: false,
              groupValue: !_copyEvent,
              title: Text(OccasionSetupStrings.story('copyOccasion')),
              onChanged: (_) {
                setState(() => _copyEvent = true);
                _pickSource();
              }),
          if (d['sourceId'] != null) Text(d['source'] as String),
          if (_copyEvent)
            OutlinedButton.icon(
                onPressed: _sources.isEmpty ? null : _pickSource,
                icon: const Icon(Icons.search),
                label: const Text('Vybrat předlohu')),
          if (_copyEvent && d['sourceId'] != null) ...[
            if (AppConfig.isAppSupported)
              _switch(d, 'copyProgram',
                  '${CommonStrings.schedule} a ${CommonStrings.places}'),
            if (AppConfig.isAppSupported)
              _switch(
                  d, 'copyInformation', 'FeatureInformation.information'.tr()),
            _switch(d, 'copyEmails', OccasionSetupStrings.story('copyEmails')),
          ],
          if (_loadingDetail) const LinearProgressIndicator(),
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
          const Text('Registrace probíhá přes formulář.'),
          _switch(d, 'copyProgram', 'Převzít program'),
          _switch(d, 'copyInformation', 'Převzít informace')
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
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (formBundle == null)
            ElevatedButton.icon(
              onPressed: _chooseForm,
              icon: const Icon(Icons.add),
              label: Text(OccasionSetupStrings.story('copyForm')),
            )
          else ...[
            if (d['formOrigin'] != null)
              Text('Převzato z události ${d['formOrigin']}'),
            _draftFormLink(d),
            const SizedBox(height: 10),
            const SizedBox(height: 12),
            Wrap(spacing: 10, children: [
              if (_sources.any((s) => (s['forms'] as List).isNotEmpty))
                OutlinedButton.icon(
                  onPressed: _chooseForm,
                  icon: const Icon(Icons.swap_horiz),
                  label: Text(OccasionSetupStrings.story('copyForm')),
                ),
            ]),
          ],
          if (_formUndo != null)
            TextButton(
                onPressed: _undoForm,
                child: Text(OccasionSetupStrings.story('undoCopy'))),
          if (formBundle != null) ...[
            const SizedBox(height: 18),
            FormEditorContent.prototype(
              key: ValueKey('${d['id']}-inline-form-$_formEpoch'),
              embedded: true,
              bundle: formBundle,
              onPrototypeHydrated: (saved) => _change((x) {
                x['formDraft'] = serializeDraftForm(saved.form);
                OccasionSetupBlueprint.normalizeForm(x);
              }, changesConfiguration: true, invalidateUndo: false),
              onPrototypeSave: (saved) => _change((x) {
                x['formDraft'] = serializeDraftForm(saved.form);
                OccasionSetupBlueprint.normalizeForm(x);
              }, changesConfiguration: true),
            ),
          ],
          const SizedBox(height: 14),
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
    const previewId = 0;
    return EditorDraftScope(
      onChanged: () => _change((x) => x['ticketDraft'] = feature.toJson(),
          changesConfiguration: true),
      child: TicketSettings(
        key: ValueKey('${d['id']}-ticket-$previewId-$_editEpoch'),
        feature: feature,
        occasionId: previewId,
        service: TicketLayoutService(transport: _draftTicketRequest),
        productEditing: false,
        borrowResourcesOnly: false,
        showTemplateGallery: true,
        showDeliverySelector: false,
        styleTemplate: !feature.deliveryMode.includesPdf ||
                !OccasionSetupAppearance.fonts
                    .containsKey(OccasionSetupAppearance.read(d)['fontFamily'])
            ? null
            : (template) {
                final json = template.toJson();
                OccasionSetupAppearance.styleTicketTemplate(
                    json, OccasionSetupAppearance.read(d));
                return TicketTemplate.fromJson(json);
              },
      ),
    );
  }

  Widget _paymentSettings(Map<String, dynamic> d) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (_loadingPayments) const LinearProgressIndicator(),
        if (_paymentError != null)
          TextButton(
              onPressed: _loadPayments,
              child: Text('$_paymentError Zkusit znovu')),
        DropdownButtonFormField<int>(
            key: ValueKey(
                '${d['id']}-bank-${(d['formDraft'] as Map?)?['bank_account']}'),
            initialValue: (d['formDraft'] as Map?)?['bank_account'] as int?,
            isExpanded: true,
            decoration:
                InputDecoration(labelText: 'BankAccount.bankAccount'.tr()),
            items: [
              if ((d['formDraft'] as Map?)?['bank_account'] != null &&
                  !_bankAccounts.any(
                      (a) => a.id == (d['formDraft'] as Map?)?['bank_account']))
                DropdownMenuItem<int>(
                    value: (d['formDraft'] as Map)['bank_account'] as int,
                    child: Text(OccasionSetupStrings.story('bankUnavailable'))),
              const DropdownMenuItem<int>(
                  value: null, child: Text('Automaticky podle měny')),
              ..._bankAccounts.map((a) => DropdownMenuItem(
                  value: a.id,
                  child: Text(
                      '${a.title ?? a.accountNumber} (${a.supportedCurrencies.join(', ')})')))
            ],
            onChanged: (id) => _change(
                (x) => (x['formDraft'] as Map)['bank_account'] = id,
                changesConfiguration: true)),
        for (final currency in _paidCurrencies(d))
          Text(_paymentRouteLabel(d, currency)),
        const SizedBox(height: 10),
        OutlinedButton.icon(
            onPressed: () async {
              if (!await _flush() || !mounted) return;
              await Navigator.of(context).push<void>(MaterialPageRoute(
                  builder: (_) =>
                      UnitBankAccountsScreen(unitId: _stored.unit)));
              if (mounted) await _loadPayments();
            },
            icon: const Icon(Icons.account_balance),
            label: Text(OccasionSetupStrings.story('manageBanks'))),
      ]);

  Widget _blueprintSettings(Map<String, dynamic> d) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final mode in [
        'new',
        if (_sources.any((s) => (s['blueprints'] as List).isNotEmpty)) 'copy'
      ])
        RadioListTile<String>(
            value: mode,
            groupValue: OccasionSetupBlueprint(d).modeId,
            title: Text(OccasionSetupStrings.story('blueprint.$mode')),
            onChanged: (value) {
              if (value == 'copy') {
                _selectBlueprint();
                return;
              }
              if (value == 'new') {
                _newBlueprint();
                return;
              }
              _change((x) => OccasionSetupBlueprint(x).clear(),
                  changesConfiguration: true);
            }),
      if (_blueprintError != null) ...[
        Text(_blueprintError!),
        TextButton(
            onPressed: _selectBlueprint, child: const Text('Zkusit znovu')),
      ],
      if (OccasionSetupBlueprint(d).mode != SetupBlueprintMode.none) ...[
        if (OccasionSetupBlueprint(d).seatCount > 0)
          Text('${OccasionSetupBlueprint(d).seatCount} míst v plánu'),
        const SizedBox(height: 12),
        ElevatedButton.icon(
            onPressed: _openBlueprint,
            icon: const Icon(Icons.grid_on),
            label: Text(OccasionSetupStrings.story('editBlueprint'))),
        const SizedBox(height: 12),
        const Text('Úpravy plánku se ukládají do tohoto konceptu.'),
      ],
    ]);
  }

  Future<void> _jump(String key) async {
    final target = _questions.indexWhere((q) => q.key == key);
    if (target < 0 || _finalizeCommand != null) return;
    FocusManager.instance.primaryFocus?.unfocus();
    _change((d) => _goToQuestion(d, target));
    await _flush();
  }

  String _shortLabel(String key) =>
      const {
        'source': 'Kopie',
        'name': 'Název',
        'dates': 'Termín',
        'kind': 'Typ',
        'appearance': 'Vzhled',
        'link': 'Odkaz',
        'content': 'Obsah',
        'form': 'Formulář',
        'saleTiming': 'Otevření',
        'payments': 'Platby',
        'paymentTiming': 'Splatnost',
        'communication': 'Komunikace',
        'blueprint': 'Sál',
        'verification': 'Ověření',
        'review': 'Kontrola',
      }[key] ??
      key;
  String _questionTitle(String key) =>
      const {
        'dates': 'Kdy se koná?',
        'kind': 'Jaký typ akce připravuješ?',
        'appearance': 'Jak má akce vypadat?',
        'blueprint': 'Jak bude vypadat sál?',
      }[key] ??
      OccasionSetupStrings.story('${key}Question');
  String _kindLabel(Map d) => const {
        'regular': 'Běžná akce · přihlášení přes formulář',
        'concert': 'Koncert · vstupenky bez výběru míst',
        'ball': 'Ples · vstupenky a rezervace míst',
      }[OccasionSetupStory.kind(d)]!;

  Widget _kindSettings(Map<String, dynamic> d) => Column(children: [
        for (final kind in OccasionSetupStory.kinds)
          RadioListTile<String>(
              value: kind,
              groupValue: d['eventKindNeedsConfirmation'] == true
                  ? null
                  : d['eventKind'] as String?,
              title: Text(const {
                'regular': 'Běžná akce',
                'concert': 'Koncert',
                'ball': 'Ples'
              }[kind]!),
              subtitle: Text(const {
                'regular': 'Přihlášení účastníků přes formulář.',
                'concert': 'Vstupenky bez výběru konkrétního místa.',
                'ball': 'Vstupenky s rezervací konkrétních míst v sále.'
              }[kind]!),
              onChanged: (value) {
                _change((x) {
                  x['eventKind'] = value;
                  x['eventKindNeedsConfirmation'] = false;
                  x['pathNotice'] = true;
                  _inlineFormBundle = null;
                  _formEpoch++;
                }, changesConfiguration: true);
              }),
        if (d['pathNotice'] == true)
          const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                  'Tok odpovídá vybranému typu. Neaktivní nastavení zůstává v konceptu a při vytvoření se nepoužije.')),
      ]);

  Future<Map<String, dynamic>> _draftTicketRequest(
      Map<String, dynamic> body) async {
    if (!await _flush())
      throw StateError('Koncept není uložený. Zkus uložení znovu.');
    body = Map.of(body)..remove('occasionId');
    final response = await Supabase.instance.client.functions
        .invoke('preview-ticket-layout', body: {
      ...body,
      'draftId': _stored.id,
      'draftRevision': _stored.revision,
    });
    if (response.status != 200 || response.data is! Map)
      throw StateError('Náhled nelze načíst. Zkus to znovu.');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Widget _appearanceSettings(Map<String, dynamic> d) {
    final a = OccasionSetupAppearance.read(d);
    Color color(dynamic hex) => Color(int.parse('ff$hex', radix: 16));
    String hex(Color c) =>
        c.toARGB32().toRadixString(16).substring(2).toUpperCase();
    void apply(Map<String, dynamic> next) {
      if (!OccasionSetupAppearance.fonts.containsKey(next['fontFamily'])) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text('Nejdřív vyber písmo podporované formulářem i PDF.')));
        return;
      }
      _change((x) => OccasionSetupAppearance.apply(x, next),
          changesConfiguration: true);
      setState(() {
        _inlineFormBundle = null;
        _ticketFeature = null;
        _editEpoch++;
      });
    }

    void custom(String key, dynamic value) =>
        apply({...a, 'id': 'custom', key: value});
    return OccasionSetupAppearancePanel(
      presets: [
        for (final p in OccasionSetupAppearance.presets)
          OccasionSetupAppearancePreset(
              id: p['id'] as String,
              label: p['label'] as String,
              primaryColor: color(p['primary']),
              secondaryColor: color(p['secondary']),
              gradient: p['gradient'] as bool,
              fontFamily: p['fontFamily'] as String)
      ],
      selectedPresetId: a['id'] as String?,
      onPresetSelected: (id) => apply(Map<String, dynamic>.from(
          OccasionSetupAppearance.presets.firstWhere((p) => p['id'] == id))),
      fontFamily: a['fontFamily'] as String,
      fontFamilies: {
        ...OccasionSetupAppearance.fonts.keys,
        a['fontFamily'] as String
      }.toList(),
      onFontChanged: (v) => custom('fontFamily', v),
      primaryColor: color(a['primary']),
      secondaryColor: color(a['secondary']),
      gradient: a['gradient'] as bool,
      onPrimaryChanged: (v) => custom('primary', hex(v)),
      onSecondaryChanged: (v) => custom('secondary', hex(v)),
      onGradientChanged: (v) => custom('gradient', v),
      formPreview: OccasionSetupFormPreview(
          key: ValueKey('form-preview-$_editEpoch'), draft: d),
      ticketSettings: OccasionSetupStory.tickets(d) ? _ticketSettings(d) : null,
    );
  }

  Widget _wizard(Map<String, dynamic> d) {
    final step = d['step'] as int;
    final index = _questionIndex(d);
    final question = _questions[index];
    final numbered = _questions.where((q) => !q.optional).toList();
    final number = numbered.indexWhere((q) => q.key == question.key) + 1;
    final isReview = question.key == 'review';
    final reviewReady = isReview && _reviewIssues(d).isEmpty;
    final isEditor = question.key == 'form' || question.key == 'appearance';
    return OccasionSetupStoryShell(
      questionNumbers: [
        for (final q in _questions)
          q.optional ? null : numbered.indexWhere((n) => n.key == q.key) + 1
      ],
      questionKeys: [for (final q in _questions) q.key],
      questionLabels: [for (final q in _questions) _shortLabel(q.key)],
      questionSections: [
        for (final q in _questions)
          q.step == 5
              ? 'Dokončení'
              : ['name', 'dates', 'kind', 'appearance', 'link', 'source']
                      .contains(q.key)
                  ? 'Základy'
                  : OccasionSetupStory.tickets(d)
                      ? 'Prodej'
                      : 'Registrace'
      ],
      completedKeys: {
        for (final q in _questions)
          if (!q.optional && _questionReady(d, q)) q.key
      },
      visitedKeys:
          (d['visitedQuestions'] as List? ?? []).cast<String>().toSet(),
      onQuestionSelected: _finalizeCommand != null ? null : _jump,
      contextLabel: _kindLabel(d),
      introductionAction:
          (_sources.isNotEmpty || _loadingSources || _sourceError != null)
              ? TextButton(
                  onPressed: () {
                    if (_showSource) {
                      _jump('name');
                    } else {
                      _change((x) {
                        x['storyQuestion'] = 'source';
                        x['step'] = 0;
                      });
                    }
                  },
                  child: Text(_loadingSources
                      ? 'Načítání předloh'
                      : _sourceError ?? 'Vytvořit kopii události'))
              : null,
      questionTitles: [
        for (final item in _questions) _questionTitle(item.key),
      ],
      currentIndex: index,
      eventTitle:
          '${OccasionSetupStrings.story('draft')} · ${(d['title'] as String).trim().isEmpty ? OccasionSetupStrings.untitled : d['title']}',
      status: _error != null
          ? OccasionSetupStrings.saveFailed
          : _pending != null || _dirty
              ? OccasionSetupStrings.saving
              : OccasionSetupStrings.saved,
      readiness: OccasionSetupStrings.readiness(_progress(d)),
      questionCount: question.optional
          ? 'Nepovinná část'
          : OccasionSetupStrings.questionNumber(number, numbered.length),
      segmentStates: [
        OccasionSetupStrings.story('completedQuestion'),
        OccasionSetupStrings.story('currentQuestion'),
        OccasionSetupStrings.story('upcomingQuestion'),
      ],
      leaveLabel: OccasionSetupStrings.story('leave'),
      backLabel: CommonStrings.back,
      onLeave: _pending != null ? null : _leave,
      onBack: index == 0 ? null : () => _jump(_questions[index - 1].key),
      maxContentWidth: question.key == 'appearance'
          ? 1120
          : step == 3
              ? StylesConfig.formMaxWidth
              : isReview || question.optional
                  ? 960
                  : 680,
      centerQuestion: !isEditor && !isReview && !question.optional,
      error: _error == null
          ? null
          : Row(children: [
              Expanded(
                  child: Text(_error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error))),
              TextButton(
                onPressed:
                    _pending != null ? null : (_conflict ? _reload : _flush),
                child: Text(_conflict
                    ? OccasionSetupStrings.reload
                    : OccasionSetupStrings.retry),
              ),
            ]),
      primaryAction: FilledButton(
        style: FilledButton.styleFrom(minimumSize: const Size(160, 48)),
        onPressed: isReview
            ? d['reviewed'] == true
                ? (_finalizing || !reviewReady ? null : _finalize)
                : (reviewReady && d['reviewConfirmed'] == true ? _review : null)
            : _advance,
        child: Text(
          isReview
              ? d['reviewed'] == true
                  ? OccasionSetupStrings.createEvent
                  : 'Potvrdit kontrolu'
              : question.optional
                  ? OccasionSetupStrings.story('skipVerification')
                  : CommonStrings.continueAction,
          textAlign: TextAlign.center,
        ),
      ),
      child: _body(d),
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: _allowPop,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _leave();
        },
        child: Scaffold(
          body: _finalizeCommand == null
              ? _wizard(_data)
              : Center(
                  child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        if (_finalizing) const CircularProgressIndicator(),
                        Text(_finalizeError ?? OccasionSetupStrings.saving),
                        if (!_finalizing) ...[
                          ElevatedButton(
                              onPressed: _finalize,
                              child: Text(OccasionSetupStrings.retry)),
                          TextButton(
                              onPressed: _leave,
                              child: Text(CommonStrings.back)),
                        ],
                      ]))),
        ),
      );
}
