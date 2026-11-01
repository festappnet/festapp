import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/widgets/app_dialog.dart';

import 'seating_transition_controller.dart';
import 'seating_transition_models.dart';
import 'seating_transition_strings.dart';

String _t(String key) => SeatingTransitionStrings.text(key);

class SeatingTransitionSummary extends StatelessWidget {
  const SeatingTransitionSummary({
    super.key,
    required this.controller,
    required this.open,
    this.onWaitlist,
  });
  final SeatingTransitionController controller;
  final VoidCallback open;
  final VoidCallback? onWaitlist;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final data = controller.context;
      if (controller.workspace == null && controller.error == null)
        return const SizedBox.shrink();
      if (data?.state == 'published' ||
          controller.workspace?['status'] == 'published')
        return const SizedBox.shrink();
      final message = data == null
          ? 'chooseForm'
          : data.admitted == 0
          ? 'noAdmissions'
          : data.allAssigned
          ? 'allAssigned'
          : 'workRemaining';
      return Container(
        key: const ValueKey('seating-summary'),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        child: Wrap(
          spacing: 16,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(_t(message)),
            if (data != null) ...[
              Text('${_t('unassigned')}: ${data.counts['unassigned'] ?? 0}'),
              if ((data.counts['blocked'] ?? 0) > 0)
                Text('${_t('blocked')}: ${data.counts['blocked']}'),
              if ((data.counts['waiting'] ?? 0) +
                      (data.counts['offered'] ?? 0) >
                  0)
                TextButton(
                  onPressed: onWaitlist,
                  child: Text(
                    '${_t('waiting')}: ${data.counts['waiting'] ?? 0} · ${_t('offered')}: ${data.counts['offered'] ?? 0}',
                  ),
                ),
            ],
            OutlinedButton(
              onPressed: controller.committing ? null : open,
              child: Text(_t('open')),
            ),
          ],
        ),
      );
    },
  );
}

class SeatingTransitionPanel extends StatefulWidget {
  const SeatingTransitionPanel({
    super.key,
    required this.controller,
    required this.onClose,
    this.onWaitlist,
    this.onCommitted,
  });
  final SeatingTransitionController controller;
  final VoidCallback onClose;
  final VoidCallback? onWaitlist;
  final Future<void> Function()? onCommitted;
  @override
  State<SeatingTransitionPanel> createState() => _SeatingTransitionPanelState();
}

class _SeatingTransitionPanelState extends State<SeatingTransitionPanel> {
  SeatingTransitionController get c => widget.controller;
  late final _search = TextEditingController(text: c.search);
  final _scroll = ScrollController();
  int? _lastSelected;
  int _lastPairCount = 0;
  @override
  void initState() {
    super.initState();
    c.addListener(_focusPairing);
  }

  void _focusPairing() {
    final selected = c.selected?.itemId;
    final focus =
        (selected != null && selected != _lastSelected) ||
        c.pairs.length > _lastPairCount;
    _lastSelected = selected;
    _lastPairCount = c.pairs.length;
    if (!focus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
    });
  }

  @override
  void dispose() {
    c.removeListener(_focusPairing);
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _review({bool publication = false}) async {
    final preview = await c.preview(publication: publication);
    if (!mounted || preview == null) return;
    final pairs = List<SeatingMapping>.of(c.pairs.values);
    var submitting = false;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => PopScope(
          canPop: !submitting,
          child: AppAlertDialog(
            dismissible: !submitting,
            onClose: () {
              if (!submitting) Navigator.pop(dialogContext);
            },
            title: Text(_t(publication ? 'publicationTitle' : 'reviewTitle')),
            content: SizedBox(
              width: 580,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _t(publication ? 'publicationExplanation' : 'unchanged'),
                    ),
                    const SizedBox(height: 16),
                    if (publication) ...[
                      for (final form in preview.forms)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                form['title']?.toString() ??
                                    '${_t('form')} #${form['id']}',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              Text(
                                '${_t('oldCapacity')}: ${form['participantCapacity'] ?? _t('unlimited')}',
                              ),
                              Text(
                                '${_t('newCapacity')}: ${form['capacity'] ?? '-'} · ${_t('available')}: ${form['available'] ?? '-'}',
                              ),
                            ],
                          ),
                        ),
                      for (final product in preview.catalog)
                        Text(
                          '${product['title'] ?? product['productTitle'] ?? product['productId']} · ${_t('available')}: ${product['available'] ?? '-'}',
                        ),
                    ] else
                      for (final pair in pairs)
                        _pairRow(pair, removable: false),
                    for (final blocker in preview.blockers)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          _blocker(blocker),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    if (submitting) ...[
                      const SizedBox(height: 16),
                      const LinearProgressIndicator(),
                      Text(_t('committing')),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: submitting
                    ? null
                    : () => Navigator.pop(dialogContext),
                child: Text(CommonStrings.cancel),
              ),
              FilledButton(
                onPressed: submitting || !preview.ready
                    ? null
                    : () async {
                        setDialogState(() => submitting = true);
                        final saved = await c.commit(
                          preview,
                          publication: publication,
                        );
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                        if (saved) await widget.onCommitted?.call();
                      },
                child: Text(_t(publication ? 'confirmPublish' : 'confirm')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _blocker(Map<String, dynamic> blocker) => [
    if (blocker['ticketId'] != null) '${_t('ticket')} #${blocker['ticketId']}',
    if (blocker['spotId'] != null)
      '${_t('seat')} ${c.seatTitle((blocker['spotId'] as num).toInt())}',
    if (blocker['formId'] != null) '${_t('form')} #${blocker['formId']}',
    SeatingTransitionStrings.reason(blocker['reason']?.toString() ?? 'UNKNOWN'),
  ].join(' · ');

  Widget _pairRow(SeatingMapping pair, {bool removable = true}) {
    final item = c.pairAdmissions[pair.admissionItemId];
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(item?.label ?? '${_t('ticket')} #${pair.ticketId}'),
      subtitle: Text(
        '${_t('form')} #${item?.formId ?? '-'} · ${_t('order')} #${item?.orderSymbol ?? '-'}\n${item?.productTitle ?? ''}\n${pair.expectedSpotId == null ? _t('unseated') : c.seatTitle(pair.expectedSpotId)} → ${pair.targetSpotId == null ? _t('unseated') : c.seatTitle(pair.targetSpotId)}',
      ),
      trailing: removable
          ? IconButton(
              tooltip: _t('removePair'),
              onPressed: c.busy || c.uncertain
                  ? null
                  : () => c.remove(pair.admissionItemId),
              icon: const Icon(Icons.close),
            )
          : null,
    );
  }

  Future<void> _cancelConfiguration() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AppAlertDialog(
        onClose: () => Navigator.pop(context, false),
        title: Text(_t('cancelConfiguration')),
        content: Text(_t('cancelExplanation')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(CommonStrings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(_t('cancelConfiguration')),
          ),
        ],
      ),
    );
    if (confirmed == true) await c.cancelConfiguration();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    builder: (context, _) {
      final data = c.context;
      final configure = SeatingCapabilities(
        seatingMap(c.workspace?['capabilities'] ?? const {}),
      ).configure;
      return ListView(
        key: const ValueKey('seating-worklist'),
        controller: _scroll,
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _t('title'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: _t('close'),
                onPressed: c.committing ? null : widget.onClose,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          if (c.busy) ...[
            const LinearProgressIndicator(),
            Text(
              _t(
                c.recovering
                    ? 'recovering'
                    : c.committing
                    ? 'committing'
                    : 'loading',
              ),
            ),
          ],
          if (c.error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                SeatingTransitionStrings.reason(c.error!),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (c.uncertain)
            FilledButton(
              onPressed: c.committing ? null : c.recover,
              child: Text(_t('recover')),
            )
          else
            TextButton.icon(
              onPressed: c.busy ? null : () => c.load(discover: true),
              icon: const Icon(Icons.refresh),
              label: Text(_t('refresh')),
            ),
          if (c.notice != null) Text(_t(c.notice!)),
          if (data == null)
            Text(
              _t(
                c.workspace?['status'] == 'published'
                    ? 'published'
                    : c.workspace?['status'] == 'no_source'
                    ? 'no_source'
                    : c.workspace?['status'] == 'repair_plan'
                    ? 'repairPlan'
                    : configure
                    ? 'chooseForm'
                    : 'configureRequired',
              ),
            ),
          if (configure &&
              !c.uncertain &&
              data?.state != 'published' &&
              c.workspace?['status'] != 'published') ...[
            for (final form in seatingRows(
              c.workspace?['forms'],
            ).where((f) => f['transitionId'] == null))
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  form['title'] as String? ?? '${_t('form')} #${form['id']}',
                ),
                subtitle: form['reason'] == null
                    ? null
                    : Text(
                        SeatingTransitionStrings.reason(
                          form['reason'].toString(),
                        ),
                      ),
                trailing: form['canStart'] != true
                    ? null
                    : TextButton(
                        onPressed: c.busy
                            ? null
                            : () => c.start(seatingInt(form['id'])),
                        child: Text(_t('start')),
                      ),
              ),
          ],
          if (data != null) ...[
            if (c.requestedUnit.isNotEmpty)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${_t('unit')}: ${c.requestedUnit.length}'),
                subtitle: Text(c.requestedUnit.map(c.seatTitle).join(', ')),
                trailing: IconButton(
                  tooltip: CommonStrings.cancel,
                  onPressed: c.busy || c.uncertain ? null : c.clearUnitRequest,
                  icon: const Icon(Icons.close),
                ),
              ),

            if (data.state == 'published') Text(_t('published')),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final key in const [
                  'unassigned',
                  'assigned',
                  'standing',
                  'blocked',
                  'waiting',
                  'offered',
                ])
                  ChoiceChip(
                    label: Text('${_t(key)} ${data.counts[key] ?? 0}'),
                    selected: c.category == key,
                    onSelected: c.busy || c.uncertain
                        ? null
                        : (_) => c.filter(kind: key),
                  ),
              ],
            ),
            if (data.state == 'organizer_managed' &&
                data.allAssigned &&
                data.admitted > 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(_t('allAssigned')),
              ),
            if (widget.onWaitlist != null &&
                (data.counts['waiting'] ?? 0) + (data.counts['offered'] ?? 0) >
                    0)
              TextButton(
                onPressed: widget.onWaitlist,
                child: Text(_t('waiting')),
              ),
            if (c.selected != null && c.canAssign) ...[
              const Divider(),
              Text(
                c.selected!.label,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(_t('compatibleSeats')),
              if (c.compatible.isEmpty) Text(_t('noSeats')),
              for (final seat in c.compatible)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(seat.title),
                  subtitle: seat.unitSpotIds.length > 1
                      ? Text('${_t('unit')}: ${seat.unitSpotIds.length}')
                      : null,
                  onTap: c.busy || c.uncertain ? null : () => c.pair(seat.id),
                ),
              if (c.selected!.spotId != null)
                TextButton(
                  onPressed: c.busy || c.uncertain ? null : () => c.pair(null),
                  child: Text(_t('release')),
                ),
            ],
            if (c.pairs.isNotEmpty) ...[
              const Divider(),
              Text(_t('draft'), style: Theme.of(context).textTheme.titleMedium),
              for (final pair in c.pairs.values) _pairRow(pair),
              FilledButton(
                onPressed: c.busy || c.uncertain || !c.canAssign
                    ? null
                    : _review,
                child: Text(_t('review')),
              ),
            ],
            if (!data.capabilities.readHolders)
              Text(_t('readRequired'))
            else ...[
              const SizedBox(height: 12),
              TextField(
                controller: _search,
                maxLength: 256,
                enabled: !c.busy && !c.uncertain,
                decoration: InputDecoration(
                  labelText: _t('search'),
                  suffixIcon: IconButton(
                    tooltip: _t('search'),
                    onPressed: c.busy || c.uncertain
                        ? null
                        : () => c.filter(query: _search.text),
                    icon: const Icon(Icons.search),
                  ),
                ),
                onSubmitted: (value) => c.filter(query: value),
              ),
              if (!c.canAssign)
                Text(_t('assignRequired'))
              else
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(_t('selectAdmission')),
                ),
              if (data.items.isEmpty && !c.loading)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    _t(
                      data.admitted == 0 && c.search.isEmpty
                          ? 'noAdmissions'
                          : 'noResults',
                    ),
                  ),
                ),
              for (final item in data.items)
                ListTile(
                  key: ValueKey('admission-${item.ticketId}'),
                  contentPadding: EdgeInsets.zero,
                  selected: c.selected?.itemId == item.itemId,
                  title: Text(item.label),
                  subtitle: Text(
                    '${_t('form')} #${item.formId} · ${_t('order')} #${item.orderSymbol}\n${item.productTitle}${item.spotId == null ? '' : ' · ${c.seatTitle(item.spotId)}'}${item.reason == null ? '' : '\n${SeatingTransitionStrings.reason(item.reason!)}'}',
                  ),
                  leading: c.pairs.containsKey(item.itemId)
                      ? const Icon(Icons.pending_actions)
                      : null,
                  onTap: c.canAssign && item.mutable && !c.busy && !c.uncertain
                      ? () => c.select(item)
                      : null,
                ),
              Wrap(
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: c.hasPrevious && !c.busy && !c.uncertain
                        ? c.previous
                        : null,
                    child: Text(_t('previous')),
                  ),
                  TextButton(
                    onPressed:
                        data.nextCursor != null && !c.busy && !c.uncertain
                        ? c.next
                        : null,
                    child: Text(_t('next')),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(_t('compatibility')),
              initiallyExpanded: true,
              children: [
                for (final product in data.compatibility)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      product['productTitle']?.toString() ??
                          '#${product['productId']}',
                    ),
                    subtitle: Text(
                      '${_t('admissions')}: ${product['admissions']} · ${_t('seats')}: ${product['seats']} · ${_t('standing')}: ${product['standing'] == true ? _t('standing') : '-'}${product['reason'] == null ? '' : '\n${SeatingTransitionStrings.reason(product['reason'].toString())}'}',
                    ),
                  ),
              ],
            ),
            if (data.capabilities.configure &&
                data.publicationAvailable &&
                data.state == 'organizer_managed') ...[
              const Divider(),
              OutlinedButton(
                onPressed: c.busy || c.uncertain
                    ? null
                    : () => _review(publication: true),
                child: Text(_t('publish')),
              ),
              if ((data.counts['assigned'] ?? 0) == 0)
                TextButton(
                  onPressed: c.busy || c.uncertain
                      ? null
                      : _cancelConfiguration,
                  child: Text(_t('cancelConfiguration')),
                ),
            ],
          ],
        ],
      );
    },
  );
}

/// Seating is a worklist task at every width. Do not hide its queue behind the
/// geometry editor's mobile library button or a modal above the selectable map.
class SeatingWorkspaceFrame extends StatelessWidget {
  const SeatingWorkspaceFrame({
    super.key,
    required this.active,
    required this.child,
    this.panel,
  });
  final bool active;
  final Widget child;
  final Widget? panel;
  @override
  Widget build(BuildContext context) {
    if (!active || panel == null) return child;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 900) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 340, child: panel),
              const VerticalDivider(width: 1),
              Expanded(child: child),
            ],
          );
        }
        return Column(
          children: [
            SizedBox(
              height: (constraints.maxHeight * .35).clamp(80.0, 240.0),
              child: child,
            ),
            const Divider(height: 1),
            Expanded(child: panel!),
          ],
        );
      },
    );
  }
}

/// Both entry and publication require a saved plan. Closing keeps the draft;
/// neither branch performs a seating command or releases a placement.
Future<bool> confirmSeatingSavedPlan(
  BuildContext context, {
  required bool Function() isDirty,
  required Future<void> Function() save,
  required VoidCallback discard,
}) async {
  if (!isDirty()) return true;
  final choice = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AppAlertDialog(
      onClose: () => Navigator.pop(dialogContext),
      title: Text(_t('saveDraft')),
      content: Text(_t('saveDraftDetail')),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(CommonStrings.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, 'discard'),
          child: Text(CommonStrings.discardChanges),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, 'save'),
          child: Text(CommonStrings.save),
        ),
      ],
    ),
  );
  if (choice == null || !context.mounted) return false;
  if (choice == 'save') {
    await save();
  } else {
    discard();
  }
  return !isDirty();
}
