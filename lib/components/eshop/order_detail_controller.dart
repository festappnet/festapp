import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fstapp/data_services/rights_service.dart';

import 'models/order_admin_detail.dart';
import 'order_blueprint_cache.dart';
import 'order_commands.dart';
import 'order_contact_controller.dart';
import 'order_detail_strings.dart';

/// One identity, generation and contact draft across every detail tab.
class OrderDetailController extends ChangeNotifier {
  OrderDetailController({
    required this.orderId,
    required this.occasionId,
    Future<dynamic> Function(String, Map<String, dynamic>)? read,
    OrderCommands? commands,
    OrderBlueprintCache? blueprints,
  }) : _blueprints = blueprints ?? OrderBlueprintCache(),
       _commands = commands,
       _hasInjectedRead = read != null,
       _read =
           read ??
           ((name, args) => Supabase.instance.client.rpc(name, params: args)) {
    contact.addListener(_draftChanged);
    note.addListener(_draftChanged);
    RightsService.occasionLinkModelNotifier.addListener(_contextChanged);
  }
  final int orderId, occasionId;
  final OrderCommands? _commands;
  final bool _hasInjectedRead;
  final OrderBlueprintCache _blueprints;
  final Future<dynamic> Function(String, Map<String, dynamic>) _read;
  late final contact = OrderContactController(
    orderId: orderId,
    occasionId: occasionId,
    commands: _commands ?? (_hasInjectedRead ? null : SupabaseOrderCommands(Supabase.instance.client)),
    read: _read,
    validContext: () => validContext,
    loadSnapshot: () async {
      if (!await load()) throw StateError('Refresh failed');
      return {'order': detail!.order, 'emailSummary': detail!.emailSummary};
    },
  );
  TextEditingController get email => contact.email;
  final note = TextEditingController();
  OrderAdminDetail? detail;
  bool loading = true, stale = false, _busy = false;
  bool get busy => _busy || contact.busy;
  bool _disposed = false;
  int _generation = 0;
  String? error;
  final _previews = <int, OrderBlueprintView>{};
  final _inlineDrafts =
      <
        Object,
        ({
          bool Function() isDirty,
          VoidCallback discard,
          Future<void> Function() save,
        })
      >{};
  void registerInlineDraft(
    Object key, {
    required bool Function() isDirty,
    required VoidCallback discard,
    required Future<void> Function() save,
  }) {
    _inlineDrafts[key] = (isDirty: isDirty, discard: discard, save: save);
  }

  void unregisterInlineDraft(Object key) => _inlineDrafts.remove(key);
  void inlineDraftChanged() => _draftChanged();

  int get dirtyInlineDraftCount =>
      _inlineDrafts.values.where((draft) => draft.isDirty()).length;
  bool get _emailDirty => contact.dirty;
  int get dirtyDraftCount => dirtyInlineDraftCount + (_emailDirty ? 1 : 0);

  /// One user action, using the existing owners. A confirmed draft is cleaned
  /// before readback; later failure leaves only the remaining work pending.
  Future<void> saveDrafts() async {
    if (busy || stale || !validContext || detail == null) {
      throw StateError(OrderDetailStrings.text('responses_unavailable'));
    }
    final pending = _inlineDrafts.entries
        .where((entry) => entry.value.isDirty())
        .toList();
    setBusy(true);
    try {
      await contact.ensureNoPending();
      if (_emailDirty) {
        if (!detail!.canWrite ||
            !detail!.model.allows('edit') ||
            !contact.validEmail) {
          throw StateError(OrderDetailStrings.text('responses_unavailable'));
        }
        await contact.save(resend: false);
        if (contact.stale || stale || !validContext)
          throw StateError(OrderDetailStrings.text('udaje_nejsou_aktualni'));
      }
      for (final entry in pending) {
        if (!validContext || stale)
          throw StateError(OrderDetailStrings.text('responses_unavailable'));
        if (!_inlineDrafts.containsKey(entry.key) || !entry.value.isDirty())
          continue;
        await entry.value.save();
        if (entry.value.isDirty())
          throw StateError(OrderDetailStrings.text('responses_unavailable'));
        // Advance the shared full-array fence before another field is saved.
        if (!await load())
          throw StateError(OrderDetailStrings.text('udaje_nejsou_aktualni'));
      }
    } finally {
      setBusy(false);
    }
  }

  bool get dirty =>
      detail != null &&
      (contact.dirty ||
          note.text != (detail!.order['note_hidden'] ?? '') ||
          _inlineDrafts.values.any((draft) => draft.isDirty()));

  /// Discard only the local fields after the user's explicit choice. A durable
  /// uncertain command is independent and is never removed by this operation.
  void discardDraft() {
    if (busy || detail == null) return;
    contact.discard();
    note.text = detail!.order['note_hidden']?.toString() ?? '';
    for (final draft in _inlineDrafts.values.toList()) {
      draft.discard();
    }
    _draftChanged();
  }

  bool get validContext =>
      !_disposed && RightsService.currentOccasionId() == occasionId;
  void _draftChanged() {
    if (!_disposed) notifyListeners();
  }

  void _contextChanged() {
    if (validContext) return;
    _generation++;
    detail = null;
    _previews.clear();
    _blueprints.clear();
    error = 'Objednávka není dostupná.';
    notifyListeners();
  }

  Future<bool> load() async {
    final generation = ++_generation;
    final keepEmail = detail != null && contact.dirty;
    final keepNote =
        detail != null && note.text != (detail!.order['note_hidden'] ?? '');
    loading = detail == null;
    error = null;
    notifyListeners();
    try {
      final result = detailMap(
        await _read('get_order_admin_detail', {
          'p_order': orderId,
          'p_occasion': occasionId,
        }),
      );
      if (_disposed || generation != _generation || !validContext) return false;
      if (result['code'] != 200) throw StateError('Order unavailable');
      detail = OrderAdminDetail(detailMap(result['data']));
      _previews.clear();
      contact.acceptSnapshot(
        detail!.order,
        detail!.emailSummary,
        acceptSavedContact: !keepEmail,
      );
      if (!keepNote) note.text = detail!.order['note_hidden']?.toString() ?? '';
      loading = false;
      stale = false;
      notifyListeners();
      return true;
    } catch (_) {
      if (_disposed || generation != _generation) return false;
      loading = false;
      stale = true;
      error = 'Údaje se nepodařilo načíst. Obnovte je prosím.';
      notifyListeners();
      return false;
    }
  }

  Future<OrderBlueprintView> blueprint(int id) async {
    if (_previews.containsKey(id)) return _previews[id]!;
    for (var attempt = 0; attempt < 2; attempt++) {
      final generation = _generation;
      final known = _blueprints.lookup(occasionId, id);
      final result = detailMap(
        await _read('get_order_blueprint_view', {
          'p_order': orderId,
          'p_occasion': occasionId,
          'p_blueprint': id,
          if (known != null) 'p_known_layout_revision': known.revision,
          'p_expected_placement_fingerprint': detail!.placementFingerprint,
        }),
      );
      if (!validContext || generation != _generation)
        throw StateError('Context changed');
      if (result['code'] == 409 && attempt == 0) {
        // A read-only map must not race a batch save's own readback generation.
        if (busy) throw StateError('Context changed');
        if (!await load()) throw StateError('Refresh failed');
        continue;
      }
      if (result['code'] != 200)
        throw StateError('Plan unavailable or changed');
      final view = _blueprints.decode(
        detailMap(result['data']),
        occasionId: occasionId,
        blueprintId: id,
        known: known,
      );
      final expectedRevision = detail!.plans
          .where((plan) => plan['id'] == id)
          .firstOrNull?['layoutRevision'];
      if (expectedRevision != view.plan.revision) {
        // Geometry may be saved between the detail and preview reads without
        // changing the order's placement fingerprint. Refresh once; retain the
        // already authorized immutable drawing for the subsequent thin read.
        if (attempt == 0 && !busy && await load()) continue;
        throw StateError('Plan revision changed');
      }
      return _previews[id] = view;
    }
    throw StateError('Placement changed');
  }

  void setBusy(bool value) {
    if (_disposed) return;
    _busy = value;
    contact.hostBusy = value;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _inlineDrafts.clear();
    _generation++;
    RightsService.occasionLinkModelNotifier.removeListener(_contextChanged);
    contact.removeListener(_draftChanged);
    contact.dispose();
    note.dispose();
    super.dispose();
  }
}
