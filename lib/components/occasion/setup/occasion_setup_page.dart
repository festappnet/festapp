import '../../ticket_layout/ticket_delivery_strings.dart';
import 'package:fstapp/components/stripe_payments/payment_method_cards.dart';
import 'package:fstapp/components/stripe_payments/stripe_feature.dart';
import 'package:fstapp/components/forms/payment_method_strings.dart';
import 'package:fstapp/components/eshop/orders_strings.dart';
import 'occasion_setup_appearance.dart';
import '../../fonts/form_font_catalog.dart';
import 'occasion_setup_appearance_panel.dart';
import 'occasion_setup_form_preview.dart';
import 'occasion_setup_ticket_gallery.dart';

import 'package:fstapp/router_service.dart';

import '../occasion_creation_notice.dart';
import 'occasion_setup_result.dart';

import 'package:fstapp/services/time_helper.dart';

import 'occasion_setup_sales.dart';
import 'occasion_setup_completed.dart';
import 'occasion_setup_source_picker.dart';
import 'occasion_setup_copy_picker.dart';
import 'occasion_setup_references.dart';
import 'occasion_setup_reference_dialog.dart';

import 'package:fstapp/data_services/authorization_capabilities.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';

import 'blueprint_setup_layout_draft.dart';
import '../../blueprint/blueprint_layout_resources.dart';
import '../../blueprint/blueprint_text_preparation.dart';
import '../../blueprint/blueprint_strings.dart';
import '../../blueprint/views/blueprint_layout_demo.dart';
import '../../blueprint/views/blueprint_product_dialogs.dart';

import 'package:festapp_core/forms.dart';

import 'dart:async';
import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/styles/styles_config.dart';
import 'package:fstapp/components/_shared/admin_strings.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:festapp_core/eshop.dart';
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
import 'package:fstapp/services/dialog_helper.dart';

import 'occasion_setup_draft.dart';

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
import 'package:fstapp/components/ticket_layout/ticket_layout_service.dart';

import 'package:fstapp/components/unit/verification/db_unit_verification.dart';
import 'package:fstapp/components/unit/verification/unit_legal_profile.dart';
import 'package:fstapp/components/unit/verification/verification_strings.dart';
import 'package:fstapp/components/unit/verification/unit_legal_profile_section.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/services/exception_handler.dart';

class OccasionSetupPage extends StatefulWidget {
  final OccasionSetupDraft draft;
  const OccasionSetupPage({super.key, required this.draft});
  static Future<OccasionSetupResult?> open(
    BuildContext context,
    OccasionSetupDraft draft,
  ) async {
    final initialized = await ExceptionHandler.guard(
      context,
      futureFunction: () => OccasionSetupDrafts(Supabase.instance.client)
          .initializeDefaults(draft),
    );
    if (initialized == null || !context.mounted) return null;
    final result = await Navigator.of(context).push<OccasionSetupResult>(
      MaterialPageRoute(builder: (_) => OccasionSetupPage(draft: initialized)),
    );
    if (result != null && context.mounted) {
      final next = await Navigator.of(context).push<OccasionSetupNext>(
        MaterialPageRoute(
          builder: (_) => OccasionSetupCompleted(result: result),
        ),
      );
      if (next == OccasionSetupNext.manage && context.mounted) {
        await RouterService.navigateToOccasionAdministration(
          context,
          occasionLink: result.link,
        );
      }
    }
    if (result != null)
      OccasionCreationNotice.record(result.unit, result.occasionId);
    return result;
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
  int _configurationEpoch = 0;
  Map<String, dynamic>? _formUndo;
  TicketFeature? _ticketFeature;
  FormEditBundle? _inlineFormBundle;
  List<Map<String, dynamic>> _sources = [];
  Map<String, dynamic>? _selectedSource;
  int _sourceRequest = 0;
  bool _loadingDetail = false;
  final Map<String, Future<Map<String, dynamic>>> _sourceRequests = {};
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
  String? _blueprintError;
  bool _blueprintOpenFailed = false;
  bool _loadingBlueprintCandidate = false;
  int _blueprintSelectionRequest = 0;
  bool _openingBlueprint = false;
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
      'copyProgram': false,
      'copyInformation': false,
      'copyEmails': false,
      'formEnabled': true,
      'formOrigin': null,
      'formDraft': null,
      'deadline': '',
      'blueprintMode': SetupBlueprintConfiguration(_stored.data).modeId,
      'reviewed': false,
      'reviewConfirmed': false,
      'completed': <int>[],
      ..._stored.data,
      'step': _stored.data['step'] ?? 1,
    };
    _data.putIfAbsent(
      'formLinkAutomatic',
      () => ((_data['formDraft'] as Map?)?['link'] as String? ?? '').isEmpty,
    );
    _ensureDefaultForm(_data);
    initializeCommunicationDraft(_data);
    _restrictToSupportedFeatures(_data);
    _data.remove('bankAccountConfirmed');
    _data.remove('configureScanning');
    OccasionSetupStory.normalize(_data, AppConfig.isAppSupported);
    if (_data['appearance'] == null &&
        _data['sourceId'] == null &&
        _data['formOrigin'] == null)
      OccasionSetupAppearance.apply(_data, OccasionSetupAppearance.read(_data));
    _linkController = TextEditingController(text: _data['link'] as String);
    _loadSources();
    _refreshVerification();
    _save();
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
    setState(() {
      _loadingSources = true;
      _sourceError = null;
    });
    _sourceRequests.clear();
    try {
      final rows = await Supabase.instance.client.rpc(
        'get_occasion_setup_source_list',
        params: {'p_unit': _stored.unit, 'p_source_unit': null},
      );
      if (!mounted) return;
      setState(
        () => _sources =
            (rows as List).map((r) => Map<String, dynamic>.from(r)).toList(),
      );
      final id = _data['sourceId'] as int?;
      if (id != null) {
        if (_data['sourceSelectionPending'] == true) {
          await _selectSource(id);
        } else {
          // Read-only refresh: a presentation label is not a draft edit.
          final source = await _sourceDetail(id);
          if (mounted && _data['sourceId'] == id)
            setState(() => _selectedSource = source);
        }
      }
    } catch (_) {
      if (mounted)
        setState(() => _sourceError =
            OccasionSetupStrings.ui('templates_could_not_be_loaded'));
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
          params: {'p_unit': _stored.unit, 'p_occasion': id},
        );
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
      _selectedSource = null;
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
      final prepared = Map<String, dynamic>.from(
        jsonDecode(jsonEncode(source)) as Map,
      );
      final form = (prepared['forms'] as List).firstOrNull as Map?;
      final plans = prepared['blueprints'] as List;
      final index = plans.indexWhere(
        (p) => (p as Map)['id'] == form?['blueprint'],
      );
      if (index >= 0)
        plans[index] = await _prepareBlueprint(plans[index] as Map);
      if (!mounted || request != _sourceRequest) return;
      _applySource(staged, id, source: prepared);
      SetupBlueprintConfiguration(staged).normalize();
      final resolved = await _resolveReferences(staged, _data);
      if (!mounted || request != _sourceRequest || resolved == null) return;
      _selectedSource = prepared;
      _change((d) {
        d.clear();
        d.addAll(resolved);
        d.remove('sourceSelectionPending');
      }, changesConfiguration: true);
    } catch (e) {
      if (mounted && request == _sourceRequest)
        setState(
          () => _sourceError = e is FormatException
              ? e.message
              : OccasionSetupStrings.ui(
                  'the_template_could_not_be_loaded_your_previous_settings'),
        );
    } finally {
      if (mounted && request == _sourceRequest)
        setState(() => _loadingDetail = false);
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

  Map<String, dynamic> _clone(Map value) =>
      Map<String, dynamic>.from(jsonDecode(jsonEncode(value)));

  Future<Map<String, dynamic>?> _pickConfiguration(String kind) async {
    final epoch = _configurationEpoch;
    final chosen = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => OccasionSetupCopyPicker(
        kind: kind,
        load: () async {
          final rows = await Supabase.instance.client.rpc(
            'get_occasion_setup_source_list',
            params: {'p_unit': _stored.unit, 'p_source_unit': null},
          );
          return [
            for (final source in (rows as List).whereType<Map>())
              for (final item in (source[kind] as List? ?? []).whereType<Map>())
                {
                  ...Map<String, dynamic>.from(item),
                  'occasionId': (source['occasion'] as Map)['id'],
                  'occasionTitle': (source['occasion'] as Map)['title'],
                },
          ];
        },
      ),
    );
    if (!mounted || chosen == null || epoch != _configurationEpoch) return null;
    try {
      final source = await _sourceDetail(chosen['occasionId'] as int);
      if (!mounted || epoch != _configurationEpoch) return null;
      return {
        'source': source,
        'item': (source[kind] as List).whereType<Map>().firstWhere(
              (i) => i['id'] == chosen['id'],
            ),
      };
    } catch (error, stack) {
      debugPrint('Setup copy: $error\n$stack');
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(OccasionSetupStrings.story('copiesFailed'))),
        );
      return null;
    }
  }

  Future<Map<String, dynamic>> _loadEmailPreview(
    Map<String, dynamic> snapshot,
  ) async {
    if (!await _flush()) throw StateError('Draft save failed');
    if (snapshot['previewMessageType'] == 'order_tickets') {
      final data = await Supabase.instance.client
          .rpc('get_occasion_setup_email_preview', params: {
        'p_id': _stored.id,
        'p_expected_revision': _stored.revision,
        'p_message_type': 'order_tickets',
        'p_occasion': null,
        'p_delivery_mode': null,
      });
      return Map<String, dynamic>.from(data as Map);
    }
    final response = await Supabase.instance.client.functions.invoke(
      'occasion-setup-email-preview',
      body: {
        'draftId': _stored.id,
        'revision': _stored.revision,
        if (snapshot['previewMessageType'] != null)
          'messageType': snapshot['previewMessageType'],
        if (snapshot['previewTicketCount'] != null)
          'sampleTicketCount': snapshot['previewTicketCount'],
        if (snapshot['previewMessageType'] == 'order_tickets')
          'deliveryMode': (snapshot['ticketDraft'] as Map?)?['delivery_mode'] ??
              'pdf_attachment',
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  void _ensureDefaultForm(Map<String, dynamic> draft) {
    final existing = draft['formDraft'];
    if (existing is Map &&
        (draft['formDefaultsInitialized'] == true ||
            (existing['fields'] as List? ?? []).isNotEmpty)) {
      draft['formDefaultsInitialized'] = true;
      if (draft['formDefaultsFollowEvent'] == true &&
          draft['starterNamesLocalized'] != true) {
        draft['formDraft'] = serializeDraftForm(
          localizeStarterProducts(
            draftFormBundle(Map<String, dynamic>.from(existing)).form,
          ),
        );
        draft['starterNamesLocalized'] = true;
      }
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
    draft.remove('bankAccountConfirmed');
    draft.remove('bankAccountFingerprint');
  }

  void _applySource(
    Map<String, dynamic> draft,
    int? sourceId, {
    Map<String, dynamic>? source,
  }) {
    _formLinkAvailable = null;
    _resetBankAccount(draft);
    _ticketFeature = null;
    _inlineFormBundle = null;
    _formEpoch++;
    draft.remove('ticketDraft');
    draft['formDefaultsFollowEvent'] = sourceId == null;
    draft['source'] = OccasionSetupStrings.copy('fromScratch');
    draft['copyProgram'] = false;
    draft['copyInformation'] = false;
    draft['copyEmails'] = false;
    draft['sourceId'] = null;
    draft.remove('sourceSelectionPending');
    draft.remove('sourceFormId');
    draft['formDraft'] = null;
    draft['formOrigin'] = null;
    draft.remove('blueprintLayoutDraft');
    draft['blueprintMode'] = 'Bez plánku';
    draft['sourceProgram'] = <dynamic>[];
    draft['sourceInformation'] = <dynamic>[];
    draft['completed'] = <int>[];
    if (sourceId == null) {
      _ensureDefaultForm(draft);
      OccasionSetupAppearance.apply(
        draft,
        Map<String, dynamic>.from(OccasionSetupAppearance.presets.first),
      );
      return;
    }
    source ??= _selectedSource;
    if (source == null)
      throw FormatException(
          OccasionSetupStrings.ui('the_template_is_not_loaded'));
    draft['source'] = _sourceLabel(source);
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
      final sourcePayments =
          ((draft['formDraft'] as Map)['data'] as Map?)?['payments'];
      if (draft['paymentChoicesEnabled'] == true && sourcePayments is Map) {
        final hasCard = sourcePayments['stripeConnectionId'] is String ||
            sourcePayments['bankEnabled'] == false;
        draft['paymentMethod'] = hasCard
            ? (sourcePayments['bankEnabled'] == false ? 'stripe' : 'both')
            : 'bank';
      }
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
    draft.remove('appearance');
    draft['appearance'] = {
      ...OccasionSetupAppearance.read(draft),
      'id': 'custom',
      'preserveSource': true
    };
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

  Future<Map<String, dynamic>> _prepareBlueprint(Map plan) async {
    final raw = plan['blueprintLayoutDraft'];
    if (raw is! Map || (raw['layout'] as Map?)?['schemaVersion'] != 1) {
      return SetupBlueprintConfiguration.adaptSource(
        plan,
        fontFamilies: const {},
      );
    }
    final provider = await BlueprintTextResources.forSetupDraft(_stored.id);
    final families = {
      for (final family in provider.families)
        family['id'] as String: Map<String, dynamic>.from(family),
    };
    final adapted = SetupBlueprintConfiguration.adaptSource(
      plan,
      fontFamilies: families,
    );
    final draft = BlueprintSetupLayoutDraft.fromJson(
      Map<String, dynamic>.from(adapted['blueprintLayoutDraft'] as Map),
    );
    await BlueprintTextPreparation(provider.prepareTextBatch)
        .prepareSnapshot(draft.document, families, const {});
    return adapted;
  }

  void _applyBlueprint(Map<String, dynamic> draft, Map plan) {
    SetupBlueprintConfiguration(draft).importPlan(plan);
  }

  void _save() {
    if (_stored.isFinalized) return;
    _dirty = true;
    _debounce?.cancel();
    if (!_conflict && _error == null) {
      _debounce = Timer(const Duration(milliseconds: 600), _flush);
    }
  }

  void _change(
    void Function(Map<String, dynamic>) update, {
    bool changesConfiguration = false,
    bool invalidateUndo = true,
  }) {
    if (_finalizeCommand != null) return;
    setState(() {
      final oldTitle = _data['title'];
      final oldFormLink = (_data['formDraft'] as Map?)?['link'];
      final oldCurrencies = OccasionSetupStory.paymentCurrencies(_data);
      update(_data);
      if (changesConfiguration && invalidateUndo) {
        _configurationEpoch++;
        _formUndo = null;
      }
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
      OccasionSetupStory.normalize(_data, AppConfig.isAppSupported);
      if (_data['formDraft'] is Map) {
        (_data['formDraft'] as Map)['title'] = _data['title'];
        _inlineFormBundle?.form.definition =
            _inlineFormBundle!.form.definition.copyWith(title: _data['title']);
      }
      _restrictToSupportedFeatures(_data);
      if (changesConfiguration) {
        _persistFormControls(_data);
        SetupBlueprintConfiguration(_data).normalize();
      }
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
      SetupBlueprintConfiguration(_data).normalize();
      _restrictToSupportedFeatures(_data);
      OccasionSetupStory.normalize(_data, AppConfig.isAppSupported);
      _data['completedQuestions'] = [
        for (final q in _questions)
          if (!q.optional && _questionReady(_data, q)) q.key,
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
    if (_finalizing ||
        _finalizeCommand == null &&
            (_data['reviewConfirmed'] != true ||
                _reviewIssues(_data).isNotEmpty)) return;
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
    } catch (error) {
      if (!eventCreated &&
          error is PostgrestException &&
          error.code != null &&
          !error.code!.startsWith('08') &&
          error.code != '57014' &&
          !error.code!.startsWith('PGRST0')) {
        _finalizeCommand = null;
        _finalizeDraft = null;
      }
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
    final confirmed = await DialogHelper.showConfirmationDialog(
      context,
      OccasionSetupStrings.reload,
      OccasionSetupStrings.reloadConfirm,
    );
    if (confirmed != true || !mounted) return;
    try {
      final current = await _store.get(_stored.id);
      if (!mounted) return;
      setState(() {
        _stored = current;
        _data = Map.of(current.data);
        OccasionSetupStory.normalize(_data, AppConfig.isAppSupported);
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
        return !_loadingDetail && _data['sourceSelectionPending'] != true;
      case 1:
        final start = DateTime.tryParse(d['start'] as String);
        final end = DateTime.tryParse(d['end'] as String);
        return (d['title'] as String).trim().isNotEmpty &&
            (!AppConfig.isAppSupported ||
                d['isPromoted'] != true ||
                (d['introImage'] as String? ?? '').trim().isNotEmpty) &&
            isValidPublicSlug(d['link'] as String, allowEmpty: true) &&
            start != null &&
            end != null &&
            !end.isBefore(start);
      case 2:
        return true;
      case 3:
        if (d['formEnabled'] == false) return true;
        if (!OccasionSetupStory.productPricesValid(d)) return false;
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
      !SetupBlueprintConfiguration(d).active ||
      SetupBlueprintConfiguration(d).ready;

  bool _paymentsReady(Map<String, dynamic> d) =>
      _deadlineReady(d) &&
      (!OccasionSetupStory.hasPaidProducts(d) ||
          OccasionSetupStory.paymentSetupReady(d));

  bool _deadlineReady(Map<String, dynamic> d) =>
      (d['deadline'] as String? ?? '').trim().isEmpty ||
      (int.tryParse(d['deadline'] as String? ?? '') ?? -1) >= 0;

  List<OccasionSetupQuestion> get _questions => OccasionSetupStory.questions(
        AppConfig.isAppSupported,
        data: _data,
        organizationVerified: _organizerProfile?.status == 'verified',
        includeSource: _data['storyQuestion'] == 'source',
      );

  int _questionIndex(Map<String, dynamic> d) => OccasionSetupStory.index(
        d,
        AppConfig.isAppSupported,
        organizationVerified: _organizerProfile?.status == 'verified',
        includeSource: _data['storyQuestion'] == 'source',
      );

  void _goToQuestion(Map<String, dynamic> d, int index) {
    final question = _questions[index];
    d['step'] = question.step;
    d['storyQuestion'] = question.key;
    d['visitedQuestions'] = {
      ...(d['visitedQuestions'] as List? ?? []).cast<String>(),
      question.key,
    }.toList();
  }

  bool _questionReady(Map<String, dynamic> d, OccasionSetupQuestion q) {
    if (q.key == 'ticket')
      return !OccasionSetupStory.hasTickets(d) ||
          (d['ticketDraft'] as Map?)?['delivery_mode'] == 'inline_qr' ||
          (d['ticketDraft'] as Map?)?['layout'] is Map;
    if (q.key == 'appearance')
      return d['appearance'] is Map &&
          OccasionSetupAppearance.valid(d['appearance'] as Map);
    if (q.key == 'review')
      return d['reviewed'] == true && d['reviewConfirmed'] == true;
    if (q.optional) return true;
    if (q.key == 'saleTiming')
      return OccasionSetupSales.valid(d, DateTime.now());
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
    if (q.key == 'payments') return OccasionSetupStory.paymentSetupReady(d);
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
        return !AppConfig.isAppSupported ||
            d['isPromoted'] != true ||
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
    _jump(_questions[index + 1].key);
  }

  Future<void> _openBlueprint({VenueLayoutDocument? initialTemplate}) async {
    if (initialTemplate == null &&
        _data['blueprintLayoutDraft'] is! Map &&
        SetupBlueprintConfiguration(_data).mode != SetupBlueprintMode.copy) {
      await _startNewBlueprint();
      return;
    }
    if (_openingBlueprint) return;
    setState(() {
      _openingBlueprint = true;
      _blueprintOpenFailed = false;
      _blueprintError = null;
    });
    final assets = BlueprintLayoutAssetResolver();
    try {
      final oldLayout = _active!['blueprintLayoutDraft'];
      if (oldLayout is Map &&
          (oldLayout['layout'] as Map?)?['schemaVersion'] == 1) {
        final prepared = await _prepareBlueprint({
          'blueprintLayoutDraft': oldLayout,
        });
        if (!mounted) return;
        _change(
          (value) =>
              value['blueprintLayoutDraft'] = prepared['blueprintLayoutDraft'],
          changesConfiguration: true,
        );
      }
      if (!await _flush() || !mounted) return;
      final data = _active!;
      final formData = data['formDraft'];
      final products = formData is Map
          ? draftFormBundle(Map<String, dynamic>.from(formData))
              .products
              .where((p) => p.productTypeString == ProductModel.spotType)
              .toList()
          : <ProductModel>[];
      if (products.isEmpty)
        throw StateError(BlueprintStrings.toastNoTemplateProduct);
      ProductModel? defaultProduct;
      if (products.length == 1) {
        defaultProduct = products.single;
      } else {
        defaultProduct = await showDialog<ProductModel>(
          context: context,
          builder: (_) => SelectProductDialog.catalog(
            products: products,
            onProductSaved: (_) {},
            canEditCatalog: false,
          ),
        );
        if (defaultProduct == null || !mounted) return;
      }
      final raw = data['blueprintLayoutDraft'];
      if (raw == null &&
          SetupBlueprintConfiguration(data).mode == SetupBlueprintMode.copy) {
        throw StateError(BlueprintStrings.layoutUnavailable);
      }
      var draft = raw is Map
          ? BlueprintSetupLayoutDraft.fromJson(Map<String, dynamic>.from(raw))
          : BlueprintSetupLayoutDraft.empty(
              document: initialTemplate ??
                  VenueLayoutTemplates.byId(
                    'blank',
                  ).create(localize: VenueLayoutLocalizations.of(context).text),
              resources: const {},
            );
      final provider = await BlueprintTextResources.forSetupDraft(_stored.id);
      Future<Map<String, dynamic>> prepare(
        VenueLayoutDocument document,
        Map<String, dynamic> resources,
      ) async {
        final prepared =
            await BlueprintTextPreparation(provider.prepareTextBatch)
                .prepareSnapshot(
                    document,
                    {
                      for (final family in provider.families)
                        family['id'] as String: family,
                    },
                    resources);
        return assets.resolve(prepared);
      }

      final resources = await prepare(
        draft.document,
        await _store.blueprintResources(_stored),
      );
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: AppBar(
              title: Text(OccasionSetupStrings.story('draftBlueprintTitle')),
            ),
            body: BlueprintLayoutDemo(
              onSaved: () => Navigator.of(context).pop(),
              initialDocument: draft.document,
              initiallyUnsaved: raw is! Map,
              initialResources: resources,
              loadTextResources: () async => provider,
              prepareResources: prepare,
              unitId: _stored.unit,
              onSave: (document) async {
                var next = draft.reconcile(
                  document,
                  defaultProductId: defaultProduct!.id,
                );
                final unassigned = next.seatBindings.values
                    .where(
                      (seat) =>
                          seat.productId == null &&
                          !draft.seatBindings.containsKey(seat.nodeId),
                    )
                    .toList();
                for (final group in unassigned
                    .map((seat) => seat.groupNodeId)
                    .whereType<String>()
                    .toSet()) {
                  final product = await showDialog<ProductModel>(
                    context: context,
                    builder: (_) => SelectProductDialog.catalog(
                      products: products,
                      onProductSaved: (_) {},
                      canEditCatalog: false,
                    ),
                  );
                  if (product == null) throw StateError(CommonStrings.storno);
                  next = next.withGroupProduct(
                    group,
                    product.id!,
                    assignNodeIds: unassigned
                        .where((seat) => seat.groupNodeId == group)
                        .map((seat) => seat.nodeId)
                        .toSet(),
                  );
                }
                for (final area in document.nodes.where(
                  (n) => n.kind == 'capacityArea',
                )) {
                  if (next.areaBindings.any((b) => b['nodeId'] == area.id))
                    continue;
                  final product = await showDialog<ProductModel>(
                    context: context,
                    builder: (_) => SelectProductDialog.catalog(
                      products: products,
                      onProductSaved: (_) {},
                      canEditCatalog: false,
                    ),
                  );
                  if (product == null) throw StateError(CommonStrings.storno);
                  final capacity = area.properties['capacity'];
                  if (capacity is! num ||
                      capacity < 0 ||
                      capacity != capacity.round()) {
                    throw StateError(CommonStrings.invalidFormat);
                  }
                  next = next.withArea(
                    nodeId: area.id,
                    productId: product.id!,
                    capacity: capacity.toInt(),
                  );
                }
                _change(
                  (value) => value['blueprintLayoutDraft'] = next.toJson(),
                  changesConfiguration: true,
                );
                if (!await _flush())
                  throw StateError(_error ?? CommonStrings.unexpectedError);
                draft = next;
              },
            ),
          ),
        ),
      );
    } catch (error) {
      if (mounted)
        setState(() {
          _blueprintOpenFailed = true;
          _blueprintError = error.toString();
        });
    } finally {
      assets.dispose();
      if (mounted) setState(() => _openingBlueprint = false);
    }
  }

  int _layoutSeatCount(Map<String, dynamic> data) =>
      SetupBlueprintConfiguration(data).seatCount;
  int _layoutAreaCount(Map<String, dynamic> data) =>
      SetupBlueprintConfiguration(data).areaCount;

  Future<void> _startNewBlueprint() async {
    final selected = await showVenueLayoutTemplateGallery(context);
    if (!mounted || selected == null) return;
    _change((d) {
      SetupBlueprintConfiguration(d).clear(create: true);
      _inlineFormBundle = null;
      _formEpoch++;
    }, changesConfiguration: true);
    await _openBlueprint(
      initialTemplate: selected.create(
        localize: VenueLayoutLocalizations.of(context).text,
      ),
    );
  }

  Future<void> _selectBlueprint({bool chooseAnother = false}) async {
    if (_loadingBlueprintCandidate) return;
    final epoch = _configurationEpoch;
    final picked = await _pickConfiguration('blueprints');
    if (!mounted || picked == null || epoch != _configurationEpoch) return;
    final request = ++_blueprintSelectionRequest;
    setState(() => _loadingBlueprintCandidate = true);
    try {
      final candidate = _clone(_data);
      _applyBlueprint(
        candidate,
        await _prepareBlueprint(picked['item'] as Map),
      );
      candidate['blueprintSourceOccasionId'] =
          ((picked['source'] as Map)['occasion'] as Map)['id'];
      if (!mounted || epoch != _configurationEpoch) return;
      final resolved = await _resolveReferences(candidate, _data);
      if (!mounted ||
          resolved == null ||
          request != _blueprintSelectionRequest ||
          epoch != _configurationEpoch) return;
      _change((d) {
        d.addAll(resolved);
        _inlineFormBundle = null;
        _formEpoch++;
      }, changesConfiguration: true);
      setState(() {
        _blueprintError = null;
        _blueprintOpenFailed = false;
      });
    } catch (error) {
      if (mounted) setState(() => _blueprintError = error.toString());
    } finally {
      if (mounted) setState(() => _loadingBlueprintCandidate = false);
    }
  }

  Future<void> _chooseForm() async {
    final epoch = _configurationEpoch;
    final picked = await _pickConfiguration('forms');
    if (!mounted || picked == null || epoch != _configurationEpoch) return;
    final previous = _clone(_data);
    try {
      final candidate = _clone(_data);
      final source = picked['source'] as Map;
      final form = _clone(picked['item'] as Map);
      form['link'] = (candidate['formDraft'] as Map?)?['link'] ?? '';
      candidate['formDraft'] = form;
      candidate.remove('appearance');
      candidate['appearance'] = {
        ...OccasionSetupAppearance.read(candidate),
        'id': 'custom',
        'preserveSource': true
      };
      candidate['sourceFormId'] = form['id'];
      candidate['formSourceOccasionId'] = (source['occasion'] as Map)['id'];
      candidate['formOrigin'] = (source['occasion'] as Map)['title'];
      candidate['formDefaultsFollowEvent'] = false;
      final plan = (source['blueprints'] as List)
          .whereType<Map>()
          .where((p) => p['id'] == form['blueprint'])
          .firstOrNull;
      if (plan != null)
        _applyBlueprint(candidate, await _prepareBlueprint(plan));
      if (!mounted || epoch != _configurationEpoch) return;
      final next = await _resolveReferences(candidate, _data);
      if (!mounted || next == null || epoch != _configurationEpoch) return;
      _change((d) {
        d.clear();
        d.addAll(next);
        _resetBankAccount(d);
        _adoptFormSettings(d);
        _formEpoch++;
        _formLinkAvailable = null;
        _inlineFormBundle = null;
        _ticketFeature = null;
      }, changesConfiguration: true);
      setState(() => _formUndo = previous);
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
      final step = d['step'];
      final q = d['storyQuestion'];
      d.clear();
      d.addAll(previous);
      d['step'] = step;
      d['storyQuestion'] = q;
      _inlineFormBundle = null;
      _formEpoch++;
      _ticketFeature = null;
      _formLinkAvailable = null;
    }, changesConfiguration: true);
  }

  Future<Map<String, dynamic>?> _resolveReferences(
    Map<String, dynamic> candidate,
    Map<String, dynamic> previous,
  ) async {
    if (!OccasionSetupReferences(candidate).hasIssues) return candidate;
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) =>
          OccasionSetupReferenceDialog(data: candidate, previous: previous),
    );
  }

  Future<void> _repairReferences() async {
    final candidate = Map<String, dynamic>.from(
      jsonDecode(jsonEncode(_data)) as Map,
    );
    final next = await _resolveReferences(candidate, candidate);
    if (!mounted || next == null) return;
    _change((draft) {
      draft['blueprintLayoutDraft'] = next['blueprintLayoutDraft'];
      draft['ticketDraft'] = next['ticketDraft'];
      _ticketFeature = null;
    }, changesConfiguration: true);
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
    final value = DateTime.tryParse(d[question] as String)?.toOccasionTime();
    void update(DateTime selected) => _change((x) {
          final instant = selected.toUtcFromOccasionTime();
          x[question] = instant.toIso8601String();
          if (!isStart) x['endEdited'] = true;
          final end = DateTime.tryParse(x['end'] as String);
          if (isStart &&
              x['endEdited'] != true &&
              end != null &&
              instant.isAfter(end)) {
            x['end'] = instant.toIso8601String();
          }
        }, changesConfiguration: true);
    final start = DateTime.tryParse(d['start'] as String)?.toOccasionTime();
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
      issues.add(MapEntry(1, OccasionSetupStrings.ui('enter_an_event_name')));
    }
    if (!isValidPublicSlug(d['link'] as String, allowEmpty: true)) {
      issues.add(
          MapEntry(1, OccasionSetupStrings.ui('the_event_link_is_invalid')));
    }
    final start = DateTime.tryParse(d['start'] as String);
    final end = DateTime.tryParse(d['end'] as String);
    if (start == null || end == null || end.isBefore(start)) {
      issues.add(MapEntry(
          1, OccasionSetupStrings.ui('the_event_start_and_end_are_invalid')));
    }
    if (d['formEnabled'] == true) {
      if (!OccasionSetupStory.productPricesValid(d))
        issues.add(MapEntry(3, OrdersStrings.priceValidationInvalid));
      if (!OccasionSetupSales.valid(d, DateTime.now()))
        issues.add(MapEntry(3, OccasionSetupSales.text(d, 'invalidTiming')));
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
          MapEntry(
            3,
            OccasionSetupStrings.ui('create_or_copy_a_form_first'),
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
            MapEntry(3,
                OccasionSetupStrings.ui('enter_a_form_name_and_a_valid_link')),
          );
        }
        if (form.form.relatedFields
            .where((field) => field.definition.isTicketField != true)
            .isEmpty) {
          issues.add(
              MapEntry(3, OccasionSetupStrings.ui('the_form_has_no_fields')));
        }
        if (form.form.relatedFields.any(
              (field) => field.definition.type == FormMetadata.fieldTypeTicket,
            ) &&
            form.products.isEmpty) {
          issues.add(
            MapEntry(
                3, OccasionSetupStrings.ui('the_ticket_form_has_no_products')),
          );
        }
      }
    }
    if (SetupBlueprintConfiguration(d).active) {
      if (d['formEnabled'] != true || d['formDraft'] == null) {
        issues.add(
          MapEntry(
            AppConfig.isAppSupported ? 4 : 6,
            OccasionSetupStrings.ui('a_seating_plan_requires_a_form'),
          ),
        );
      }
      if (!_blueprintReady(d)) {
        issues.add(
          MapEntry(
            AppConfig.isAppSupported ? 4 : 6,
            OccasionSetupStrings.ui('the_seating_plan_has_no_seats_yet'),
          ),
        );
      }
    }
    if (OccasionSetupReferences(d).hasIssues) {
      issues.add(MapEntry(3, OccasionSetupStrings.copy('invalidReferences')));
    }
    if (OccasionSetupStory.hasPaidProducts(d) &&
        !OccasionSetupStory.paymentSetupReady(d)) {
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
          OccasionSetupStrings.ui(
              'enter_a_non_negative_number_of_days_or_leave_the_deadli'),
        ),
      );
    }
    if (AppConfig.isAppSupported &&
        d['isPromoted'] == true &&
        (d['introImage'] as String? ?? '').trim().isEmpty) {
      issues.add(
        MapEntry(1, OccasionSetupStrings.story('promotionImageRequired')),
      );
    }
    for (final q in _questions.where(
      (q) => q.key == 'appearance' || q.key == 'ticket',
    )) {
      if (!_questionReady(d, q))
        issues.add(MapEntry(
            q.step,
            OccasionSetupStrings.ui(
                'complete_step', {'step': _shortLabel(q.key)})));
    }
    return issues;
  }

  String _dateForReview(String? raw) {
    final value = DateTime.tryParse(raw ?? '')?.toOccasionTime();
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
    final hasIssue = issues.any((issue) => issue.key == step);
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
    final layout = (d['blueprintLayoutDraft'] as Map?)?['layout'] as Map?;
    final canvas = layout?['canvas'] as Map?;
    final groups = [
      for (final node in layout?['nodes'] as List? ?? const [])
        if (const [
          'table',
          'group',
          'row',
          'section',
        ].contains((node as Map)['kind']))
          {'title': node['label']},
    ];
    final seatCount = _layoutSeatCount(d);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
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
                  OccasionSetupStrings.ui('what_still_needs_attention'),
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
            OccasionSetupStrings.ui('source_and_copying'),
            [
              _reviewRow(OccasionSetupStrings.ui('source_event'),
                  d['source'] as String),
            ],
            issues),
        _reviewSection(
            d,
            1,
            OccasionSetupStrings.ui('event'),
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
                OccasionSetupStrings.story(
                  AppConfig.isAppSupported ? 'promotion' : 'listingTitle',
                ),
                OccasionSetupStrings.story(
                  (AppConfig.isAppSupported
                          ? d['isPromoted'] == true
                          : d['listPubliclyOnPublish'] != false)
                      ? 'enabled'
                      : 'disabled',
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
                  d['formEnabled'] == true
                      ? OccasionSetupStrings.ui('enabled')
                      : OccasionSetupStrings.ui('disabled'),
                ),
                _reviewRow(
                  CommonStrings.schedule,
                  d['copyProgram'] == true
                      ? OccasionSetupStrings.ui('copy')
                      : OccasionSetupStrings.ui('do_not_copy'),
                ),
                _reviewRow(
                  'FeatureInformation.information'.tr(),
                  d['copyInformation'] == true
                      ? OccasionSetupStrings.ui('copy')
                      : OccasionSetupStrings.ui('do_not_copy'),
                ),
                _reviewRow(
                  OccasionSetupStrings.ui('email_templates'),
                  d['copyEmails'] == true
                      ? OccasionSetupStrings.ui('copy')
                      : OccasionSetupStrings.ui('do_not_copy'),
                ),
              ],
              issues),
        _reviewSection(
            d,
            3,
            'FeatureForm.title'.tr(),
            [
              if (d['formEnabled'] != true)
                Text(OccasionSetupStrings.ui(
                    'this_event_does_not_include_a_form'))
              else if (form == null)
                Text(OccasionSetupStrings.ui(
                    'the_form_has_not_been_created_yet'))
              else ...[
                _reviewRow(
                  OccasionSetupStrings.ui('source'),
                  d['formOrigin'] == null
                      ? OccasionSetupStrings.ui('new_form')
                      : OccasionSetupStrings.ui(
                          'copied_from_event', {'title': '${d['formOrigin']}'}),
                ),
                _reviewRow(
                  'FeatureFormSettings.labelFormTitle'.tr(),
                  form.form.definition.title ?? '',
                ),
                _reviewRow(
                  'FeatureFormSettings.labelFormLink'.tr(),
                  form.form.definition.link ?? '',
                ),
                _reviewRow(
                  OccasionSetupSales.text(d, 'saleStart'),
                  OccasionSetupSales.text(
                      d, 'mode.${OccasionSetupSales.mode(d)}'),
                ),
                if (OccasionSetupSales.mode(d) == 'scheduled')
                  _reviewRow(
                    OccasionSetupSales.text(d, 'saleStart'),
                    _dateForReview(d['saleStart'] as String?),
                  ),
                _reviewRow(
                  OccasionSetupSales.text(d, 'saleEnd'),
                  _dateForReview((d['saleEnd'] ?? d['end']) as String?),
                ),
                Text(
                  OccasionSetupStrings.ui('form_field_count', {
                    'count':
                        '${form.form.relatedFields.where((field) => field.definition.isTicketField != true).length}'
                  }),
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
                if (form.products.isEmpty)
                  Text(OccasionSetupStrings.ui('no_products')),
                for (final type in form.productTypes) ...[
                  Text(
                    type.title ?? '',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  for (final product in type.products ?? <ProductModel>[])
                    _reviewRow(
                      product.title ?? '',
                      '${product.price?.toStringAsFixed(d['paymentMethod'] == 'stripe' || d['paymentMethod'] == 'both' ? 2 : 0) ?? '0'} ${product.currencyCode ?? 'CZK'} · limit ${product.maximum?.toString() ?? 'Waitlist.unlimited'.tr()}',
                    ),
                ],
                const SizedBox(height: 6),
                if (AppConfig.isAppSupported &&
                    OccasionSetupStory.hasPaidProducts(d)) ...[
                  _reviewRow(
                    d['paymentMethod'] == 'stripe'
                        ? PaymentMethodStrings.text('onlyStripe')
                        : 'BankAccount.bankAccount'.tr(),
                    d['paymentMethod'] == 'stripe'
                        ? OccasionSetupStrings.story('stripeDraftHint')
                        : OccasionSetupStory.paymentSetupReady(d)
                            ? (d['bankAccountLabel'] as String? ?? '')
                            : OccasionSetupStrings.story(
                                'bankAccountNotConfirmed'),
                  ),
                  _reviewRow(
                    'FeatureFormSettings.labelDeadlineDays'.tr(),
                    '${effectiveSetupDeadlineSeconds(d) / 86400}'.replaceFirst(
                      RegExp(r'\.0$'),
                      '',
                    ),
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
        if (OccasionSetupStory.hasTickets(d))
          _reviewSection(
            d,
            2,
            OccasionSetupStrings.ui('ticket'),
            [
              _reviewRow(
                  TicketDeliveryStrings.text('title'),
                  TicketDeliveryStrings.label(
                      _ticketDraftFeature(d).deliveryMode)),
              _reviewRow(
                OccasionSetupStrings.ui('appearance'),
                (d['ticketDraft'] as Map?)?['layout'] == null
                    ? OccasionSetupStrings.ui('default_template')
                    : OccasionSetupStrings.ui('saved_design'),
              ),
            ],
            issues,
            questionKey: 'ticket',
          ),
        if (!AppConfig.isAppSupported && OccasionSetupStory.hasPaidProducts(d))
          _reviewSection(
              d,
              4,
              OccasionSetupStrings.ui('payment_settings'),
              [
                _reviewRow(
                  d['paymentMethod'] == 'stripe'
                      ? PaymentMethodStrings.text('onlyStripe')
                      : 'BankAccount.bankAccount'.tr(),
                  d['paymentMethod'] == 'stripe'
                      ? OccasionSetupStrings.story('stripeDraftHint')
                      : OccasionSetupStory.paymentSetupReady(d)
                          ? (d['bankAccountLabel'] as String? ?? '')
                          : OccasionSetupStrings.story(
                              'bankAccountNotConfirmed'),
                ),
                _reviewRow(
                  'FeatureFormSettings.labelDeadlineDays'.tr(),
                  '${effectiveSetupDeadlineSeconds(d) / 86400}'.replaceFirst(
                    RegExp(r'\.0$'),
                    '',
                  ),
                ),
              ],
              issues),
        if (OccasionSetupStory.formEnabled(d))
          _reviewSection(
            d,
            AppConfig.isAppSupported ? 4 : 6,
            CommonStrings.blueprint,
            [
              _reviewRow(OccasionSetupStrings.ui('method'),
                  SetupBlueprintConfiguration(d).label),
              if (SetupBlueprintConfiguration(d).active) ...[
                _reviewRow(
                  OccasionSetupStrings.ui('dimensions'),
                  '${canvas?['width'] ?? '-'} × ${canvas?['height'] ?? '-'}',
                ),
                _reviewRow(
                  'Skupiny',
                  groups
                      .map((group) => (group as Map)['title']?.toString() ?? '')
                      .join(', '),
                ),
                _reviewRow(OccasionSetupStrings.ui('seats'), '$seatCount'),
                _reviewRow(
                  OccasionSetupStrings.ui('form_link'),
                  form?.form.definition.title ??
                      OccasionSetupStrings.ui('missing_form'),
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
            OccasionSetupStrings.ui('privacy_and_completion'),
            [
              Text(OccasionSetupSales.text(d, 'privacy')),
              if (d['formEnabled'] == true)
                Text(
                  OccasionSetupSales.text(
                    d,
                    'completion.${OccasionSetupSales.mode(d)}',
                  ),
                ),
              const SizedBox(height: 8),
              Text(FormStrings.automaticPublicLink),
            ],
            issues),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: d['reviewConfirmed'] == true,
          onChanged: issues.isEmpty
              ? (value) => _change((x) => x['reviewConfirmed'] = value == true)
              : null,
          title: Text(OccasionSetupStrings.story('reviewConfirmation')),
        ),
        TextButton(
          onPressed: _leave,
          child: Text(OccasionSetupSales.text(d, 'saveAndLeave')),
        ),
        if (_finalizeError != null) Text(_finalizeError!),
      ],
    );
  }

  Widget _switch(Map<String, dynamic> data, String key, String label) =>
      SwitchListTile.adaptive(
        title: Text(label),
        value: data[key] == true,
        onChanged: (value) =>
            _change((draft) => draft[key] = value, changesConfiguration: true),
      );

  Widget _body(Map<String, dynamic> d) {
    final questionKey = _questions[_questionIndex(d)].key;
    if (questionKey == 'appearance') return _appearanceSettings(d);
    if (questionKey == 'ticket') return _ticketChoices(d);
    if (_questions[_questionIndex(d)].key == 'saleTiming')
      return OccasionSetupSaleSettings(
        data: d,
        onChanged: (patch) =>
            _change((x) => x.addAll(patch), changesConfiguration: true),
      );
    if (_questions[_questionIndex(d)].key == 'promotion' &&
        AppConfig.isAppSupported) {
      return OccasionSetupPromotion(
        data: d,
        onChanged: (patch) =>
            _change((x) => x.addAll(patch), changesConfiguration: true),
      );
    }
    if (_questions[_questionIndex(d)].key == 'promotion') {
      return SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: Text(OccasionSetupStrings.story('listingTitle')),
        subtitle: Text(OccasionSetupStrings.story('listingHint')),
        value: d['listPubliclyOnPublish'] != false,
        onChanged: (value) => _change(
          (x) => x['listPubliclyOnPublish'] = value,
          changesConfiguration: true,
        ),
      );
    }
    if (_questions[_questionIndex(d)].key == 'paymentTiming') {
      if (d['paymentMethod'] == 'stripe')
        return Text(OccasionSetupStrings.story('stripeReservation'));
      return OccasionSetupCommunication(
        key: const ValueKey('payment-timing'),
        paymentTiming: true,
        draftId: _stored.id,
        unitId: _stored.unit,
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
        loadPreview: _loadEmailPreview,
        draftId: _stored.id,
        unitId: _stored.unit,
        data: d,
        onChanged: (patch) {
          if (patch.containsKey('ticketDraft')) _ticketFeature = null;
          _change((x) => x.addAll(patch), changesConfiguration: true);
        },
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
    if (_questions[_questionIndex(d)].key == 'verification') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(OccasionSetupStrings.story('verificationHint')),
          const SizedBox(height: 20),
          UnitLegalProfileSection(
            unitId: _stored.unit,
            canEdit: RightsService.hasCapability(
              AuthorizationCapabilities.unitLegalProfileWrite,
            ),
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
                child:
                    Text('$_sourceError ${OccasionSetupStrings.ui('retry')}'),
              ),
            OccasionSetupSourcePicker(
              sources: _sources,
              selectedId: d['sourceId'] as int?,
              unavailableLabel: d['source'] as String?,
              label: _sourceLabel,
              onChanged: _selectSource,
            ),
            if (d['sourceId'] != null) ...[
              if (AppConfig.isAppSupported)
                _switch(
                  d,
                  'copyProgram',
                  '${CommonStrings.schedule} a ${CommonStrings.places}',
                ),
              if (AppConfig.isAppSupported)
                _switch(
                  d,
                  'copyInformation',
                  'FeatureInformation.information'.tr(),
                ),
              _switch(
                d,
                'copyEmails',
                OccasionSetupStrings.story('copyEmails'),
              ),
            ],
            if (_loadingDetail) const LinearProgressIndicator(),
            if (_sources.isEmpty && !_loadingSources && _sourceError == null)
              Text(
                OccasionSetupStrings.ui(
                    'this_organization_has_no_saved_templates_yet'),
              ),
            Text(
              OccasionSetupStrings.ui(
                  'copying_transfers_only_the_selected_settings_orders_par'),
            ),
          ],
        );
      case 1:
        return _basics(d);
      case 2:
        if (!AppConfig.isAppSupported) return _ticketSettings(d);
        return Column(
          children: [_switch(d, 'formEnabled', 'Registrace a prodej')],
        );
      case 3:
        if (d['formEnabled'] == false) {
          return Text(OccasionSetupStrings.ui('the_form_is_disabled'));
        }
        final formData = d['formDraft'];
        final formBundle = formData is Map
            ? (_inlineFormBundle ??= draftFormBundle(
                Map<String, dynamic>.from(formData),
              ))
            : null;
        final referenceIssues = OccasionSetupReferences(d).hasIssues;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (referenceIssues) ...[
              Text(OccasionSetupStrings.copy('invalidReferences')),
              OutlinedButton(
                onPressed: _repairReferences,
                child: Text(OccasionSetupStrings.copy('repairReferences')),
              ),
              const SizedBox(height: 16),
            ],
            if (formBundle == null)
              ElevatedButton.icon(
                onPressed: _chooseForm,
                icon: const Icon(Icons.add),
                label: Text(OccasionSetupStrings.story('copyForm')),
              )
            else ...[
              if (d['formOrigin'] != null)
                Text(OccasionSetupStrings.ui(
                    'copied_from_event', {'title': '${d['formOrigin']}'})),
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
                onChanged: (value, automatic) => _change(
                  (x) {
                    x['formLinkAutomatic'] = automatic;
                    (x['formDraft'] as Map)['link'] = value;
                    _inlineFormBundle?.form.definition = _inlineFormBundle!
                        .form.definition
                        .copyWith(link: value);
                  },
                  changesConfiguration: true,
                  invalidateUndo: !automatic,
                ),
              ),
              const SizedBox(height: 10),
              const SizedBox(height: 12),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                children: [
                  if (_sources.any(
                    (source) => (source['forms'] as List).isNotEmpty,
                  ))
                    OutlinedButton.icon(
                      onPressed: _chooseForm,
                      icon: const Icon(Icons.swap_horiz),
                      label: Text(OccasionSetupStrings.story('copyForm')),
                    ),
                ],
              ),
            ],
            if (_formUndo != null)
              TextButton(
                onPressed: _undoForm,
                child: Text(OccasionSetupStrings.story('undoCopy')),
              ),
            if (formBundle != null) ...[
              if (!OccasionSetupStory.productPricesValid(d))
                Text(OrdersStrings.priceValidationInvalid,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 18),
              FormEditorContent.prototype(
                key: ValueKey('${d['id']}-inline-form-$_formEpoch'),
                embedded: true,
                bundle: formBundle,
                onPrototypeHydrated: (saved) => _change(
                  (x) {
                    x['formDraft'] = serializeDraftForm(saved.form);
                  },
                  changesConfiguration: true,
                  invalidateUndo: false,
                ),
                onPrototypeSave: (saved) => _change((x) {
                  x['formDraft'] = serializeDraftForm(saved.form);
                  if (SetupBlueprintConfiguration(x).active &&
                      !saved.form.usesSeatSelection) {
                    SetupBlueprintConfiguration(x).clear();
                  }
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

  Widget _ticketChoices(Map<String, dynamic> d) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(OccasionSetupStrings.ui('use_tickets')),
            subtitle: Text(OccasionSetupStrings.ui(
                'participants_receive_a_ticket_with_an_admission_qr_code')),
            value: OccasionSetupStory.hasTickets(d),
            onChanged: (enabled) => _change((x) {
              _inlineFormBundle = null;
              OccasionSetupStory.setTicketsEnabled(x, enabled);
              if (enabled && x['ticketDraft'] is! Map) {
                OccasionSetupAppearance.apply(
                    x, OccasionSetupAppearance.read(x));
              }
              _ticketFeature = null;
              _editEpoch++;
            }, changesConfiguration: true),
          ),
          if (OccasionSetupStory.hasTickets(d)) ...[
            const SizedBox(height: 20),
            if (_ticketDraftFeature(d).deliveryMode.includesPdf)
              OccasionSetupTicketGallery(
                key: ValueKey('ticket-gallery-$_editEpoch'),
                selectedId: d['ticketTemplateId'] as String?,
                currentTemplate: ((d['ticketDraft'] as Map?)?['layout']
                                as Map?)?['templates']?[
                            _ticketDraftFeature(d).ticketType == 'named'
                                ? 'named'
                                : 'wide'] ==
                        null
                    ? null
                    : Map<String, dynamic>.from(((d['ticketDraft']
                            as Map)['layout'] as Map)['templates'][
                        _ticketDraftFeature(d).ticketType == 'named'
                            ? 'named'
                            : 'wide']),
                appearance: OccasionSetupAppearance.read(d),
                loadResources: () async {
                  if (!await _flush())
                    throw StateError('Koncept se nepodařilo uložit');
                  final service = TicketLayoutService()
                      .forSetupDraft(_stored.id, _stored.unit,
                          revision: _stored.revision)
                      .withPreviewOccasion(TicketPreviewOccasion(
                          title: d['title'] as String,
                          startTime: DateTime.tryParse(d['start'] as String),
                          endTime: DateTime.tryParse(d['end'] as String),
                          placeName: d['placeName'] as String?));
                  final resources = await service.resolve(
                      0,
                      _ticketDraftFeature(d).ticketType == 'named'
                          ? 'named'
                          : 'wide',
                      (d['ticketDraft'] as Map?)?['layout'] == null
                          ? null
                          : Map<String, dynamic>.from(
                              (d['ticketDraft'] as Map)['layout']),
                      _ticketDraftFeature(d).ticketBackground);
                  final sharedFont = OccasionSetupAppearance
                      .fonts[OccasionSetupAppearance.read(d)['fontFamily']];
                  if (sharedFont != null &&
                      !resources.fonts.containsKey(sharedFont)) {
                    resources.fonts[sharedFont] =
                        await service.fontForSetupDraft(_stored.id, sharedFont);
                  }
                  return resources;
                },
                onSelected: (selection) => _change((x) {
                  final feature = Map<String, dynamic>.from(
                      x['ticketDraft'] as Map? ??
                          {'code': 'ticket', 'is_enabled': true});
                  feature['layout'] = {
                    'schemaVersion': 3,
                    'templates': {
                      _ticketDraftFeature(x).ticketType == 'named'
                          ? 'named'
                          : 'wide': selection.value
                    }
                  };
                  feature['background'] = selection.background;
                  x['ticketDraft'] = feature;
                  x['ticketTemplateId'] = selection.key;
                  x['ticketTemplateSource'] = selection.source;
                  _ticketFeature = null;
                }, changesConfiguration: true),
              ),
            const SizedBox(height: 20),
            _ticketSettings(d),
          ],
        ],
      );

  Widget _ticketSettings(Map<String, dynamic> d) {
    final feature = _ticketDraftFeature(d);
    return EditorDraftScope(
      onChanged: () {
        final next = feature.toJson();
        if (jsonEncode(TicketFeature.fromJson(
                    Map<String, dynamic>.from(d['ticketDraft'] as Map))
                .toJson()) ==
            jsonEncode(next)) return;
        _change((x) {
          x['ticketDraft'] = next;
          x['appearance'] = {
            ...OccasionSetupAppearance.read(x),
            'id': 'custom',
            'preserveSource': true
          };
          x.remove('ticketTemplateId');
          x.remove('ticketTemplateSource');
          _editEpoch++;
        }, changesConfiguration: true);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: TicketSettings(
              key: ValueKey('${d['id']}-ticket-$_editEpoch'),
              feature: feature,
              occasionId: 0,
              service: TicketLayoutService().forSetupDraft(
                _stored.id,
                _stored.unit,
                revision: _stored.revision,
              ),
              productEditing: false,
              showScannerSettingsLink: false,
              showDeliverySelector: false,
              showPreview: false,
              previewOccasion: TicketPreviewOccasion(
                title: d['title'] as String,
                startTime: DateTime.tryParse(d['start'] as String),
                endTime: DateTime.tryParse(d['end'] as String),
                placeName: d['placeName'] as String?,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _paymentSettings(Map<String, dynamic> d) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (d['paymentChoicesEnabled'] == true) ...[
            PaymentMethodCards(
              value: FormPaymentMethod.values
                  .firstWhere((m) => m.name == (d['paymentMethod'] ?? 'bank')),
              canSelectStripe: true,
              stripeFirst: true,
              onChanged: (method) => _change(
                  (x) => x['paymentMethod'] = method.name,
                  changesConfiguration: true),
            ),
            const SizedBox(height: 16),
          ],
          if (d['paymentMethod'] == 'stripe' ||
              d['paymentMethod'] == 'both') ...[
            Text(OccasionSetupStrings.story('stripeDraftHint')),
            if (StripeFeature.canManage)
              TextButton(
                  onPressed: () async {
                    if (!await _flush() || !mounted) return;
                    await RouterService.navigate(
                        context, '/unit/${_stored.unit}/edit/card-payments');
                  },
                  child: Text(OccasionSetupStrings.story('setupStripe'))),
            const SizedBox(height: 16),
          ],
          if (d['paymentMethod'] != 'stripe') ...[
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
        ],
      );

  Widget _blueprintSettings(Map<String, dynamic> d) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final mode in ['none', 'new', 'copy'])
          RadioListTile<String>(
            value: mode,
            groupValue: SetupBlueprintConfiguration(d).modeId,
            title: Text(OccasionSetupStrings.story('blueprint.$mode')),
            onChanged: (value) {
              if (value == 'copy') {
                _selectBlueprint();
                return;
              }
              if (value == 'new') {
                _startNewBlueprint();
                return;
              }
              _blueprintSelectionRequest++;
              _change((d) {
                SetupBlueprintConfiguration(d).clear();
                _inlineFormBundle = null;
                _formEpoch++;
              }, changesConfiguration: true);
            },
          ),
        if (SetupBlueprintConfiguration(d).mode == SetupBlueprintMode.copy)
          TextButton(
            onPressed: _loadingBlueprintCandidate
                ? null
                : () => _selectBlueprint(chooseAnother: true),
            child: Text(OccasionSetupStrings.ui('choose_another_seating_plan')),
          ),
        if (_loadingBlueprintCandidate) const LinearProgressIndicator(),
        if (_blueprintError != null) ...[
          Text(_blueprintError!),
          TextButton(
            onPressed: _blueprintOpenFailed ? _openBlueprint : _selectBlueprint,
            child: Text(OccasionSetupStrings.ui('retry')),
          ),
        ],
        if (SetupBlueprintConfiguration(d).active) ...[
          if (_layoutSeatCount(d) > 0)
            Text(BlueprintStrings.seatCount(_layoutSeatCount(d))),
          if (_layoutAreaCount(d) > 0)
            Text(BlueprintStrings.areaCount(_layoutAreaCount(d))),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _openingBlueprint || _loadingBlueprintCandidate
                ? null
                : _openBlueprint,
            icon: const Icon(Icons.grid_on),
            label: Text(OccasionSetupStrings.story('editBlueprint')),
          ),
          const SizedBox(height: 12),
          Text(OccasionSetupStrings.ui(
              'seating_plan_changes_are_saved_in_this_draft')),
        ],
      ],
    );
  }

  Future<void> _jump(String key) async {
    if (_presentationUploading || _finalizeCommand != null) return;
    final target = _questions.indexWhere((q) => q.key == key);
    if (target < 0) return;
    FocusManager.instance.primaryFocus?.unfocus();
    _change((d) => _goToQuestion(d, target));
    await _flush();
    if (key == 'verification') _refreshVerification();
  }

  String _shortLabel(String key) =>
      {
        'source': OccasionSetupStrings.ui('copy_59'),
        'name': OccasionSetupStrings.ui('name'),
        'dates': OccasionSetupStrings.ui('dates'),
        'appearance': OccasionSetupStrings.ui('appearance'),
        'ticket': 'Vstupenky',
        'link': OccasionSetupStrings.ui('link'),
        'content': OccasionSetupStrings.ui('content'),
        'form': OccasionSetupStrings.ui('form'),
        'saleTiming': OccasionSetupStrings.ui('opening'),
        'payments': OccasionSetupStrings.ui('payments'),
        'pricing': OccasionSetupStrings.ui('prices'),
        'presentation': OccasionSetupStrings.ui('presentation'),
        'promotion': OccasionSetupStrings.ui('publication'),
        'team': OccasionSetupStrings.ui('team'),
        'paymentTiming': OccasionSetupStrings.ui('payment_deadline'),
        'communication': OccasionSetupStrings.ui('communication'),
        'blueprint': OccasionSetupStrings.ui('venue'),
        'verification': OccasionSetupStrings.ui('verification'),
        'review': OccasionSetupStrings.ui('review'),
      }[key] ??
      key;
  Future<FormFontCatalog> _loadAppearanceFonts() async {
    final catalog = await FormFontCatalog.load();
    for (final family in OccasionSetupAppearance.fonts.keys) {
      await catalog.ensureFamily(family);
    }
    return catalog;
  }

  late Future<FormFontCatalog> _appearanceFonts = _loadAppearanceFonts();

  Widget _appearanceSettings(Map<String, dynamic> d) =>
      FutureBuilder<FormFontCatalog>(
        future: _appearanceFonts,
        builder: (context, snapshot) {
          if (snapshot.hasError)
            return TextButton(
                onPressed: () => setState(() {
                      _appearanceFonts = _loadAppearanceFonts();
                    }),
                child: Text(OccasionSetupStrings.ui(
                    'fonts_could_not_be_loaded_retry')));
          if (!snapshot.hasData)
            return const Center(child: CircularProgressIndicator());
          return _loadedAppearanceSettings(d, snapshot.data!);
        },
      );

  Widget _loadedAppearanceSettings(
      Map<String, dynamic> d, FormFontCatalog catalog) {
    final a = OccasionSetupAppearance.read(d);
    Color color(dynamic hex) => Color(int.parse('ff$hex', radix: 16));
    String hex(Color c) =>
        c.toARGB32().toRadixString(16).substring(2).toUpperCase();
    void apply(Map<String, dynamic> next) {
      if (!OccasionSetupAppearance.fonts.containsKey(next['fontFamily'])) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(OccasionSetupStrings.ui(
                'choose_a_font_supported_by_both_the_form_and_pdf_first')),
          ),
        );
        return;
      }
      _change(
        (x) => OccasionSetupAppearance.apply(x, next),
        changesConfiguration: true,
      );
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
            fontFamily: p['fontFamily'] as String,
          ),
      ],
      selectedPresetId: a['id'] as String?,
      onPresetSelected: (id) => apply(
        Map<String, dynamic>.from(
          OccasionSetupAppearance.presets.firstWhere((p) => p['id'] == id),
        ),
      ),
      fontStyle: (family, base) => catalog.families.contains(family)
          ? catalog
              .getTextTheme(family, TextTheme(bodyMedium: base))
              .bodyMedium!
          : base.copyWith(fontFamily: family),
      fontFamily: a['fontFamily'] as String,
      fontFamilies: {
        ...OccasionSetupAppearance.fonts.keys,
        a['fontFamily'] as String,
      }.toList(),
      onFontChanged: (v) => custom('fontFamily', v),
      primaryColor: color(a['primary']),
      secondaryColor: color(a['secondary']),
      gradient: a['gradient'] as bool,
      onPrimaryChanged: (v) => custom('primary', hex(v)),
      onSecondaryChanged: (v) => custom('secondary', hex(v)),
      onGradientChanged: (v) => custom('gradient', v),
      formPreview: OccasionSetupFormPreview(
        key: ValueKey('form-preview-$_editEpoch'),
        draft: d,
      ),
    );
  }

  Widget _wizard(Map<String, dynamic> d) {
    final step = d['step'] as int;
    final index = _questionIndex(d);
    final question = _questions[index];
    final isReview = question.key == 'review';
    final reviewReady = isReview && _reviewIssues(d).isEmpty;
    final isEditor = question.key == 'form' ||
        question.key == 'appearance' ||
        question.key == 'ticket';
    final numbered = _questions.where((q) => !q.optional).toList();
    return OccasionSetupStoryShell(
      questionKeys: [for (final q in _questions) q.key],
      questionLabels: [for (final q in _questions) _shortLabel(q.key)],
      questionNumbers: [
        for (final q in _questions)
          q.optional ? null : numbered.indexWhere((n) => n.key == q.key) + 1,
      ],
      questionSections: [
        for (final q in _questions)
          [
            'name',
            'dates',
            'appearance',
            'link',
            'source',
            'presentation',
          ].contains(q.key)
              ? OccasionSetupStrings.ui('basics')
              : q.step == 5
                  ? OccasionSetupStrings.ui('finish')
                  : OccasionSetupStory.hasTickets(d)
                      ? 'Prodej'
                      : 'Registrace',
      ],
      completedKeys: {
        for (final q in _questions)
          if (!q.optional && _questionReady(d, q)) q.key,
      },
      visitedKeys:
          (d['visitedQuestions'] as List? ?? []).cast<String>().toSet(),
      introductionAction: (_sources.isNotEmpty ||
              _loadingSources ||
              _sourceError != null)
          ? TextButton(
              onPressed: () => _change((x) {
                x['storyQuestion'] = 'source';
                x['step'] = 0;
              }),
              child: Text(
                _loadingSources
                    ? OccasionSetupStrings.ui('loading_templates')
                    : _sourceError ??
                        OccasionSetupStrings.ui('create_a_copy_of_an_event'),
              ),
            )
          : null,
      questionTitles: [
        for (final item in _questions)
          item.key == 'appearance'
              ? OccasionSetupStrings.ui('how_should_the_event_look')
              : item.key == 'ticket'
                  ? OccasionSetupStrings.ui('will_participants_need_a_ticket')
                  : item.key == 'team'
                      ? OccasionTeamInvitationStrings.text('question')
                      : item.key == 'saleTiming'
                          ? OccasionSetupSales.text(d, 'question')
                          : item.key == 'promotion' && !AppConfig.isAppSupported
                              ? OccasionSetupStrings.story('listingTitle')
                              : OccasionSetupStrings.story(
                                  '${item.key}Question'),
      ],
      currentIndex: index,
      eventTitle:
          '${OccasionSetupStrings.story('draft')} · ${(d['title'] as String).trim().isEmpty ? OccasionSetupStrings.untitled : d['title']}',
      status: _error != null
          ? OccasionSetupStrings.saveFailed
          : _pending != null || _dirty
              ? OccasionSetupStrings.saving
              : OccasionSetupStrings.saved,
      questionCount: question.optional
          ? OccasionSetupStrings.ui('optional_section')
          : OccasionSetupStrings.questionNumber(
              numbered.indexWhere((q) => q.key == question.key) + 1,
              numbered.length,
            ),
      segmentStates: [
        OccasionSetupSales.text(d, 'previousQuestion'),
        OccasionSetupStrings.story('currentQuestion'),
        OccasionSetupStrings.story('upcomingQuestion'),
      ],
      leaveLabel: OccasionSetupStrings.story('leave'),
      backLabel: CommonStrings.back,
      onLeave: _pending != null || _presentationUploading ? null : _leave,
      onBack: index == 0 || _presentationUploading
          ? null
          : () => _jump(_questions[index - 1].key),
      onNext:
          isReview || _presentationUploading || _finalizing ? null : _advance,
      nextLabel: CommonStrings.continueAction,
      onQuestionSelected: _presentationUploading ? null : _jump,
      maxContentWidth: question.key == 'appearance' ||
              question.key == 'ticket' ||
              question.key == 'communication'
          ? 1120
          : step == 3
              ? StylesConfig.formMaxWidth
              : isReview || question.optional
                  ? 960
                  : 680,
      centerQuestion: !isEditor &&
          !isReview &&
          !question.optional &&
          question.key != 'communication',
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
        onPressed: _presentationUploading || _finalizing
            ? null
            : isReview
                ? (reviewReady && d['reviewConfirmed'] == true
                    ? _finalize
                    : null)
                : _advance,
        child: Text(
          isReview
              ? OccasionSetupSales.createLabel(d)
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
