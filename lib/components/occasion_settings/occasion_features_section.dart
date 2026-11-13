import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/widgets/app_dialog.dart';

import '../_shared/common_strings.dart';
import '../_shared/editor_draft_scope.dart';
import '../_shared/editor_scroll.dart';
import '../features/feature.dart';
import '../features/feature_metadata.dart';
import '../features/feature_service.dart';
import '../features/feature_settings_editor.dart';
import '../features/ticket_feature.dart';
import '../ticket_layout/ticket_layout_service.dart';
import 'occasion_feature_editor_host.dart';
import 'occasion_features_controller.dart';
import 'occasion_settings_strings.dart';
import 'occasion_settings_layout.dart';

class OccasionFeaturesSection extends StatefulWidget {
  final List<Feature> features;
  final bool isEditingEnabled;
  final int occasionId;
  final Future<void> Function(TicketFeature)? onSaveTicket;
  final TicketLayoutService? ticketLayoutService;
  final OccasionFeaturesController controller;
  final VoidCallback? onReveal;
  const OccasionFeaturesSection({
    super.key,
    required this.features,
    required this.isEditingEnabled,
    required this.occasionId,
    required this.controller,
    this.onReveal,
    this.onSaveTicket,
    this.ticketLayoutService,
  });
  @override
  State<OccasionFeaturesSection> createState() =>
      _OccasionFeaturesSectionState();
}

class _OccasionFeaturesSectionState extends State<OccasionFeaturesSection> {
  final _search = TextEditingController();
  final Set<String> _visited = {};
  // Extension-based editors may construct controllers in their builders. Keep
  // their widget instance stable while a host moves, filters or changes rows.
  final Map<String, Widget> _editors = {};
  Widget _editor(Feature feature) {
    Widget build() => buildFeatureSettingsEditor(
      context,
      feature,
      occasionId: widget.occasionId,
      readOnly: !widget.isEditingEnabled,
      ticketLayoutService: widget.ticketLayoutService,
      onSaveTicket: widget.onSaveTicket,
    );
    // TicketSettings owns its own state and needs updated layout/service input.
    return feature is TicketFeature
        ? build()
        : _editors.putIfAbsent(feature.code, build);
  }

  final Map<String, FocusNode> _buttons = {};
  final Map<String, GlobalKey> _hosts = {};
  String? _selected;
  bool _dialogAttached = false, _closing = false;
  BuildContext? _dialogContext;
  StateSetter? _refreshDialog;
  ModalRoute<dynamic>? _dialogRoute;
  NavigatorState? _dialogNavigator;
  Future<void>? _dialogDone;

  Iterable<Feature> get _supported => widget.features.where(
    (f) =>
        AppConfig.isAppSupported ||
        !FeatureService.appSupportedFeatures.contains(f.code),
  );

  @override
  void initState() {
    super.initState();
    _visited.addAll(_supported.where((f) => f.isEnabled).map((f) => f.code));
    for (final feature in _supported) {
      _buttons[feature.code] = FocusNode();
      _hosts[feature.code] = GlobalKey();
    }
    widget.controller.onReveal = _reveal;
  }

  @override
  void didUpdateWidget(covariant OccasionFeaturesSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isEditingEnabled != widget.isEditingEnabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _dialogAttached) _refreshDialog?.call(() {});
      });
    }
  }

  void _reveal(String code, BuildContext? target) {
    final feature = _supported.where((f) => f.code == code).firstOrNull;
    if (feature == null) return;
    widget.onReveal?.call();
    _open(feature, target: target);
  }

  Future<void> _open(Feature feature, {BuildContext? target}) async {
    if (_selected == feature.code && _dialogAttached) {
      _revealField(target);
      return;
    }
    final previous = _dialogDone;
    if (previous != null) {
      await _closeDialog();
      await previous;
      if (!mounted) return;
    }
    final onChanged = context
        .getInheritedWidgetOfExactType<EditorDraftScope>()
        ?.onChanged;
    setState(() {
      _selected = feature.code;
      _visited.add(feature.code);
      _dialogAttached = true;
    });
    final future = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, refresh) {
          _dialogContext = dialogContext;
          _refreshDialog = refresh;
          _dialogRoute = ModalRoute.of(dialogContext);
          _dialogNavigator = Navigator.of(dialogContext);
          return EditorDraftScope(
            onChanged: () => onChanged?.call(),
            child: PopScope(
              canPop: false,
              onPopInvokedWithResult: (didPop, _) {
                if (!didPop) _closeDialog();
              },
              child: AppDialog(
                onClose: _closeDialog,
                insetPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 24,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 1050,
                    maxHeight: MediaQuery.sizeOf(dialogContext).height - 48,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
                        child: AppDialogHeader(
                          title: Text(FeatureMetadata.getTitle(feature.code)),
                          onClose: _closeDialog,
                        ),
                      ),
                      const Divider(height: 1),
                      Flexible(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(20),
                          child: _dialogAttached
                              ? _host(feature, true)
                              : const SizedBox.shrink(),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                        child: Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: FilledButton(
                            onPressed: _closeDialog,
                            child: Text(CommonStrings.close),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
    _dialogDone = future;
    _revealField(target);
    try {
      await future;
    } finally {
      _dialogDone = null;
      _dialogContext = null;
      _refreshDialog = null;
      _dialogRoute = null;
      _dialogNavigator = null;
      if (mounted) {
        setState(() {
          _selected = null;
          _dialogAttached = false;
        });
        _buttons[feature.code]?.requestFocus();
      }
    }
  }

  void _revealField(BuildContext? target) {
    if (target == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && target.mounted) revealEditorTarget(target);
    });
  }

  Future<void> _closeDialog() async {
    if (_closing || !_dialogAttached) return;
    _closing = true;
    final dialogContext = _dialogContext;
    // Reparent the live Form back into its hidden page host in the same frame.
    // Controllers, invalid input and ticket drafts survive dialog dismissal.
    _refreshDialog?.call(() => _dialogAttached = false);
    if (mounted) setState(() => _selected = null);
    await WidgetsBinding.instance.endOfFrame;
    if (dialogContext?.mounted == true) Navigator.of(dialogContext!).pop();
    _closing = false;
  }

  void _toggle(Feature feature, bool value) {
    widget.controller.saveFeature(feature.code);
    setState(() {
      feature.isEnabled = value;
      _visited.add(feature.code);
    });
    _refreshDialog?.call(() {});
    EditorDraftScope.changed(context);
  }

  @override
  void dispose() {
    widget.controller.onReveal = null;
    final route = _dialogRoute;
    final navigator = _dialogNavigator;
    if (route != null && navigator != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (navigator.mounted && route.isActive) navigator.removeRoute(route);
      });
    }
    _search.dispose();
    for (final node in _buttons.values) {
      node.dispose();
    }
    super.dispose();
  }

  Widget _host(Feature feature, bool visible) => KeyedSubtree(
    key: _hosts[feature.code],
    child: OccasionFeatureEditorHost(
      key: ValueKey('feature-host-${feature.code}'),
      feature: feature,
      controller: widget.controller,
      visible: visible,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              feature.isEnabled
                  ? OccasionSettingsStrings.enabled
                  : OccasionSettingsStrings.disabled,
            ),
            value: feature.isEnabled,
            onChanged: widget.isEditingEnabled && feature.canBeDisabled
                ? (value) => _toggle(feature, value)
                : null,
          ),
          const Divider(height: 24),
          ExcludeFocus(
            excluding: !widget.isEditingEnabled,
            child: AbsorbPointer(
              absorbing: !widget.isEditingEnabled,
              child: _editor(feature),
            ),
          ),
        ],
      ),
    ),
  );
  _FeatureTileExtent _measureTiles(double tileWidth) {
    final theme = Theme.of(context).textTheme;
    final inheritedStyle = DefaultTextStyle.of(context).style;
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final locale = Localizations.localeOf(context);
    // Container padding plus its border, matching the rendered tile below.
    final contentWidth = math.max(1.0, tileWidth - 34);
    Size measure(String text, TextStyle? style, double width) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: inheritedStyle.merge(style)),
        textDirection: direction,
        textScaler: scaler,
        locale: locale,
      )..layout(maxWidth: width);
      final size = painter.size;
      painter.dispose();
      return size;
    }

    final actionNatural = measure(
      OccasionSettingsStrings.configure,
      theme.labelLarge,
      double.infinity,
    );
    final actionWidth = math.min(
      contentWidth,
      math.max(64.0, actionNatural.width.ceilToDouble() + 24),
    );
    final actionHeight = math.max(
      48.0,
      measure(
            OccasionSettingsStrings.configure,
            theme.labelLarge,
            math.max(1.0, actionWidth - 24),
          ).height.ceilToDouble() +
          16,
    );
    final statuses = [
      OccasionSettingsStrings.enabled,
      OccasionSettingsStrings.disabled,
    ];
    final statusWidth = statuses
        .map((text) => measure(text, theme.labelMedium, double.infinity).width)
        .reduce(math.max);
    final stacked = statusWidth + 68 + 12 + actionWidth > contentWidth;
    final statusHeight = statuses
        .map(
          (text) => measure(
            text,
            theme.labelMedium,
            stacked ? contentWidth - 68 : contentWidth - actionWidth - 80,
          ).height,
        )
        .reduce(math.max);
    final footerHeight = stacked
        ? math.max(48.0, statusHeight) + 8 + actionHeight
        : math.max(math.max(48.0, statusHeight), actionHeight);
    var bodyHeight = 0.0;
    // Measure the entire supported catalog, not only the current search/group.
    // A toggle or search therefore never changes the common tile extent.
    for (final feature in _supported) {
      final title = measure(
        FeatureMetadata.getTitle(feature.code),
        theme.titleMedium,
        contentWidth,
      );
      final description = measure(
        FeatureMetadata.getDescription(feature.code),
        theme.bodyMedium,
        contentWidth,
      );
      bodyHeight = math.max(bodyHeight, title.height + 8 + description.height);
    }
    return _FeatureTileExtent(
      height: (34 + bodyHeight + 16 + footerHeight).ceilToDouble() + 2,
      footerHeight: footerHeight.ceilToDouble(),
      actionWidth: actionWidth,
      actionHeight: actionHeight,
      stackedFooter: stacked,
    );
  }

  Widget _tile(Feature feature, _FeatureTileExtent extent) {
    final selected = _selected == feature.code;
    final colors = Theme.of(context).colorScheme;
    final status = Row(
      children: [
        Semantics(
          container: true,
          label: FeatureMetadata.getTitle(feature.code),
          child: Switch(
            key: ValueKey('toggle-${feature.code}'),
            value: feature.isEnabled,
            onChanged: widget.isEditingEnabled && feature.canBeDisabled
                ? (value) => _toggle(feature, value)
                : null,
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            feature.isEnabled
                ? OccasionSettingsStrings.enabled
                : OccasionSettingsStrings.disabled,
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ),
      ],
    );
    final action = SizedBox(
      width: extent.actionWidth,
      height: extent.actionHeight,
      child: TextButton(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          minimumSize: const Size(64, 48),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.standard,
          textStyle: Theme.of(context).textTheme.labelLarge,
        ),
        focusNode: _buttons[feature.code],
        key: ValueKey('configure-${feature.code}'),
        onPressed: () => _open(feature),
        child: Text(
          OccasionSettingsStrings.configure,
          textAlign: TextAlign.center,
        ),
      ),
    );
    return Material(
      color: selected ? colors.primaryContainer : colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? colors.primary : colors.outlineVariant,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Semantics(
        key: ValueKey('feature-action-${feature.code}'),
        container: true,
        button: true,
        onTap: () => _open(feature),
        child: InkWell(
          onTap: () => _open(feature),
          canRequestFocus: false,
          excludeFromSemantics: true,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            key: ValueKey('feature-tile-${feature.code}'),
            height: extent.height,
            padding: const EdgeInsets.all(17),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  FeatureMetadata.getTitle(feature.code),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  FeatureMetadata.getDescription(feature.code),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  height: extent.footerHeight,
                  child: extent.stackedFooter
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            status,
                            const Spacer(),
                            Align(
                              alignment: AlignmentDirectional.centerEnd,
                              child: action,
                            ),
                          ],
                        )
                      : Row(
                          children: [
                            Expanded(child: status),
                            const SizedBox(width: 12),
                            action,
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final query = _search.text.trim().toLowerCase();
      final projection = _supported
          .where(
            (feature) =>
                query.isEmpty ||
                FeatureMetadata.getTitle(feature.code)
                    .toLowerCase()
                    .contains(query) ||
                FeatureMetadata.getDescription(feature.code)
                    .toLowerCase()
                    .contains(query),
          )
          .toList();
      final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final mobile =
          OccasionSettingsChapterScope.mobileOf(context) ??
          constraints.maxWidth <= 700;
      final columns = mobile
          ? 1
          : (constraints.maxWidth / textScale >= 900
                ? 3
                : constraints.maxWidth / textScale >= 600
                ? 2
                : 1);
      final tileWidth = (constraints.maxWidth - 12 * (columns - 1)) / columns;
      final tileExtent = _measureTiles(tileWidth);
      final children = <Widget>[
        TextField(
          controller: _search,
          decoration: InputDecoration(
            labelText: OccasionSettingsStrings.searchFeatures,
            prefixIcon: const Icon(Icons.search),
            border: const OutlineInputBorder(),
            suffixIcon: query.isEmpty
                ? null
                : IconButton(
                    tooltip: CommonStrings.reset,
                    icon: const Icon(Icons.clear),
                    onPressed: () => setState(_search.clear),
                  ),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 24),
      ];
      for (final enabled in [true, false]) {
        final group = projection.where((f) => f.isEnabled == enabled).toList();
        if (group.isEmpty) continue;
        children.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 12, top: 8),
            child: Text(
              enabled
                  ? OccasionSettingsStrings.enabledFeatures
                  : OccasionSettingsStrings.otherFeatures,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        );
        for (var index = 0; index < group.length; index += columns) {
          final row = group.skip(index).take(columns).toList();
          children.add(
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var cell = 0; cell < columns; cell++) ...[
                    if (cell > 0) const SizedBox(width: 12),
                    Expanded(
                      child: cell < row.length
                          ? _tile(row[cell], tileExtent)
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ),
          );
        }
      }
      if (projection.isEmpty) {
        children.add(Text(OccasionSettingsStrings.noFeaturesFound));
      }
      for (final feature in _supported.where(
        (f) =>
            _visited.contains(f.code) &&
            !(_dialogAttached && _selected == f.code),
      )) {
        children.add(_host(feature, false));
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      );
    },
  );
}

/// One measured geometry shared by every tile, including both feature groups.
class _FeatureTileExtent {
  final double height, footerHeight, actionWidth, actionHeight;
  final bool stackedFooter;
  const _FeatureTileExtent({
    required this.height,
    required this.footerHeight,
    required this.actionWidth,
    required this.actionHeight,
    required this.stackedFooter,
  });
}
