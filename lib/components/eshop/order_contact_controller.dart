import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:festapp_core/forms.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fstapp/components/email_delivery/order_email_issue.dart';
import 'package:fstapp/components/email_delivery/email_delivery_strings.dart';
import 'package:fstapp/data_services/client_sync/client_command_identity.dart';
import 'package:fstapp/data_services/rights_service.dart';

import 'order_commands.dart';

/// Shared contact session. Durable commands outlive this UI session.
class OrderContactController extends ChangeNotifier {
  OrderContactController({
    required this.orderId,
    required this.occasionId,
    this.read,
    OrderCommands? commands,
    this.loadSnapshot,
    this.onChanged,
    bool Function()? validContext,
  }) : _injectedCommands = commands,
       _context = validContext {
    _email.addListener(_notify);
    RightsService.occasionLinkModelNotifier.addListener(_contextChanged);
  }
  final int orderId, occasionId;
  final Future<dynamic> Function(String, Map<String, dynamic>)? read;
  final Future<Map<String, dynamic>> Function()? loadSnapshot;
  final Future<void> Function()? onChanged;
  final OrderCommands? _injectedCommands;
  final bool Function()? _context;
  late final OrderCommands _commands =
      _injectedCommands ?? SupabaseOrderCommands(Supabase.instance.client);
  final _email = TextEditingController();
  Map<String, dynamic>? _order, _summary;
  bool _busy = false, _loading = true, _stale = false, _disposed = false;
  bool hostBusy = false;
  String? _feedback;
  int _generation = 0, _contextEpoch = 0;
  ClientCommandIntent? _pendingContact;
  TextEditingController get email => _email;
  Map<String, dynamic>? get order => _order;
  Map<String, dynamic>? get summary => _summary;
  bool get busy => _busy;
  bool get loading => _loading;
  bool get stale => _stale;
  String? get feedback => _feedback;
  ClientCommandIntent? get pendingContact => _pendingContact;
  bool get validEmail => EmailAddress.isValid(_email.text.trim());
  bool get dirty =>
      _order != null && _email.text != (_order!['data']?['email'] ?? '');
  bool get _locked => _busy || hostBusy;
  bool get _sameContext =>
      !_disposed &&
      (_context?.call() ??
          (read != null || RightsService.currentOccasionId() == occasionId));
  String t(String key) => EmailDeliveryStrings.recovery(key);
  Future<dynamic> _read(String name, Map<String, dynamic> args) =>
      read?.call(name, args) ??
      Supabase.instance.client.rpc(name, params: args);
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _update(VoidCallback change) {
    if (_disposed) return;
    change();
    notifyListeners();
  }

  void _contextChanged() {
    if (_sameContext) return;
    _generation++;
    _contextEpoch++;
    _order = null;
    _summary = null;
    _stale = true;
    _notify();
  }

  void acceptSnapshot(
    Map<String, dynamic> order,
    Map<String, dynamic> summary, {
    bool acceptSavedContact = false,
  }) {
    if (!_sameContext) return;
    final keep = dirty && !acceptSavedContact;
    _order = Map.of(order);
    _summary = Map.of(summary);
    _loading = false;
    _stale = false;
    if (!keep) _email.text = order['data']?['email']?.toString() ?? '';
    _notify();
  }

  void _confirmEmail(String value) {
    if (_order == null) return;
    _order = {
      ..._order!,
      'data': {
        ...Map<String, dynamic>.from(_order!['data'] as Map),
        'email': value,
      },
    };
    _email.text = value;
  }

  void discard() {
    if (!_busy && _order != null)
      _email.text = _order!['data']?['email']?.toString() ?? '';
  }

  Future<void> ensureNoPending() async {
    if (read == null || _injectedCommands != null) await _findPending();
    if (_pendingContact != null) throw StateError(t('pendingContact'));
  }

  Future<void> load({bool acceptSavedContact = false}) async {
    final generation = ++_generation;
    try {
      final loaded = await loadSnapshot?.call();
      final history = loaded == null
          ? await _read('get_order_history', {'order_id': orderId})
          : {
              'code': 200,
              'data': {'order': loaded['order']},
            };
      if (history['code'] != 200 ||
          history['data']['order']['occasion'] != occasionId) {
        throw StateError('order unavailable');
      }
      final summary =
          loaded?['emailSummary'] ??
          await _read('get_order_email_summary', {'p_order': orderId});
      if (!_sameContext || generation != _generation) return;
      _update(() {
        acceptSnapshot(
          Map<String, dynamic>.from(history['data']['order']),
          Map<String, dynamic>.from(summary),
          acceptSavedContact: acceptSavedContact,
        );
      });
      if (read == null || _injectedCommands != null) {
        try {
          await _findPending();
        } catch (_) {
          /* Storage failure does not invalidate a successful read. */
        }
      }
    } catch (_) {
      if (!_sameContext || generation != _generation) return;
      _update(() {
        _loading = false;
        _stale = true;
        _feedback = t('unavailable');
      });
    }
  }

  Future<void> _findPending() async {
    final commands = _commands;
    if (commands is! RecoverableOrderContactCommands) return;
    final epoch = _contextEpoch;
    final pending = await (commands as RecoverableOrderContactCommands)
        .pendingContact(orderId);
    if (_sameContext && epoch == _contextEpoch)
      _update(() => _pendingContact = pending);
  }

  Future<void> recover() async {
    final commands = _commands;
    final pending = _pendingContact;
    if (commands is! RecoverableOrderContactCommands ||
        pending == null ||
        _locked)
      return;
    try {
      await _execute(
        () => (commands as RecoverableOrderContactCommands).recoverContact(
          pending,
        ),
        committedEmail: jsonDecode(pending.requestJson)['p_email'] as String,
      );
    } catch (_) {
      /* The session reports recovery failure; intent remains durable. */
    }
  }

  // Reuse the bounded reporting reader: one newest row, exact receipt identity,
  // at most four reads over five seconds. Never fetch history bodies or resend.
  Future<String?> _sendOutcome(Map<String, dynamic> result) async {
    final data = result['data'];
    final intent = data is Map ? data['intent'] : null;
    final id = intent is Map ? intent['message_id'] : null;
    if (id is! String || result['code'] != 200) return null;
    try {
      for (final wait in [
        Duration.zero,
        const Duration(seconds: 1),
        const Duration(seconds: 2),
        const Duration(seconds: 2),
      ]) {
        if (!_sameContext) return null;
        if (wait != Duration.zero) await Future<void>.delayed(wait);
        if (!_sameContext) return null;
        final rows = await _read('get_email_delivery_page', {
          'p_occasion': occasionId,
          'p_order': orderId,
          'p_kind': _order!['state'] == 'ordered'
              ? 'order_confirmation'
              : 'order_tickets',
          'p_limit': 1,
        }).timeout(const Duration(seconds: 2));
        if (!_sameContext || rows is! List || rows.length != 1) return null;
        final row = rows.single;
        if (row is! Map || row['message_id'] != id) return null;
        final state = row['state'];
        if (state is! String) return null;
        if (!const {'pending', 'preparing', 'sending'}.contains(state)) {
          return state;
        }
      }
    } catch (_) {
      // A reporting failure cannot undo a confirmed enqueue or trigger a retry.
    }
    return null;
  }

  String? _sentFeedback(String? outcome) =>
      const {'accepted', 'delivery', 'open', 'click'}.contains(outcome)
      ? null
      : outcome == null
      ? t('queued')
      : EmailDeliveryStrings.state(outcome);

  Future<void> save({required bool resend, OrderEmailIssue? issue}) async {
    if (_busy ||
        _stale ||
        _pendingContact != null ||
        _order == null ||
        !_sameContext ||
        !validEmail) {
      throw StateError(t('unavailable'));
    }
    final order = _order!;
    final value = _email.text.trim();
    await _execute(
      () => _commands.repairEmail(
        orderId: orderId,
        expectedEmail: order['data']['email'] ?? '',
        expectedState: order['state'],
        expectedPaymentFingerprint:
            order['email_payment_fingerprint'] as String,
        expectedPaymentVersion: (order['email_payment_version'] as num).toInt(),
        email: value,
        sourceMessageId: issue?.messageId,
        resend: resend,
      ),
      committedEmail: value,
      resend: resend,
    );
  }

  Future<void> _execute(
    Future<Map<String, dynamic>> Function() command, {
    required String committedEmail,
    bool? resend,
  }) async {
    final epoch = _contextEpoch;
    bool current() => _sameContext && epoch == _contextEpoch;
    _update(() {
      _busy = true;
      _feedback = null;
    });
    try {
      final result = await command();
      if (!current()) return;
      if (result['code'] == 200) _confirmEmail(committedEmail);
      final sending = resend ?? result['data']?['sendingRequested'] == true;
      final outcome = sending ? await _sendOutcome(result) : null;
      if (!current()) return;
      var refreshed = true;
      try {
        await onChanged?.call();
      } catch (_) {
        refreshed = false;
      }
      if (!current()) return;
      await load(acceptSavedContact: result['code'] == 200);
      if (!current()) return;
      _update(
        () =>
            _feedback = sending && result['code'] == 200 && refreshed && !_stale
            ? _sentFeedback(outcome)
            : t(
                result['code'] == 409
                    ? 'conflict'
                    : !refreshed || _stale
                    ? 'stale'
                    : 'saved',
              ),
      );
      OrderEmailIssue.changes.value++;
      if (result['code'] != 200 || !refreshed || _stale) {
        throw StateError(_feedback ?? t('failed'));
      }
    } catch (error) {
      try {
        await _findPending();
      } catch (_) {
        /* Original intent remains retained. */
      }
      if (current() && _feedback == null)
        _update(
          () => _feedback = t(
            error is PostgrestException &&
                    error.message.contains('email_recipient_suppressed')
                ? 'blocked'
                : 'failed',
          ),
        );
      rethrow;
    } finally {
      if (!_disposed) _update(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    RightsService.occasionLinkModelNotifier.removeListener(_contextChanged);
    _email.dispose();
    super.dispose();
  }
}
