import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fstapp/data_services/rights_service.dart';

import 'models/order_admin_detail.dart';
import 'order_commands.dart';
import 'order_detail_strings.dart';

import 'package:festapp_core/forms.dart';

/// One identity, generation and contact draft across every detail tab.
class OrderDetailController extends ChangeNotifier {
  OrderDetailController({
    required this.orderId,
    required this.occasionId,
    Future<dynamic> Function(String, Map<String, dynamic>)? read,
    OrderCommands? commands,
  }) : _commands = commands,
       _read =
           read ??
           ((name, args) => Supabase.instance.client.rpc(name, params: args)) {
    email.addListener(_draftChanged);
    note.addListener(_draftChanged);
    RightsService.occasionLinkModelNotifier.addListener(_contextChanged);
  }
  final int orderId, occasionId;
  final OrderCommands? _commands;
  final Future<dynamic> Function(String, Map<String, dynamic>) _read;
  final email = TextEditingController(), note = TextEditingController();
  OrderAdminDetail? detail;
  bool loading = true, stale = false, busy = false;
  bool _disposed = false;
  int _generation = 0;
  String? error;
  final maps = <int, Map<String, dynamic>>{};
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
  bool get _emailDirty =>
      detail != null && email.text != (detail!.order['data']?['email'] ?? '');
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
      if (_emailDirty) {
        if (!detail!.canWrite ||
            !detail!.model.allows('edit') ||
            !EmailAddress.isValid(email.text.trim())) {
          throw StateError(OrderDetailStrings.text('responses_unavailable'));
        }
        final order = detail!.order;
        final result =
            await (_commands ?? SupabaseOrderCommands(Supabase.instance.client))
                .repairEmail(
                  orderId: orderId,
                  expectedEmail: order['data']?['email'] ?? '',
                  expectedState: order['state'],
                  expectedPaymentVersion:
                      (order['email_payment_version'] as num).toInt(),
                  expectedPaymentFingerprint:
                      order['email_payment_fingerprint'] as String,
                  email: email.text.trim(),
                  resend: false,
                );
        if (result['code'] != 200) {
          await load();
          throw StateError(OrderDetailStrings.text('responses_changed'));
        }
        if (!await load(acceptSavedContact: true))
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
      (email.text != (detail!.order['data']?['email'] ?? '') ||
          note.text != (detail!.order['note_hidden'] ?? '') ||
          _inlineDrafts.values.any((draft) => draft.isDirty()));

  /// Discard only the local fields after the user's explicit choice. A durable
  /// uncertain command is independent and is never removed by this operation.
  void discardDraft() {
    if (busy || detail == null) return;
    email.text = detail!.order['data']?['email']?.toString() ?? '';
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
    maps.clear();
    error = 'Objednávka není dostupná.';
    notifyListeners();
  }

  Future<bool> load({bool acceptSavedContact = false}) async {
    final generation = ++_generation;
    final keepEmail =
        detail != null &&
        email.text != (detail!.order['data']?['email'] ?? '') &&
        !acceptSavedContact;
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
      maps.clear();
      if (!keepEmail) {
        email.text = detail!.order['data']?['email']?.toString() ?? '';
      }
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

  Future<Map<String, dynamic>> blueprint(int id) async {
    if (maps.containsKey(id)) return maps[id]!;
    for (var attempt = 0; attempt < 2; attempt++) {
      final generation = _generation;
      final result = detailMap(
        await _read('get_order_blueprint_view', {
          'p_order': orderId,
          'p_occasion': occasionId,
          'p_blueprint': id,
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
      return maps[id] = detailMap(result['data']);
    }
    throw StateError('Placement changed');
  }

  void setBusy(bool value) {
    if (_disposed) return;
    busy = value;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _inlineDrafts.clear();
    _generation++;
    RightsService.occasionLinkModelNotifier.removeListener(_contextChanged);
    email.dispose();
    note.dispose();
    super.dispose();
  }
}
