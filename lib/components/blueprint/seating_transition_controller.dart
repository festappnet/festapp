import 'package:flutter/foundation.dart';

import 'seating_transition_models.dart';
import 'seating_transition_transport.dart';

class SeatingTransitionController extends ChangeNotifier {
  SeatingTransitionController({
    required this.transport,
    required this.occasionId,
    required this.blueprintId,
  });
  final SeatingTransitionTransport transport;
  final int occasionId, blueprintId;
  Map<String, dynamic>? workspace;
  SeatingContext? context;
  String search = '', category = 'unassigned';
  int? after;
  final List<int?> _pages = [];
  final Map<int, SeatingMapping> pairs = {};
  final Map<int, SeatingAdmission> pairAdmissions = {};
  SeatingAdmission? selected;
  Set<int> requestedUnit = {};
  Set<int> get selectableSpotIds => !canAssign || busy || uncertain
      ? {}
      : selected != null
      ? compatible.map((s) => s.id).toSet()
      : {
          for (final seat in context?.seats ?? <SeatingSeat>[])
            if (seat.available) seat.id,
        };
  void clearUnitRequest() {
    if (busy || uncertain) return;
    requestedUnit = {};
    _notify();
  }

  bool loading = false, committing = false, recovering = false;
  String? error, notice;
  String? _pendingOperation, _pendingPrincipal;
  Map<String, dynamic>? _pendingParameters;
  int _generation = 0;
  bool _disposed = false;
  bool get busy => loading || committing || recovering;
  bool get uncertain => _pendingOperation != null || recovering;
  bool get canAssign =>
      context?.capabilities.assign == true &&
      context?.capabilities.readHolders == true;
  List<SeatingSeat> get compatible => selected == null
      ? []
      : context!.seats
            .where(
              (s) =>
                  (requestedUnit.isEmpty || requestedUnit.contains(s.id)) &&
                  s.productId == selected!.productId &&
                  s.available &&
                  !pairs.values.any(
                    (p) =>
                        p.targetSpotId == s.id &&
                        p.admissionItemId != selected!.itemId,
                  ),
            )
            .toList();
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }

  Future<void> load({bool discover = false}) async {
    if (committing) return;
    final generation = ++_generation;
    loading = true;
    error = null;
    _notify();
    try {
      if (discover || workspace == null)
        workspace = await transport.workspace(occasionId, blueprintId);
      if (discover) {
        recovering = true;
        _notify();
        var changed = false;
        for (final form in seatingRows(workspace!['forms'])) {
          try {
            changed =
                await transport.recoverStart(
                  seatingInt(form['id']),
                  blueprintId,
                ) ||
                changed;
          } on SeatingRejection catch (e) {
            error = e.reason;
          }
        }
        if (changed)
          workspace = await transport.workspace(occasionId, blueprintId);
        recovering = false;
      }
      final transitions = seatingRows(workspace!['transitions'])
          .where(
            (t) => t['blueprintId'] == blueprintId && t['state'] != 'cancelled',
          )
          .toList();
      if (transitions.isNotEmpty) {
        final id = transitions.first['id'] as String;
        if (discover) {
          recovering = true;
          _notify();
          try {
            await transport.recover(id);
          } on SeatingRejection catch (e) {
            error = e.reason;
          }
          recovering = false;
        }
        final updated = await transport.context(
          id,
          search: search,
          category: category,
          after: after,
        );
        if (generation != _generation || _disposed) return;
        if (context != null && updated.admitted > context!.admitted)
          notice = 'changed';
        context = updated;
        if (!updated.capabilities.readHolders) {
          pairs.clear();
          pairAdmissions.clear();
          selected = null;
        }
        if (selected != null)
          selected = updated.items
              .where((i) => i.itemId == selected!.itemId)
              .firstOrNull;
      } else {
        context = null;
      }
    } on SeatingRejection catch (e) {
      error = e.reason;
      if (e.reason == 'FORBIDDEN') {
        context = null;
        pairs.clear();
        pairAdmissions.clear();
        selected = null;
      }
    } catch (_) {
      error = recovering ? 'recoveryFailed' : 'UNAVAILABLE';
    } finally {
      if (generation == _generation) {
        loading = false;
        _notify();
      }
    }
  }

  void invalidateIdentity() {
    _generation++;
    requestedUnit = {};
    context = null;
    workspace = null;
    pairs.clear();
    pairAdmissions.clear();
    selected = null;
    _notify();
  }

  Future<void> filter({String? query, String? kind}) async {
    if (busy || uncertain) return;
    search = query ?? search;
    category = kind ?? category;
    after = null;
    _pages.clear();
    selected = null;
    await load();
  }

  Future<void> next() async {
    if (context?.nextCursor == null || busy) return;
    _pages.add(after);
    after = context!.nextCursor;
    await load();
  }

  Future<void> previous() async {
    if (_pages.isEmpty || busy) return;
    after = _pages.removeLast();
    await load();
  }

  bool get hasPrevious => _pages.isNotEmpty;
  void select(SeatingAdmission item) {
    if (!canAssign || busy || uncertain || !item.mutable) return;
    selected = item;
    _notify();
  }

  void pair(int? spotId) {
    final item = selected;
    if (!canAssign || busy || uncertain) return;
    if (item == null) {
      final seat = context!.seats
          .where((s) => s.id == spotId && s.available)
          .firstOrNull;
      if (seat != null) {
        requestedUnit = seat.unitSpotIds.toSet();
        _notify();
      }
      return;
    }
    if (spotId != null && !compatible.any((s) => s.id == spotId)) return;
    if (spotId == item.spotId) {
      remove(item.itemId!);
      return;
    }
    pairs[item.itemId!] = SeatingMapping(
      ticketId: item.ticketId,
      admissionItemId: item.itemId!,
      expectedSpotId: item.spotId,
      targetSpotId: spotId,
    );
    pairAdmissions[item.itemId!] = item;
    final target = context!.seats.where((s) => s.id == spotId).firstOrNull;
    if (target != null && target.unitSpotIds.length > 1)
      requestedUnit = target.unitSpotIds.toSet();
    if (requestedUnit.every(
      (id) => pairs.values.any((p) => p.targetSpotId == id),
    ))
      requestedUnit = {};
    selected = null;
    error = null;
    _notify();
  }

  void remove(int itemId) {
    if (busy || uncertain) return;
    pairs.remove(itemId);
    pairAdmissions.remove(itemId);
    _notify();
  }

  String seatTitle(int? id) => id == null
      ? ''
      : context?.seats.where((s) => s.id == id).firstOrNull?.title ?? '#$id';
  Future<SeatingPreview?> preview({bool publication = false}) async {
    if (busy || uncertain || context == null) return null;
    loading = true;
    error = null;
    _notify();
    try {
      return publication
          ? await transport.previewPublication(context!.transitionId)
          : await transport.previewAssignments(
              context!.transitionId,
              pairs.values.toList(),
            );
    } on SeatingRejection catch (e) {
      error = e.reason;
    } catch (_) {
      error = 'UNAVAILABLE';
    } finally {
      loading = false;
      _notify();
    }
    return null;
  }

  Future<bool> commit(SeatingPreview preview, {bool publication = false}) =>
      _mutate(
        publication
            ? 'publish_seating_transitions'
            : 'set_ticket_seat_assignments',
        {
          'p_transition': context!.transitionId,
          'p_fingerprint': preview.fingerprint,
          if (publication)
            'p_transition_ids': preview.transitionIds
          else
            'p_mappings': pairs.values.map((p) => p.toJson()).toList(),
        },
      );
  Future<bool> start(int formId) => _mutate('start_seating_configuration', {
    'p_form': formId,
    'p_blueprint': blueprintId,
  });
  Future<bool> cancelConfiguration() =>
      _mutate('cancel_seating_configuration', {
        'p_transition': context!.transitionId,
        'p_expected_revision': context!.revision,
      });
  Future<bool> recover() async {
    if (committing) return false;
    if (_pendingOperation == null) {
      recovering = false;
      await load(discover: true);
      return !recovering;
    }
    return _mutate(_pendingOperation!, _pendingParameters!, replay: true);
  }

  Future<bool> _mutate(
    String operation,
    Map<String, dynamic> params, {
    bool replay = false,
  }) async {
    if (committing || (!replay && uncertain)) return false;
    if (replay && _pendingPrincipal != transport.principalBinding) {
      error = 'FORBIDDEN';
      _notify();
      return false;
    }
    _pendingPrincipal = transport.principalBinding;
    _pendingOperation = operation;
    _pendingParameters = params;
    committing = true;
    recovering = replay;
    error = null;
    _notify();
    var success = false;
    try {
      await transport.mutate(operation, params);
      _pendingOperation = null;
      _pendingParameters = null;
      if (operation == 'set_ticket_seat_assignments') {
        requestedUnit = {};
        pairs.clear();
        pairAdmissions.clear();
        selected = null;
      }
      notice = 'saved';
      success = true;
    } on SeatingRejection catch (e) {
      _pendingOperation = null;
      _pendingParameters = null;
      error = e.reason;
    } catch (_) {
      error = 'recoveryFailed';
    } finally {
      committing = false;
      recovering = _pendingOperation != null;
      _notify();
    }
    if (!uncertain) {
      final failure = error;
      await load(discover: true);
      if (failure != null) {
        error = failure;
        _notify();
      }
    }
    return success;
  }
}
