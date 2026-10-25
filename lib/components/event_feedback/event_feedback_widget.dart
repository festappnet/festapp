import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/event_feedback/db_event_feedback.dart';
import 'package:fstapp/components/event_feedback/event_feedback_model.dart';
import 'package:fstapp/components/event_feedback/event_feedback_results.dart';
import 'package:fstapp/components/event_feedback/event_feedback_strings.dart';
import 'package:fstapp/components/offline/offline_strings.dart';
import 'package:fstapp/data_services/offline_data_service.dart';
import 'package:fstapp/services/connectivity_service.dart';
import 'package:fstapp/services/exception_handler.dart';
import 'package:fstapp/services/toast_helper.dart';

/// Smiley rating + optional comment shown on the event detail page when the
/// EventFeedback feature is enabled for the occasion and the event.
///
/// [isOpen] = feedback window is open (now >= event start). When closed and the
/// viewer is an editor, [isEditorPreview] shows the UI as a preview.
///
/// Uses an outlined rounded
/// container (not a Card), three equal-width colour-coded smiley tiles laid out
/// by a LayoutBuilder, and icon buttons for submit/remove.
class EventFeedbackWidget extends StatefulWidget {
  final int eventId;
  final bool isOpen;
  final bool isEditorPreview;

  /// The event caps participants (max_participants > 0), so only signed-in
  /// participants may rate it. Mirrors production `T7(event)`.
  final bool requiresSignIn;

  /// The current viewer is a signed-in participant of this event
  /// (event.isSignedIn == true). Mirrors production `event.ay`.
  final bool isParticipant;

  /// Test seam: overrides the initial feedback fetch. Defaults to the live RPC.
  @visibleForTesting
  final Future<EventFeedbackModel?> Function(int eventId)? loadFeedbackOverride;

  /// Test seam for the synchronous offline fast path.
  @visibleForTesting
  final Future<bool> Function()? isOfflineOverride;

  @visibleForTesting
  final Future<Map<String, dynamic>?> Function(int eventId)?
      loadCachedFeedbackOverride;

  /// Matches the cache read seam without requiring platform storage in UI tests.
  @visibleForTesting
  final Future<void> Function(int eventId, Map<String, dynamic>? feedback)?
      saveCachedFeedbackOverride;

  /// Keeps a stale connectivity signal or a wedged request from leaving the
  /// feedback section in an endless loading state.
  final Duration loadTimeout;

  const EventFeedbackWidget({
    super.key,
    required this.eventId,
    required this.isOpen,
    this.isEditorPreview = false,
    this.requiresSignIn = false,
    this.isParticipant = false,
    this.loadFeedbackOverride,
    this.isOfflineOverride,
    this.loadCachedFeedbackOverride,
    this.saveCachedFeedbackOverride,
    this.loadTimeout = const Duration(seconds: 12),
  });

  @override
  State<EventFeedbackWidget> createState() => _EventFeedbackWidgetState();
}

class _EventFeedbackWidgetState extends State<EventFeedbackWidget> {
  final TextEditingController _note = TextEditingController();
  String? _rating;
  bool _loading = true;
  bool _saving = false;

  /// True once the user has edited the comment since the last save/load.
  /// Drives the "Uložit komentář" (saveComment) submit label, matching prod.
  bool _commentDirty = false;
  EventFeedbackModel? _existing;

  /// Offline with no cached feedback record: the submitted state is genuinely
  /// unknown — show a notice instead of pretending "not sent yet".
  bool _stateUnknownOffline = false;

  static const _ratings = [
    EventFeedbackModel.ratingHappy,
    EventFeedbackModel.ratingNeutral,
    EventFeedbackModel.ratingSad,
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final knownOffline = widget.isOfflineOverride != null
        ? await widget.isOfflineOverride!()
        : ConnectivityService.isOfflineNotifier.value;
    if (knownOffline) {
      await _loadCachedOrUnknownOffline();
      return;
    }
    try {
      final load = widget.loadFeedbackOverride ?? DbEventFeedback.getMyFeedback;
      final fb = await load(widget.eventId).timeout(widget.loadTimeout);
      // Keep the offline "already sent" cache in sync with the live answer
      // (null clears a stale entry after a deletion elsewhere). Fire-and-
      // forget: a cache write must never block or break the UI.
      unawaited((widget.saveCachedFeedbackOverride ??
                  OfflineDataService.saveMyEventFeedback)(
              widget.eventId, fb?.toJson())
          .catchError((_) {}));
      if (!mounted) return;
      setState(() {
        _existing = fb;
        _rating = fb?.rating;
        _note.text = fb?.note ?? '';
        _commentDirty = false;
        _stateUnknownOffline = false;
        _loading = false;
      });
    } catch (e) {
      // Live fetch failed: a cached record still shows the honest "sent"
      // state; with no cache while offline the state is unknown — never lie
      // with an empty form.
      final cached = await (widget.loadCachedFeedbackOverride ??
          OfflineDataService.getMyEventFeedback)(widget.eventId);
      if (!mounted) return;
      if (cached != null) {
        final fb = EventFeedbackModel.fromJson(cached);
        setState(() {
          _existing = fb;
          _rating = fb.rating;
          _note.text = fb.note ?? '';
          _commentDirty = false;
          _loading = false;
        });
        return;
      }
      // Weak signal / timeout / server outage counts as offline too, not just a
      // missing interface — so a failed load with no cache shows the "unknown"
      // notice rather than a misleading empty form.
      final offline = e is TimeoutException ||
          ExceptionHandler.isNetworkError(e) ||
          await ConnectivityService.isOffline();
      if (!mounted) return;
      setState(() {
        _stateUnknownOffline = offline;
        _loading = false;
      });
    }
  }

  Future<void> _loadCachedOrUnknownOffline() async {
    final cached = await (widget.loadCachedFeedbackOverride ??
        OfflineDataService.getMyEventFeedback)(widget.eventId);
    if (!mounted) return;
    final fb = cached == null ? null : EventFeedbackModel.fromJson(cached);
    setState(() {
      _existing = fb;
      _rating = fb?.rating;
      _note.text = fb?.note ?? '';
      _commentDirty = false;
      _stateUnknownOffline = fb == null;
      _loading = false;
    });
  }

  Future<void> _submit() async {
    if (_rating == null) {
      ToastHelper.Show(context, EventFeedbackStrings.chooseRatingFirst);
      return;
    }
    setState(() => _saving = true);
    try {
      final fb = await DbEventFeedback.submit(
        eventId: widget.eventId,
        rating: _rating!,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      );
      // Fire-and-forget cache write — never fail a successful submit.
      unawaited(
          OfflineDataService.saveMyEventFeedback(widget.eventId, fb.toJson())
              .catchError((_) {}));
      if (!mounted) return;
      setState(() {
        _existing = fb;
        _commentDirty = false;
        _saving = false;
      });
      ToastHelper.Show(context, EventFeedbackStrings.feedbackSavedThankYou);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ToastHelper.Show(context, _errorMessage(e));
    }
  }

  /// Maps the RPC error code to its message exactly like the deployed build.
  String _errorMessage(Object e) {
    if (e is EventFeedbackException) {
      switch (e.code) {
        case 401:
          return EventFeedbackStrings.signInRequired;
        case 403:
          return EventFeedbackStrings.onlySignedInParticipants;
        case 409:
          return EventFeedbackStrings.feedbackOpensWhenEventStarts;
        case 413:
          return EventFeedbackStrings.feedbackTextTooLong;
        default:
          return e.message ?? EventFeedbackStrings.feedbackCouldNotBeSaved;
      }
    }
    // Offline gets the unified readable message instead of the generic one.
    if (ExceptionHandler.isNetworkError(e)) {
      return OfflineStrings.writeRequiresConnection;
    }
    return EventFeedbackStrings.feedbackCouldNotBeSaved;
  }

  Future<void> _remove() async {
    setState(() => _saving = true);
    try {
      await DbEventFeedback.delete(widget.eventId);
      // Fire-and-forget cache removal — never fail a successful delete.
      unawaited(OfflineDataService.saveMyEventFeedback(widget.eventId, null)
          .catchError((_) {}));
      if (!mounted) return;
      setState(() {
        _existing = null;
        _rating = null;
        _note.clear();
        _commentDirty = false;
        _saving = false;
      });
      ToastHelper.Show(context, EventFeedbackStrings.feedbackRemoved);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ToastHelper.Show(context, _errorMessage(e),
          severity: ToastSeverity.NotOk);
    }
  }

  /// Semantic accent colour for a rating (happy = green, neutral = amber,
  /// sad = red), with light/dark variants. Sad matches the deployed build
  /// exactly (0xFFD32F2F / 0xFFFF5252).
  Color _ratingColor(String rating, bool dark) {
    switch (rating) {
      case EventFeedbackModel.ratingHappy:
        return dark ? const Color(0xFF66BB6A) : const Color(0xFF388E3C);
      case EventFeedbackModel.ratingNeutral:
        return dark ? const Color(0xFFFFCA28) : const Color(0xFFF9A825);
      case EventFeedbackModel.ratingSad:
      default:
        return dark ? const Color(0xFFFF5252) : const Color(0xFFD32F2F);
    }
  }

  IconData _ratingIcon(String rating) {
    switch (rating) {
      case EventFeedbackModel.ratingHappy:
        return Icons.sentiment_very_satisfied;
      case EventFeedbackModel.ratingSad:
        return Icons.sentiment_very_dissatisfied;
      case EventFeedbackModel.ratingNeutral:
      default:
        return Icons.sentiment_neutral;
    }
  }

  /// One equal-width smiley tile: rounded outlined card with an icon over its
  /// label. Unselected tiles are neutral grey; the selected tile lights up in
  /// its semantic colour with a tinted fill and a 2px border.
  Widget _smileyTile(BuildContext context, String rating, double width) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final selected = _rating == rating;
    final accent = _ratingColor(rating, dark);
    final fg = selected ? accent : (dark ? Colors.white54 : Colors.black54);

    return SizedBox(
      width: width,
      child: Material(
        color: selected ? accent.withValues(alpha: 0.14) : Colors.transparent,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: selected
                ? accent
                : theme.colorScheme.outline.withValues(alpha: 0.4),
            width: selected ? 2 : 1,
          ),
        ),
        child: InkWell(
          onTap: _saving ? null : () => setState(() => _rating = rating),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_ratingIcon(rating), size: 30, color: fg),
                const SizedBox(height: 4),
                Text(
                  EventFeedbackStrings.ratingLabel(rating),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(color: fg),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _form(BuildContext context) {
    final submitLabel = _commentDirty
        ? EventFeedbackStrings.saveComment
        : (_existing == null
            ? EventFeedbackStrings.sendFeedback
            : EventFeedbackStrings.updateFeedback);
    final showRemove =
        _existing != null || _rating != null || _note.text.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (ctx, constraints) {
            // Two 8px gaps between three tiles.
            final width = (constraints.maxWidth - 16) / 3;
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children:
                  _ratings.map((r) => _smileyTile(ctx, r, width)).toList(),
            );
          },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _note,
          maxLength: 2000,
          minLines: 2,
          maxLines: 4,
          onChanged: (_) {
            if (!_commentDirty) setState(() => _commentDirty = true);
          },
          decoration: InputDecoration(
            labelText: EventFeedbackStrings.optionalComment,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (showRemove)
              TextButton.icon(
                onPressed: _saving ? null : _remove,
                icon: const Icon(Icons.delete_outline),
                label: Text(EventFeedbackStrings.removeFeedback),
              ),
            FilledButton.icon(
              onPressed: (_saving || _rating == null) ? null : _submit,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
              label: Text(submitLabel),
            ),
          ],
        ),
      ],
    );
  }

  /// Icon + text status row (feedback closed / participants-only), matching the
  /// deployed build's inline message layout.
  Widget _messageRow(BuildContext context, IconData icon, String text) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: theme.hintColor),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final closed = !widget.isOpen && !widget.isEditorPreview;
    // Capped events only take feedback from signed-in participants; editors
    // preview regardless. Mirrors production T7(event) && !editor && !event.ay.
    final participantsOnly = widget.requiresSignIn &&
        !widget.isEditorPreview &&
        !widget.isParticipant;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Container(
        decoration: BoxDecoration(
          // Neutral grey background, independent of the theme's (brownish)
          // surface colour, so the feedback card reads calmly on the event page.
          color: theme.brightness == Brightness.dark
              ? const Color(0xFF2A2A2C)
              : const Color(0xFFF2F2F2),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.5)),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(EventFeedbackStrings.howWasThisEvent,
                style: theme.textTheme.titleMedium),
            if (widget.isEditorPreview && !widget.isOpen)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(EventFeedbackStrings.editorPreviewBeforeStart,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(fontStyle: FontStyle.italic)),
              ),
            const SizedBox(height: 12),
            if (closed)
              _messageRow(context, Icons.schedule,
                  EventFeedbackStrings.feedbackOpensWhenEventStarts)
            else if (participantsOnly)
              _messageRow(context, Icons.lock_outline,
                  EventFeedbackStrings.onlySignedInParticipants)
            else if (_stateUnknownOffline)
              _messageRow(
                  context, Icons.cloud_off, OfflineStrings.feedbackStateUnknown)
            else
              _form(context),
            // Editors see the aggregated results inline (matches production).
            if (widget.isEditorPreview) ...[
              const SizedBox(height: 12),
              EventFeedbackResults(eventId: widget.eventId),
            ],
          ],
        ),
      ),
    );
  }
}
