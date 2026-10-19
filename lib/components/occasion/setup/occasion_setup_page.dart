import 'package:fstapp/components/forms/models/form_bundle.dart';
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
import 'package:fstapp/components/blueprint/blueprint_configuration.dart';
import 'package:fstapp/components/blueprint/blueprint_group.dart';
import 'package:fstapp/components/blueprint/blueprint_model.dart';
import 'package:fstapp/components/blueprint/blueprint_object_model.dart';
import 'package:fstapp/components/blueprint/views/blueprint_editor_tab.dart';
import 'package:festapp_core/eshop.dart';
import 'package:fstapp/components/forms/models/form_editor_draft.dart';
import 'package:fstapp/components/forms/views/create_or_copy_dialog.dart';
import 'package:fstapp/components/forms/views/form_editor_content.dart';
import 'package:fstapp/components/forms/widgets_view/form_helper.dart';
import 'package:fstapp/components/forms/views/form_public_link.dart';
import 'package:fstapp/components/forms/form_strings.dart';
import 'package:fstapp/widgets/time_data_range_picker.dart';

import 'occasion_form_draft.dart';

import 'package:fstapp/components/forms/views/form_variable_symbol_settings.dart';

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
import 'occasion_setup_presentation.dart';
import 'occasion_setup_form_link.dart';
import 'occasion_setup_pricing.dart';
import 'occasion_setup_bank_account.dart';
import 'occasion_setup_communication.dart';
import 'occasion_setup_invitations.dart';

import 'package:fstapp/components/users/occasion_team_invitation_strings.dart';
import 'package:fstapp/components/ticket_layout/views/ticket_scanning_settings.dart';
import 'package:fstapp/components/ticket_layout/ticket_layout_service.dart';

import 'package:fstapp/components/unit/verification/db_unit_verification.dart';
import 'package:fstapp/components/unit/verification/unit_legal_profile.dart';
import 'package:fstapp/components/unit/verification/verification_strings.dart';
import 'package:fstapp/components/unit/verification/unit_legal_profile_section.dart';
import 'package:fstapp/data_services/rights_service.dart';
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
    BuildContext context,
    OccasionSetupDraft draft,
  ) async {
    final initialized = await ExceptionHandler.guard(
      context,
      futureFunction: () => OccasionSetupDrafts(Supabase.instance.client)
          .initializeDefaults(draft),
    );
    if (initialized == null || !context.mounted) return;
    final link = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => OccasionSetupPage(draft: initialized)),
    );
    if (link != null && context.mounted) {
      await RouterService.navigateToOccasionAdministration(
        context,
        occasionLink: link,
      );
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
  String? _sourceError;
  bool _loadingSources = true;
  UnitLegalProfile? _organizerProfile;
  bool? _formLinkAvailable;
  bool _presentationUploading = false;
  Future<void>? _verificationRefresh;
  Timer? _debounce;
  Future<bool>? _pending;
  bool _dirty = false;
  bool _allowPop = false;
  bool _conflict = false;
  String? _error;
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
          DateTime.now().add(const Duration(days: 30)).toIso8601String(),
      'end': _stored.data['end_time'] ??
          DateTime.now().add(const Duration(days: 33)).toIso8601String(),
      'source': 'Od nuly',
      'copyProgram': false,
      'copyInformation': false,
      'copyEmails': false,
      'formEnabled': true,
      'formOrigin': null,
      'formDraft': null,
      'deadline': '',
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
    _data.putIfAbsent(
      'formLinkAutomatic',
      () => ((_data['formDraft'] as Map?)?['link'] as String? ?? '').isEmpty,
    );
    _ensureDefaultForm(_data);
    initializeCommunicationDraft(_data);
    _restrictToSupportedFeatures(_data);
    _linkController = TextEditingController(text: _data['link'] as String);
    _loadSources();
    _refreshVerification();
  }

  Future<void> _refreshVerification() =>
      _verificationRefresh ??= _loadVerification().whenComplete(() {
        _verificationRefresh = null;
      });

  Future<void> _loadVerification() async {
    try {
      final profile = await DbUnitVerification().get(_stored.unit);
      if (!mounted) return;
      // Recompute from the stable question key at completion, never from an
      // index captured before the request. Other in-flight navigation wins.
      final wasVerification = _data['storyQuestion'] == 'verification';
      setState(() => _organizerProfile = profile);
      if (profile.status == 'verified' && wasVerification) {
        _change((d) => d['storyQuestion'] = 'review');
      }
    } catch (_) {
      // Unknown verification must retain the optional verification question.
      if (mounted) setState(() => _organizerProfile = null);
    }
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
        params: {'p_unit': _data['sourceUnitId'] ?? _stored.unit},
      );
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

  List<FormEditorDraft> get _sourceForms => [
        for (final source in _sources)
          for (final raw in source['forms'] as List)
            FormEditorDraft.fromJson(Map<String, dynamic>.from(raw))
              ..occasionModel = OccasionModel.fromJson(
                Map<String, dynamic>.from(source['occasion']),
              ),
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
    draft['formDraft'] = serializeDraftForm(
      defaultDraftForm(
        Map<String, dynamic>.from(draft['defaultConfiguration'] as Map),
      ),
    );
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

  void _resetBankAccount(Map<String, dynamic> draft) {
    draft.remove('bankAccountId');
    draft.remove('bankAccountLabel');
    draft['bankAccountConfirmed'] = false;
  }

  void _applySource(Map<String, dynamic> draft, String label) {
    _formLinkAvailable = null;
    _resetBankAccount(draft);
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
      draft['formDraft'] = jsonDecode(jsonEncode(forms.first));
      (draft['formDraft'] as Map)['link'] = '';
      draft['formLinkAutomatic'] = true;
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
        seconds == null ? '' : (seconds / 86400).round().toString();
    initializeCommunicationDraft(draft, reset: true);
  }

  void _persistFormControls(Map<String, dynamic> draft) {
    final form = draft['formDraft'];
    if (form is! Map) return;
    final days = int.tryParse(draft['deadline'] as String? ?? '');
    form['deadline_duration_seconds'] = days == null ? null : days * 86400;
    serializeCommunicationDraft(draft);
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

  void _change(
    void Function(Map<String, dynamic>) update, {
    bool changesConfiguration = false,
  }) {
    if (_finalizeCommand != null) return;
    setState(() {
      final oldTitle = _data['title'];
      final oldFormLink = (_data['formDraft'] as Map?)?['link'];
      final oldCurrencies = OccasionSetupStory.paymentCurrencies(_data);
      update(_data);
      if (_data['title'] != oldTitle &&
          _data['formLinkAutomatic'] != false &&
          _data['formDraft'] is Map) {
        (_data['formDraft'] as Map)['link'] = '';
        _inlineFormBundle?.form.definition =
            _inlineFormBundle!.form.definition.copyWith(link: '');
      }
      final newCurrencies = OccasionSetupStory.paymentCurrencies(_data);
      if (oldCurrencies.length != newCurrencies.length ||
          !oldCurrencies.containsAll(newCurrencies)) {
        _resetBankAccount(_data);
      }
      if ((_data['formDraft'] as Map?)?['link'] != oldFormLink)
        _formLinkAvailable = null;
      if (_data['formDefaultsFollowEvent'] == true &&
          _data['formDraft'] is Map) {
        final form = _data['formDraft'] as Map;
        if (_data['title'] != oldTitle &&
            (_data['title'] as String).isNotEmpty) {
          form['title'] = _data['title'];
          _inlineFormBundle?.form.definition = _inlineFormBundle!
              .form.definition
              .copyWith(title: _data['title']);
        }
      }
      _restrictToSupportedFeatures(_data);
      if (changesConfiguration) _persistFormControls(_data);
      if (changesConfiguration) {
        _data['reviewed'] = false;
        _data['reviewConfirmed'] = false;
        (_data['completed'] as List).remove(5);
        for (final step in OccasionSetupDraft.supportedSteps.where(
          (s) => s != 5,
        )) {
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
        // Adopt server-owned copy title without overwriting typing during save.
        if (_data['title'] == snapshot['title'] &&
            _data['copy_title_edited'] != true &&
            _stored.data['title'] != snapshot['title']) {
          _data['title'] = _stored.data['title'];
          _editEpoch++;
        }
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

  Future<void> _finalize() async {
    if (_finalizing) return;
    setState(() {
      _finalizing = true;
      _finalizeError = null;
    });
    var eventCreated = false;
    try {
      if (_finalizeCommand == null) {
        if (!await _flush() || !mounted) return;
        _finalizeDraft = _stored;
        _finalizeCommand = OccasionSetupDrafts.newId();
      }
      final link = await _store.finalize(_finalizeDraft!, _finalizeCommand!);
      eventCreated = true;
      if (_finalizeDraft!.data['sendTeamInvitations'] == true &&
          occasionSetupInviteEmails(_finalizeDraft!.data).isNotEmpty) {
        final result = await Supabase.instance.client.functions.invoke(
          'send-occasion-team-invitations',
          body: {'draftId': _finalizeDraft!.id},
        );
        if (result.status != 200 ||
            result.data is! Map ||
            result.data['complete'] != true) {
          if (mounted)
            setState(
              () => _finalizeError = OccasionTeamInvitationStrings.text(
                'sendFailed',
              ),
            );
          return;
        }
      }
      if (!mounted) return;
      setState(() => _allowPop = true);
      Navigator.of(context).pop(link);
    } catch (_) {
      if (mounted)
        setState(
          () => _finalizeError = eventCreated
              ? OccasionTeamInvitationStrings.text('sendFailed')
              : OccasionSetupStrings.finalizeFailed,
        );
    } finally {
      if (mounted) setState(() => _finalizing = false);
    }
  }

  Future<void> _leave() async {
    if (_presentationUploading) return;
    if (_finalizing) return;
    if (_finalizeCommand != null) {
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
    final confirmed = await DialogHelper.showConfirmationDialog(
      context,
      OccasionSetupStrings.reload,
      OccasionSetupStrings.reloadConfirm,
    );
    if (confirmed != true || !mounted) return;
    try {
      final rows = await _store.list(_stored.unit);
      final current = rows.firstWhere((d) => d.id == _stored.id);
      if (!mounted) return;
      setState(() {
        _stored = current;
        _data = Map.of(current.data);
        _formLinkAvailable = null;
        _data.putIfAbsent(
          'formLinkAutomatic',
          () =>
              ((_data['formDraft'] as Map?)?['link'] as String? ?? '').isEmpty,
        );
        _inlineFormBundle = null;
        _ensureDefaultForm(_data);
        initializeCommunicationDraft(_data);
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

  bool _stepReady(
    Map<String, dynamic> d,
    int step, {
    bool includePricing = true,
    bool includePayments = true,
    bool includeCommunication = true,
  }) {
    if (!OccasionSetupStory.applicableSteps(
      d,
      AppConfig.isAppSupported,
    ).contains(step)) return true;
    switch (step) {
      case 0:
        return true;
      case 1:
        final start = DateTime.tryParse(d['start'] as String);
        final end = DateTime.tryParse(d['end'] as String);
        return (d['title'] as String).trim().isNotEmpty &&
            (d['isPromoted'] != true ||
                (d['introImage'] as String? ?? '').trim().isNotEmpty) &&
            isValidPublicSlug(d['link'] as String, allowEmpty: true) &&
            start != null &&
            end != null &&
            !end.isBefore(start);
      case 2:
        return true;
      case 3:
        if (d['formEnabled'] == false) return true;
        if (includeCommunication && !communicationDraftValid(d)) return false;
        if (_formLinkAvailable == false ||
            (includePricing &&
                OccasionSetupStory.pricingIssueKeys(
                  d,
                  DateTime.now(),
                ).isNotEmpty)) return false;
        if (includePayments &&
            AppConfig.isAppSupported &&
            OccasionSetupStory.hasPaidProducts(d) &&
            !_paymentsReady(d)) return false;
        final formData = d['formDraft'];
        if (formData is! Map) return false;
        return (formData['title'] as String? ?? '').trim().isNotEmpty &&
            isValidPublicSlug(
              formData['link'] as String? ?? '',
              allowEmpty: true,
            ) &&
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
      _deadlineReady(d) &&
      (!OccasionSetupStory.hasPaidProducts(d) ||
          OccasionSetupStory.paymentAccountConfirmed(d));

  bool _deadlineReady(Map<String, dynamic> d) =>
      (d['deadline'] as String? ?? '').trim().isEmpty ||
      (int.tryParse(d['deadline'] as String? ?? '') ?? -1) >= 0;

  int _progress(Map<String, dynamic> d) {
    return ((OccasionSetupDraft.completedCount(d) /
                OccasionSetupStory.applicableSteps(
                  d,
                  AppConfig.isAppSupported,
                ).length) *
            100)
        .round();
  }

  List<OccasionSetupQuestion> get _questions => OccasionSetupStory.questions(
        AppConfig.isAppSupported,
        data: _data,
        organizationVerified: _organizerProfile?.status == 'verified',
      );

  int _questionIndex(Map<String, dynamic> d) => OccasionSetupStory.index(
        d,
        AppConfig.isAppSupported,
        organizationVerified: _organizerProfile?.status == 'verified',
      );

  void _goToQuestion(Map<String, dynamic> d, int index) {
    final question = _questions[index];
    d['step'] = question.step;
    d['storyQuestion'] = question.key;
  }

  bool _questionReady(Map<String, dynamic> d, OccasionSetupQuestion q) {
    if (q.optional) return true;
    if (q.key == 'form')
      return _stepReady(
        d,
        3,
        includePricing: false,
        includePayments: false,
        includeCommunication: false,
      );
    if (q.key == 'pricing')
      return _stepReady(
        d,
        3,
        includePayments: false,
        includeCommunication: false,
      );
    if (q.key == 'payments')
      return OccasionSetupStory.paymentAccountConfirmed(d);
    if (q.key == 'paymentTiming')
      return _deadlineReady(d) &&
          communicationDraftValid(d, includeReply: false);
    if (q.key == 'communication')
      return communicationDraftValid(d, includeReminders: false) &&
          _stepReady(d, q.step, includeCommunication: false);
    if (q.step != 1) return _stepReady(d, q.step);
    switch (q.key) {
      case 'name':
        return (d['title'] as String).trim().isNotEmpty;
      case 'promotion':
      case 'presentation':
        return d['isPromoted'] != true ||
            (d['introImage'] as String? ?? '').trim().isNotEmpty;
      case 'dates':
        final start = DateTime.tryParse(d['start'] as String);
        final end = DateTime.tryParse(d['end'] as String);
        return start != null && end != null && !end.isBefore(start);
      default:
        return isValidPublicSlug(d['link'] as String, allowEmpty: true);
    }
  }

  void _advance() {
    if (_presentationUploading) return;
    final d = _active!;
    final index = _questionIndex(d);
    final question = _questions[index];
    if (index == _questions.length - 1) return;
    if (!_questionReady(d, question)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(OccasionSetupStrings.story('incomplete'))),
      );
      return;
    }
    _change((x) {
      if (OccasionSetupStory.completesRequiredStep(_questions, index) &&
          !(x['completed'] as List).contains(question.step)) {
        (x['completed'] as List).add(question.step);
      }
      _goToQuestion(x, index + 1);
    });
    if (question.key == 'verification') _refreshVerification();
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
          SnackBar(content: Text('Ještě není dokončen krok ${_steps[step]}.')),
        );
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
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: Text('${CommonStrings.blueprint} · návrh události'),
          ),
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
      ),
    );
  }

  BlueprintModel _planFromDraft(Map<String, dynamic> d) {
    final groups = (d['blueprintGroups'] as List)
        .map(
          (g) =>
              BlueprintGroupModel.fromJson(Map<String, dynamic>.from(g as Map)),
        )
        .toList();
    final objects = (d['blueprintObjects'] as List)
        .map(
          (o) => BlueprintObjectModel.fromJson(
            Map<String, dynamic>.from(o as Map),
          ),
        )
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
        height: d['blueprintHeight'] as int,
      ),
      objects: objects,
      groups: groups,
      products: products,
    );
    plan.assignAllSpotsWithBlueprint();
    return plan;
  }

  Widget _choice(
    Map<String, dynamic> d,
    String keyName,
    String label,
    List<String> options,
  ) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: DropdownButtonFormField<String>(
          key: ValueKey('${d['id']}-$keyName-${d[keyName]}'),
          initialValue: d[keyName] as String,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
          ),
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
          content: const Text(
            'Dosavadní úpravy formuláře se při výměně zahodí.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(CommonStrings.back),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('Common.confirm'.tr()),
            ),
          ],
        ),
      );
      if (replace != true || !mounted) return;
    }
    final result = await showDialog<dynamic>(
      context: context,
      builder: (context) => CreateOrCopyFormDialog(
        existingForms: _sourceForms.map((form) => form.toBundle()).toList(),
      ),
    );
    if (!mounted || result == null) return;
    final form = result is FormBundle
        ? FormEditorDraft.fromBundle(result)
        : defaultDraftForm(
            Map<String, dynamic>.from(_data['defaultConfiguration'] as Map),
          );
    _change((draft) {
      _resetBankAccount(draft);
      _formEpoch++;
      _formLinkAvailable = null;
      _inlineFormBundle = null;
      draft['formDefaultsFollowEvent'] = false;
      draft['formDraft'] = serializeDraftForm(form);
      (draft['formDraft'] as Map)['link'] = '';
      draft['formLinkAutomatic'] = true;
      _adoptFormSettings(draft);
      draft['formOrigin'] =
          result is FormBundle ? form.occasionModel?.title : null;
      if (result is FormBundle && form.definition.blueprint != null) {
        for (final source in _sources) {
          final plans = source['blueprints'] as List;
          final selected = plans
              .where((p) => (p as Map)['id'] == form.definition.blueprint)
              .firstOrNull;
          if (selected is Map) _applyBlueprint(draft, selected);
        }
      }
    }, changesConfiguration: true);
  }

  Widget _formTextField(
    Map<String, dynamic> draft,
    String field,
    String label,
  ) {
    final form = Map<String, dynamic>.from(draft['formDraft'] as Map);
    return TextFormField(
      key: ValueKey('${draft['id']}-form-$_formEpoch-$field'),
      initialValue: form[field] as String? ?? '',
      decoration: InputDecoration(labelText: label),
      onChanged: (value) => _change((x) {
        x['formDefaultsFollowEvent'] = false;
        (x['formDraft'] as Map)[field] = value;
        if (field == 'title')
          _inlineFormBundle?.form.definition =
              _inlineFormBundle!.form.definition.copyWith(title: value);
        if (field == 'link')
          _inlineFormBundle?.form.definition =
              _inlineFormBundle!.form.definition.copyWith(link: value);
      }, changesConfiguration: true),
    );
  }

  Widget _basics(Map<String, dynamic> d) {
    final question = _questions[_questionIndex(d)].key;
    if (question == 'presentation') {
      return OccasionSetupPresentation(
        onBusyChanged: (value) {
          if (mounted) setState(() => _presentationUploading = value);
        },
        unitId: _stored.unit,
        data: d,
        onChanged: (patch) =>
            _change((x) => x.addAll(patch), changesConfiguration: true),
      );
    }
    if (question == 'name') {
      return TextFormField(
        key: ValueKey('${d['id']}-title-$_editEpoch'),
        initialValue: d['title'] as String,
        decoration: InputDecoration(
          labelText: AdministrationStrings.titleLabel,
        ),
        onChanged: (value) => _change((x) {
          x['title'] = value;
          x['copy_title_edited'] = true;
        }, changesConfiguration: true),
      );
    }
    if (question == 'link') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            controller: _linkController,
            decoration: InputDecoration(
              labelText: AdministrationStrings.linkLabel,
            ),
            onChanged: (value) =>
                _change((x) => x['link'] = value, changesConfiguration: true),
          ),
          const SizedBox(height: 16),
          PublicLink(link: d['link'] as String, isForm: false),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _dateFields(d, 'start'),
        const SizedBox(height: 24),
        _dateFields(d, 'end'),
      ],
    );
  }

  Widget _dateFields(Map<String, dynamic> d, String question) {
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TimeDatePicker(
          date: value,
          time: value == null ? null : TimeOfDay.fromDateTime(value),
          dateLabel: OccasionSetupStrings.story(
            isStart ? 'startDate' : 'endDate',
          ),
          timeLabel: OccasionSetupStrings.story(
            isStart ? 'startTime' : 'endTime',
          ),
          minDate: DateTime(2000),
          maxDate: DateTime(2101),
          isValid: value != null &&
              (isStart || start == null || !value.isBefore(start)),
          onDateChanged: (day) => update(
            DateTime(
              day.year,
              day.month,
              day.day,
              value?.hour ?? 0,
              value?.minute ?? 0,
            ),
          ),
          onTimeChanged: (time) {
            final day = value ?? DateTime.now();
            update(
              DateTime(day.year, day.month, day.day, time.hour, time.minute),
            );
          },
        ),
        if (!isStart && value != null && start != null && value.isBefore(start))
          Text(
            OccasionSetupStrings.story('endBeforeStart'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    );
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
      issues.add(const MapEntry(1, 'Začátek a konec události nejsou platné.'));
    }
    if (d['formEnabled'] == true) {
      if (!communicationDraftValid(d))
        issues.add(
          MapEntry(3, OccasionSetupStrings.story('communicationIncomplete')),
        );
      if (_formLinkAvailable == false)
        issues.add(
          MapEntry(3, OccasionSetupStrings.story('formLinkUnavailable')),
        );
      for (final key in OccasionSetupStory.pricingIssueKeys(
        d,
        DateTime.now(),
      )) {
        issues.add(MapEntry(3, OccasionSetupStrings.story(key)));
      }
      final formData = d['formDraft'];
      if (formData is! Map) {
        issues.add(
          const MapEntry(
            3,
            'Chybí formulář. Je nutné jej založit nebo převzít.',
          ),
        );
      } else {
        final form = draftFormBundle(Map<String, dynamic>.from(formData));
        if ((form.form.definition.title ?? '').trim().isEmpty ||
            !isValidPublicSlug(
              form.form.definition.link ?? '',
              allowEmpty: true,
            )) {
          issues.add(
            const MapEntry(3, 'Chybí název nebo platný odkaz formuláře.'),
          );
        }
        if (form.form.relatedFields
            .where((field) => field.definition.isTicketField != true)
            .isEmpty) {
          issues.add(const MapEntry(3, 'Formulář nemá žádná pole.'));
        }
        if (form.form.relatedFields.any(
              (field) => field.definition.type == FormMetadata.fieldTypeTicket,
            ) &&
            form.products.isEmpty) {
          issues.add(
            const MapEntry(3, 'Formulář se vstupenkami nemá produkty.'),
          );
        }
      }
    }
    if (OccasionSetupStory.formEnabled(d) &&
        d['blueprintMode'] != 'Bez plánku') {
      if (d['formEnabled'] != true || d['formDraft'] == null) {
        issues.add(
          MapEntry(
            AppConfig.isAppSupported ? 4 : 6,
            'Plánek potřebuje formulář.',
          ),
        );
      }
      if ((d['blueprintObjects'] as List).isEmpty) {
        issues.add(
          MapEntry(
            AppConfig.isAppSupported ? 4 : 6,
            'Plánek zatím nemá žádná místa.',
          ),
        );
      }
    }
    if (OccasionSetupStory.hasPaidProducts(d) &&
        !OccasionSetupStory.paymentAccountConfirmed(d)) {
      issues.add(
        MapEntry(
          AppConfig.isAppSupported ? 3 : 4,
          OccasionSetupStrings.story('bankAccountRequired'),
        ),
      );
    }
    if (OccasionSetupStory.hasPaidProducts(d) && !_deadlineReady(d)) {
      issues.add(
        MapEntry(
          AppConfig.isAppSupported ? 3 : 4,
          'Splatnost musí být nezáporný počet dní, nebo pole ponechte prázdné.',
        ),
      );
    }
    if (d['isPromoted'] == true &&
        (d['introImage'] as String? ?? '').trim().isEmpty) {
      issues.add(
        MapEntry(1, OccasionSetupStrings.story('promotionImageRequired')),
      );
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
        child: LayoutBuilder(
          builder: (context, constraints) {
            final labelWidget = Text(
              label,
              style: Theme.of(context).textTheme.bodySmall,
            );
            if (constraints.maxWidth < 540) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [labelWidget, SelectableText(value)],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 205, child: labelWidget),
                Expanded(child: SelectableText(value)),
              ],
            );
          },
        ),
      );

  Widget _reviewSection(
    Map<String, dynamic> d,
    int step,
    String title,
    List<Widget> children,
    List<MapEntry<int, String>> issues, {
    String? questionKey,
  }) {
    final hasIssue = issues.any((issue) => issue.key == step) ||
        (step == 5 && d['reviewed'] != true);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? Colors.grey[850]
            : Colors.white,
        border: Border.all(
          color: hasIssue
              ? Theme.of(context).colorScheme.error
              : Theme.of(context).colorScheme.outlineVariant,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                hasIssue ? Icons.error_outline : Icons.check_circle_outline,
                color: hasIssue
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (step != 5 &&
                  OccasionSetupStory.applicableSteps(
                    d,
                    AppConfig.isAppSupported,
                  ).contains(step))
                TextButton.icon(
                  onPressed: () => _change((x) {
                    x['step'] = step;
                    if (questionKey != null) x['storyQuestion'] = questionKey;
                  }),
                  icon: const Icon(Icons.edit_outlined, size: 17),
                  label: Text(CommonStrings.edit),
                ),
            ],
          ),
          const Divider(),
          ...children,
        ],
      ),
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
    final applicable = OccasionSetupStory.applicableSteps(
      d,
      AppConfig.isAppSupported,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text(
          '${applicable.length - 1 - issues.map((issue) => issue.key).toSet().length} z ${applicable.length - 1} nastavení bez chyby · ${OccasionSetupDraft.completedCount(d)} z ${applicable.length} kroků potvrzeno${d['reviewed'] == true ? '' : ' · čeká finální kontrola'}',
        ),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Co ještě doplnit',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                for (final issue in issues)
                  ListTile(
                    dense: true,
                    leading: const Icon(
                      Icons.error_outline,
                      color: Color(0xffad721b),
                    ),
                    title: Text(issue.value),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _change((x) => x['step'] = issue.key),
                  ),
              ],
            ),
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
              _reviewRow(
                  AdministrationStrings.titleLabel, d['title'] as String),
              if (AppConfig.isAppSupported)
                _reviewRow(
                  AdministrationStrings.linkLabel,
                  (d['link'] as String).isEmpty
                      ? FormStrings.automaticPublicLink
                      : publicLinkUrl(d['link'] as String, isForm: false),
                ),
              _reviewRow(
                  CommonStrings.start, _dateForReview(d['start'] as String)),
              _reviewRow(CommonStrings.end, _dateForReview(d['end'] as String)),
              _reviewRow(
                OccasionSetupStrings.story('introImage'),
                OccasionSetupStrings.story(
                  (d['introImage'] as String? ?? '').isEmpty
                      ? 'notProvided'
                      : 'provided',
                ),
              ),
              _reviewRow(
                OccasionSetupStrings.story('promotion'),
                OccasionSetupStrings.story(
                  d['isPromoted'] == true ? 'enabled' : 'disabled',
                ),
              ),
              if ((d['placeName'] as String? ?? '').isNotEmpty)
                _reviewRow(CommonStrings.place, d['placeName'] as String),
              if ((d['description'] as String? ?? '').isNotEmpty)
                _reviewRow(
                  CommonStrings.description,
                  OccasionSetupStrings.story('provided'),
                ),
            ],
            issues),
        if (AppConfig.isAppSupported)
          _reviewSection(
              d,
              2,
              CommonStrings.content,
              [
                _reviewRow(
                  'FeatureForm.title'.tr(),
                  d['formEnabled'] == true ? 'Zapnuto' : 'Vypnuto',
                ),
                _reviewRow(
                  CommonStrings.schedule,
                  d['copyProgram'] == true ? 'Převzít' : 'Bez převzetí',
                ),
                _reviewRow(
                  'FeatureInformation.information'.tr(),
                  d['copyInformation'] == true ? 'Převzít' : 'Bez převzetí',
                ),
                _reviewRow(
                  'Šablony e-mailů',
                  d['copyEmails'] == true ? 'Převzít' : 'Bez převzetí',
                ),
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
                      : 'Kopie z události ${d['formOrigin']}',
                ),
                _reviewRow(
                  'FeatureFormSettings.labelFormTitle'.tr(),
                  form.form.definition.title ?? '',
                ),
                _reviewRow(
                  'FeatureFormSettings.labelFormLink'.tr(),
                  form.form.definition.link ?? '',
                ),
                _reviewRow('Stav', 'Zavřený'),
                Text(
                  'Pole formuláře (${form.form.relatedFields.where((field) => field.definition.isTicketField != true).length})',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                for (final field in form.form.relatedFields.where(
                  (field) => field.definition.isTicketField != true,
                ))
                  _reviewRow(
                    field.definition.title ??
                        FormHelper.fieldTypeToLocale(
                            field.definition.type ?? ''),
                    '${FormHelper.fieldTypeToLocale(field.definition.type ?? '')} · ${field.definition.isRequired == true ? 'povinné' : 'nepovinné'}${field.definition.isHidden == true ? ' · skryté' : ''}${field.options.isEmpty ? '' : ' · možnosti: ${field.options.map((option) => option.title).join(', ')}'}',
                  ),
                const SizedBox(height: 6),
                Text(
                  '${CommonStrings.products} (${form.products.length})',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                if (form.products.isEmpty) const Text('Žádné produkty'),
                for (final type in form.productTypes) ...[
                  Text(
                    type.title ?? '',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  for (final product in type.products ?? <ProductModel>[])
                    _reviewRow(
                      product.title ?? '',
                      '${product.price?.toStringAsFixed(0) ?? '0'} ${product.currencyCode ?? 'CZK'} · limit ${product.maximum?.toString() ?? 'bez limitu'}',
                    ),
                ],
                const SizedBox(height: 6),
                if (AppConfig.isAppSupported &&
                    OccasionSetupStory.hasPaidProducts(d)) ...[
                  _reviewRow(
                    'BankAccount.bankAccount'.tr(),
                    OccasionSetupStory.paymentAccountConfirmed(d)
                        ? (d['bankAccountLabel'] as String? ?? '')
                        : OccasionSetupStrings.story('bankAccountNotConfirmed'),
                  ),
                  _reviewRow(
                    'FeatureFormSettings.labelDeadlineDays'.tr(),
                    '${d['deadline']}',
                  ),
                ],
              ],
            ],
            issues),
        _reviewSection(
          d,
          5,
          OccasionTeamInvitationStrings.text('question'),
          [
            OccasionSetupInvitationsSummary(
              data: d,
              onSendChanged: (value) => _change(
                (x) => x['sendTeamInvitations'] = value,
                changesConfiguration: true,
              ),
            ),
          ],
          issues,
          questionKey: 'team',
        ),
        if (OccasionSetupStory.formEnabled(d))
          _reviewSection(
            d,
            3,
            OccasionSetupStrings.story('communicationQuestion'),
            [OccasionSetupCommunicationSummary(data: d)],
            issues,
            questionKey: 'communication',
          ),
        if (!AppConfig.isAppSupported && OccasionSetupStory.hasTickets(d))
          _reviewSection(
              d,
              2,
              'Vstupenka',
              [
                _reviewRow(
                  'Vzhled',
                  (d['ticketDraft'] as Map?)?['layout'] == null
                      ? 'Výchozí šablona'
                      : 'Uložený návrh',
                ),
              ],
              issues),
        if (!AppConfig.isAppSupported && OccasionSetupStory.hasPaidProducts(d))
          _reviewSection(
              d,
              4,
              'Nastavení plateb',
              [
                _reviewRow(
                  'BankAccount.bankAccount'.tr(),
                  OccasionSetupStory.paymentAccountConfirmed(d)
                      ? (d['bankAccountLabel'] as String? ?? '')
                      : OccasionSetupStrings.story('bankAccountNotConfirmed'),
                ),
                _reviewRow(
                  'FeatureFormSettings.labelDeadlineDays'.tr(),
                  '${d['deadline']}',
                ),
              ],
              issues),
        if (OccasionSetupStory.formEnabled(d))
          _reviewSection(
            d,
            AppConfig.isAppSupported ? 4 : 6,
            CommonStrings.blueprint,
            [
              _reviewRow('Způsob', d['blueprintMode'] as String),
              if (d['blueprintMode'] != 'Bez plánku') ...[
                _reviewRow(
                  'Rozměry',
                  '${d['blueprintWidth']} × ${d['blueprintHeight']}',
                ),
                _reviewRow(
                  'Skupiny',
                  groups
                      .map((group) => (group as Map)['title']?.toString() ?? '')
                      .join(', '),
                ),
                _reviewRow('Místa', '$seatCount'),
                _reviewRow(
                  'Vazba na formulář',
                  form?.form.definition.title ?? 'Chybí formulář',
                ),
              ],
            ],
            issues,
          ),
        if (_organizerProfile?.status == 'verified')
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.verified_outlined),
            title: Text(VerificationStrings.text('verified')),
            subtitle: Text(
              _organizerProfile!.details['legalName'] as String? ?? '',
            ),
          ),
        _reviewSection(
            d,
            5,
            'Soukromí a dokončení',
            [
              const Text(
                'Koncept je neveřejný. Vytvořená událost zůstane skrytá a formulář zavřený. Zveřejnění je samostatný krok.',
              ),
              const SizedBox(height: 8),
              Text(FormStrings.automaticPublicLink),
            ],
            issues),
        if (d['reviewed'] != true) ...[
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: d['reviewConfirmed'] == true,
            onChanged: issues.isEmpty
                ? (value) =>
                    _change((x) => x['reviewConfirmed'] = value == true)
                : null,
            title: Text(OccasionSetupStrings.story('reviewConfirmation')),
            subtitle: const Text('Potvrzení zpřístupní dokončení kontroly.'),
          ),
        ] else ...[
          const Text(
            '100 % znamená dokončené nastavení. Koncept je stále neveřejný.',
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: _leave,
            child: const Text('Uložit dokončený koncept'),
          ),
          if (_finalizeError != null) Text(_finalizeError!),
        ],
      ],
    );
  }

  Widget _body(Map<String, dynamic> d) {
    if (_questions[_questionIndex(d)].key == 'promotion') {
      return OccasionSetupPromotion(
        data: d,
        onChanged: (patch) =>
            _change((x) => x.addAll(patch), changesConfiguration: true),
      );
    }
    if (_questions[_questionIndex(d)].key == 'paymentTiming') {
      return OccasionSetupCommunication(
        key: const ValueKey('payment-timing'),
        paymentTiming: true,
        draftId: _stored.id,
        data: d,
        onChanged: (patch) =>
            _change((x) => x.addAll(patch), changesConfiguration: true),
      );
    }
    if (_questions[_questionIndex(d)].key == 'team') {
      return OccasionSetupInvitations(
        draftId: _stored.id,
        data: d,
        onChanged: (patch) =>
            _change((x) => x.addAll(patch), changesConfiguration: true),
      );
    }
    if (_questions[_questionIndex(d)].key == 'communication') {
      return OccasionSetupCommunication(
        key: const ValueKey('communication'),
        draftId: _stored.id,
        data: d,
        onChanged: (patch) =>
            _change((x) => x.addAll(patch), changesConfiguration: true),
      );
    }
    if (_questions[_questionIndex(d)].key == 'payments')
      return _paymentSettings(d);
    if (_questions[_questionIndex(d)].key == 'pricing') {
      return OccasionSetupPricing(
        data: d,
        onChanged: (patch) =>
            _change((x) => x.addAll(patch), changesConfiguration: true),
      );
    }
    if (_questions[_questionIndex(d)].key == 'scanner') {
      final feature = _ticketDraftFeature(d);
      return EditorDraftScope(
        onChanged: () => _change(
          (x) => x['ticketDraft'] = feature.toJson(),
          changesConfiguration: true,
        ),
        child: TicketScanningSettings(feature: feature),
      );
    }
    if (_questions[_questionIndex(d)].key == 'verification') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(OccasionSetupStrings.story('verificationHint')),
          const SizedBox(height: 20),
          UnitLegalProfileSection(
            unitId: _stored.unit,
            canEdit: RightsService.isUnitManager(),
          ),
        ],
      );
    }

    switch (d['step'] as int) {
      case 0:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_loadingSources) const LinearProgressIndicator(),
            if (_sourceError != null)
              TextButton(
                onPressed: _loadSources,
                child: Text('$_sourceError Zkusit znovu'),
              ),
            _choice(d, 'source', 'Zdroj', [
              'Od nuly',
              ..._sources.map(_sourceLabel),
              if (d['source'] != 'Od nuly' &&
                  !_sources.any((s) => _sourceLabel(s) == d['source']))
                d['source'] as String,
            ]),
            if (_sources.isEmpty && !_loadingSources && _sourceError == null)
              const Text(
                'V této jednotce zatím nejsou žádné uložené předlohy.',
              ),
            const Text(
              'Kopie přenese jen vybrané nastavení. Objednávky, účastníci a rezervace zůstanou ve zdroji.',
            ),
          ],
        );
      case 1:
        return _basics(d);
      case 2:
        if (!AppConfig.isAppSupported) return _ticketSettings(d);
        return Column(
          children: [
            _switch(d, 'formEnabled', 'Registrace a prodej'),
            _switch(
              d,
              'copyProgram',
              '${CommonStrings.schedule} a ${CommonStrings.places}',
            ),
            _switch(
              d,
              'copyInformation',
              'FeatureInformation.information'.tr(),
            ),
            if (d['copyProgram'] == true)
              ExpansionTile(
                title: Text(
                  '${CommonStrings.schedule} · ${(d['sourceProgram'] as List? ?? []).length}',
                ),
                children: [
                  for (final item in d['sourceProgram'] as List? ?? [])
                    ListTile(
                      title: Text((item as Map)['title']?.toString() ?? ''),
                      subtitle: Text(
                        _dateForReview(item['start_time']?.toString()),
                      ),
                    ),
                ],
              ),
            if (d['copyInformation'] == true)
              ExpansionTile(
                title: Text(
                  '${'FeatureInformation.information'.tr()} · ${(d['sourceInformation'] as List? ?? []).length}',
                ),
                children: [
                  for (final item in d['sourceInformation'] as List? ?? [])
                    ListTile(
                      title: Text((item as Map)['title']?.toString() ?? ''),
                    ),
                ],
              ),
            ExpansionTile(
              title: Text('FormsFeature.additionalSettings'.tr()),
              subtitle: const Text('Šablony e-mailů a menší volby'),
              children: [_switch(d, 'copyEmails', 'Převzít e-mailové šablony')],
            ),
          ],
        );
      case 3:
        if (d['formEnabled'] == false) {
          return const Text('Formulář je vypnutý.');
        }
        final formData = d['formDraft'];
        final formBundle = formData is Map
            ? (_inlineFormBundle ??= draftFormBundle(
                Map<String, dynamic>.from(formData),
              ))
            : null;
        final fields = formBundle?.form.relatedFields
                .where((field) => field.definition.isTicketField != true)
                .length ??
            0;
        final products = formBundle?.products.length ?? 0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
                d,
                'title',
                'FeatureFormSettings.labelFormTitle'.tr(),
              ),
              const SizedBox(height: 10),
              OccasionSetupFormLink(
                key: ValueKey('${d['id']}-form-link-$_formEpoch'),
                draftId: _stored.id,
                title: d['title'] as String,
                value: formBundle.form.definition.link ?? '',
                automatic: d['formLinkAutomatic'] != false,
                onValidityChanged: (value) {
                  if (mounted && _formLinkAvailable != value)
                    setState(() => _formLinkAvailable = value);
                },
                onChanged: (value, automatic) => _change((x) {
                  x['formLinkAutomatic'] = automatic;
                  (x['formDraft'] as Map)['link'] = value;
                  _inlineFormBundle?.form.definition =
                      _inlineFormBundle!.form.definition.copyWith(link: value);
                }, changesConfiguration: true),
              ),
              const SizedBox(height: 10),
              Text('$fields polí · $products produktů'),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                children: [
                  OutlinedButton.icon(
                    onPressed: _chooseForm,
                    icon: const Icon(Icons.swap_horiz),
                    label: Text('FormsFeature.createNewForm'.tr()),
                  ),
                ],
              ),
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
          ],
        );
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

  TicketFeature _ticketDraftFeature(Map<String, dynamic> d) =>
      _ticketFeature ??= TicketFeature.fromJson(
        Map<String, dynamic>.from(
          d['ticketDraft'] as Map? ??
              {'code': FeatureConstants.ticket, 'is_enabled': true},
        ),
      );

  Widget _ticketSettings(Map<String, dynamic> d) {
    final feature = _ticketDraftFeature(d);
    // Preview resources come from an authorized event; saved edits belong only
    // to this draft. The source event's feature configuration is never updated.
    final previewId = d['sourceId'] as int? ??
        (_sources.isEmpty
            ? null
            : (_sources.first['occasion'] as Map)['id'] as int);
    return EditorDraftScope(
      onChanged: () => _change(
        (x) => x['ticketDraft'] = feature.toJson(),
        changesConfiguration: true,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (previewId == null)
            const Text('Pro náhled vstupenky zatím není dostupná předloha.')
          else
            Center(
              child: TicketSettings(
                key: ValueKey('${d['id']}-ticket-$previewId-$_editEpoch'),
                feature: feature,
                occasionId: previewId,
                productEditing: false,
                showScanningSettings: false,
                borrowResourcesOnly: d['sourceId'] == null,
                previewOccasion: TicketPreviewOccasion(
                  title: d['title'] as String,
                  startTime: DateTime.tryParse(d['start'] as String),
                  endTime: DateTime.tryParse(d['end'] as String),
                  placeName: d['placeName'] as String?,
                ),
              ),
            ),
          const SizedBox(height: 24),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(OccasionSetupStrings.story('configureScanning')),
            subtitle: Text(OccasionSetupStrings.story('configureScanningHint')),
            value: d['configureScanning'] == true,
            onChanged: (value) =>
                _change((x) => x['configureScanning'] = value),
          ),
        ],
      ),
    );
  }

  Widget _paymentSettings(Map<String, dynamic> d) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OccasionSetupBankAccount(
            draftId: _stored.id,
            unitId: _stored.unit,
            data: d,
            onChanged: (patch) =>
                _change((x) => x.addAll(patch), changesConfiguration: true),
          ),
          const SizedBox(height: 24),
          FormVariableSymbolSettings(
            value: Map<String, dynamic>.from(
              ((d['formDraft'] as Map?)?['data']
                      as Map?)?[FormDefinition.metaVariableSymbol] as Map? ??
                  {},
            ),
            onChanged: (value) => _change((x) {
              final form = x['formDraft'] as Map;
              final meta =
                  Map<String, dynamic>.from(form['data'] as Map? ?? {});
              meta[FormDefinition.metaVariableSymbol] = value;
              form['data'] = meta;
              _inlineFormBundle?.form.definition =
                  _inlineFormBundle!.form.definition.copyWith(data: meta);
            }, changesConfiguration: true),
          ),
        ],
      );

  Widget _blueprintSettings(Map<String, dynamic> d) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _choice(d, 'blueprintMode', CommonStrings.blueprint, [
          'Bez plánku',
          'Nový',
          'Převzít',
        ]),
        if (d['blueprintMode'] != 'Bez plánku') ...[
          Text('${(d['blueprintObjects'] as List).length} míst v plánu'),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _openBlueprint,
            icon: const Icon(Icons.grid_on),
            label: const Text('Otevřít editor plánku'),
          ),
          const SizedBox(height: 12),
          const Text('Úpravy plánku se ukládají do tohoto konceptu.'),
        ],
      ],
    );
  }

  Widget _wizard(Map<String, dynamic> d) {
    final step = d['step'] as int;
    final index = _questionIndex(d);
    final question = _questions[index];
    final isReview = question.key == 'review';
    final reviewReady = isReview && _reviewIssues(d).isEmpty;
    final isEditor = question.key == 'form' || question.key == 'ticket';
    return OccasionSetupStoryShell(
      questionTitles: [
        for (final item in _questions)
          item.key == 'team'
              ? OccasionTeamInvitationStrings.text('question')
              : OccasionSetupStrings.story('${item.key}Question'),
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
      questionCount: OccasionSetupStrings.questionNumber(
        index + 1,
        _questions.length,
      ),
      segmentStates: [
        OccasionSetupStrings.story('completedQuestion'),
        OccasionSetupStrings.story('currentQuestion'),
        OccasionSetupStrings.story('upcomingQuestion'),
      ],
      leaveLabel: OccasionSetupStrings.story('leave'),
      backLabel: CommonStrings.back,
      onLeave: _pending != null || _presentationUploading ? null : _leave,
      onBack: index == 0 || _presentationUploading
          ? null
          : () {
              _change((x) => _goToQuestion(x, _questionIndex(x) - 1));
              if (question.key == 'verification') _refreshVerification();
            },
      onQuestionSelected: _presentationUploading
          ? null
          : (target) {
              _change((x) => _goToQuestion(x, target));
              if (question.key == 'verification') _refreshVerification();
            },
      maxContentWidth: step == 3 || question.key == 'ticket'
          ? StylesConfig.formMaxWidth
          : isReview || question.optional
              ? 960
              : 680,
      centerQuestion: !isEditor && !isReview && !question.optional,
      error: _error == null
          ? null
          : Row(
              children: [
                Expanded(
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
                TextButton(
                  onPressed:
                      _pending != null ? null : (_conflict ? _reload : _flush),
                  child: Text(
                    _conflict
                        ? OccasionSetupStrings.reload
                        : OccasionSetupStrings.retry,
                  ),
                ),
              ],
            ),
      primaryAction: FilledButton(
        style: FilledButton.styleFrom(minimumSize: const Size(160, 48)),
        onPressed: _presentationUploading
            ? null
            : isReview
                ? d['reviewed'] == true
                    ? (_finalizing || !reviewReady ? null : _finalize)
                    : (reviewReady && d['reviewConfirmed'] == true
                        ? _review
                        : null)
                : _advance,
        child: Text(
          isReview
              ? d['reviewed'] == true
                  ? OccasionSetupStrings.createEvent
                  : OccasionSetupStrings.story('confirmReview')
              : question.key == 'verification'
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
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_finalizing) const CircularProgressIndicator(),
                        Text(_finalizeError ?? OccasionSetupStrings.saving),
                        if (!_finalizing) ...[
                          ElevatedButton(
                            onPressed: _finalize,
                            child: Text(OccasionSetupStrings.retry),
                          ),
                          TextButton(
                            onPressed: _leave,
                            child: Text(CommonStrings.back),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
        ),
      );
}
