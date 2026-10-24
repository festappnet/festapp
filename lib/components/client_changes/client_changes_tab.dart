import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:fstapp/components/client_changes/client_change_model.dart';
import 'package:fstapp/components/client_changes/client_changes_strings.dart';
import 'package:fstapp/components/client_changes/db_client_changes.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/services/connectivity_service.dart';
import 'package:fstapp/services/exception_handler.dart';
import 'package:intl/intl.dart';

typedef ClientActivityLoader = Future<List<ClientActivityDay>> Function({
  required int occasionId,
  required DateTime from,
  required DateTime to,
});

class ClientChangesTab extends StatefulWidget {
  const ClientChangesTab({
    super.key,
    this.clientSyncEnabled,
    this.activityLoader,
    this.isOffline,
    this.occasionId,
  });

  final bool? clientSyncEnabled;
  final ClientActivityLoader? activityLoader;
  final Future<bool> Function()? isOffline;
  final int? occasionId;

  @override
  State<ClientChangesTab> createState() => _ClientChangesTabState();
}

class _ClientChangesTabState extends State<ClientChangesTab> {
  DbClientChanges? _repository;
  List<ClientActivityDay> _days = const [];
  late DateTime _from;
  late DateTime _to;
  int _loadEpoch = 0;
  int _rangeDays = 7;
  bool _error = false;
  bool _offline = false;
  bool _loading = false;

  bool get _clientSyncEnabled =>
      widget.clientSyncEnabled ??
      RightsService.occasionLinkModel?.clientSyncV1 ??
      false;

  @override
  void initState() {
    super.initState();
    final today = DateUtils.dateOnly(DateTime.now());
    _from = today.subtract(const Duration(days: 6));
    _to = today.add(const Duration(days: 1));
    if (_clientSyncEnabled) {
      if (widget.activityLoader == null) _repository = DbClientChanges();
      _load();
    }
  }

  Future<void> _load() async {
    final epoch = ++_loadEpoch;
    setState(() {
      _loading = true;
      _error = false;
      _offline = false;
    });
    final isOffline =
        await (widget.isOffline ?? ConnectivityService.isOffline)();
    if (!mounted || epoch != _loadEpoch) return;
    if (isOffline) {
      setState(() {
        _error = true;
        _offline = true;
        _loading = false;
      });
      return;
    }
    final result = await ExceptionHandler.guard(
      context,
      futureFunction: () => (widget.activityLoader ?? _repository!.activity)(
        occasionId: widget.occasionId ?? RightsService.currentOccasionId()!,
        from: _from,
        to: _to,
      ),
    );
    if (!mounted || epoch != _loadEpoch) return;
    setState(() {
      if (result == null) {
        _error = true;
      } else {
        _days = result;
      }
      _loading = false;
    });
  }

  void _setRangeDays(int days) {
    if (days == _rangeDays) return;
    final today = DateUtils.dateOnly(DateTime.now());
    setState(() {
      _rangeDays = days;
      _from = today.subtract(Duration(days: days - 1));
      _to = today.add(const Duration(days: 1));
      _days = const [];
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (!_clientSyncEnabled) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.history_toggle_off),
            const SizedBox(height: 8),
            Text(ClientChangesStrings.notActive, textAlign: TextAlign.center),
          ],
        ),
      );
    }

    return Column(
      children: [
        if (_loading) const LinearProgressIndicator(),
        Expanded(
          child: _error && _days.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_offline
                          ? ClientChangesStrings.onlineOnly
                          : ClientChangesStrings.loadError),
                      TextButton(
                        onPressed: _load,
                        child: Text(ClientChangesStrings.retry),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text(
                        ClientChangesStrings.title,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(ClientChangesStrings.subtitle(_rangeDays)),
                      const SizedBox(height: 12),
                      SegmentedButton<int>(
                        segments: [
                          for (final days in const [7, 14])
                            ButtonSegment<int>(
                              value: days,
                              label: Text(
                                ClientChangesStrings.rangeDays(days),
                              ),
                            ),
                        ],
                        selected: {_rangeDays},
                        onSelectionChanged: (selection) =>
                            _setRangeDays(selection.single),
                      ),
                      const SizedBox(height: 24),
                      if (_days.isEmpty && !_loading)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 40),
                          child: Center(
                            child: Text(
                              ClientChangesStrings.empty(_rangeDays),
                            ),
                          ),
                        )
                      else
                        ClientActivityBarChart(
                          days: _days,
                          from: _from,
                          to: _to,
                        ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

class ClientActivityBarChart extends StatelessWidget {
  const ClientActivityBarChart({
    super.key,
    required this.days,
    required this.from,
    required this.to,
  });

  final List<ClientActivityDay> days;
  final DateTime from;
  final DateTime to;

  static String _key(DateTime date) => '${date.year}-${date.month}-${date.day}';

  static int _niceMaximum(int value) {
    if (value <= 1) return 1;
    final magnitude = math.pow(10, value.toString().length - 1).toInt();
    final normalized = value / magnitude;
    final nice = normalized <= 1
        ? 1
        : normalized <= 2
            ? 2
            : normalized <= 5
                ? 5
                : 10;
    return nice * magnitude;
  }

  @override
  Widget build(BuildContext context) {
    final byDay = {for (final day in days) _key(day.day): day};
    final visibleDays = <ClientActivityDay>[];
    for (var day = DateUtils.dateOnly(from);
        day.isBefore(to);
        day = day.add(const Duration(days: 1))) {
      visibleDays.add(byDay[_key(day)] ??
          ClientActivityDay(
            day: day,
            actionCount: 0,
            changedItemCount: 0,
            activeActorCount: 0,
          ));
    }
    final total = visibleDays.fold<int>(0, (sum, day) => sum + day.actionCount);
    final rawMaximum = visibleDays.fold<int>(
      0,
      (maximum, day) => math.max(maximum, day.actionCount),
    );
    final maximum = _niceMaximum(rawMaximum);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              ClientChangesStrings.totalChanges(total),
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final minimumWidth = visibleDays.length * 48.0 + 44;
                final width = math.max(constraints.maxWidth, minimumWidth);
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: width,
                    height: 240,
                    child: _chart(context, visibleDays, maximum),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _chart(
    BuildContext context,
    List<ClientActivityDay> visibleDays,
    int maximum,
  ) {
    final textStyle = Theme.of(context).textTheme.labelSmall;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 40,
          height: 190,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('$maximum', style: textStyle),
              Text('${maximum ~/ 2}', style: textStyle),
              Text('0', style: textStyle),
            ],
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Stack(
            children: [
              ...[0.0, 0.5, 1.0].map(
                (position) => Positioned(
                  left: 0,
                  right: 0,
                  top: position * 180,
                  child: Divider(
                    height: 1,
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: visibleDays
                    .map((day) => Expanded(
                          child: _dayColumn(context, day, maximum),
                        ))
                    .toList(growable: false),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _dayColumn(
    BuildContext context,
    ClientActivityDay day,
    int maximum,
  ) {
    final barHeight = day.actionCount == 0
        ? 0.0
        : math.max(4.0, 150 * day.actionCount / maximum);
    final dateLabel = DateFormat.MEd().format(day.day);
    final semantics = ClientChangesStrings.dayChanges(
      dateLabel,
      day.actionCount,
    );
    return Semantics(
      label: semantics,
      child: Tooltip(
        message: semantics,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Column(
            children: [
              SizedBox(
                height: 180,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text('${day.actionCount}',
                        style: Theme.of(context).textTheme.labelSmall),
                    const SizedBox(height: 3),
                    AnimatedContainer(
                      key: ValueKey('activity-${_key(day.day)}'),
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeOutCubic,
                      width: 28,
                      height: barHeight,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(6),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                dateLabel,
                maxLines: 1,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
