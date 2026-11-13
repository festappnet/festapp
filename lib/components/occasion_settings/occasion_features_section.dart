import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:fstapp/app_config.dart';

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
  final ScrollController? scrollController;
  final VoidCallback? onReveal;
  const OccasionFeaturesSection({
    super.key,
    required this.features,
    required this.isEditingEnabled,
    required this.occasionId,
    required this.controller,
    this.scrollController,
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
  final Map<String, GlobalKey> _panels = {};
  String? _selected;
  int _revealRevision = 0;
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
      _panels[feature.code] = GlobalKey();
    }
    widget.controller.onReveal = _reveal;
  }

  void _reveal(String code) {
    if (!mounted || !_panels.containsKey(code)) return;
    widget.onReveal?.call();
    setState(() {
      _search.clear();
      _selected = code;
      _visited.add(code);
    });
    _scrollTo(code);
  }

  void _scrollTo(String code) {
    final revision = ++_revealRevision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || revision != _revealRevision || _selected != code) return;
      final target = _panels[code]?.currentContext;
      if (target != null) {
        revealEditorTarget(target, controller: widget.scrollController);
      }
    });
  }

  void _toggle(Feature feature, bool value) {
    widget.controller.saveFeature(feature.code);
    setState(() {
      feature.isEnabled = value;
      _visited.add(feature.code);
    });
    EditorDraftScope.changed(context);
    if (_selected == feature.code) _scrollTo(feature.code);
  }

  @override
  void dispose() {
    widget.controller.onReveal = null;
    _search.dispose();
    for (final node in _buttons.values) {
      node.dispose();
    }
    super.dispose();
  }

  Widget _host(Feature feature, bool visible) => OccasionFeatureEditorHost(
    key: ValueKey('feature-host-${feature.code}'),
    feature: feature,
    controller: widget.controller,
    visible: visible,
    child: Container(
      key: _panels[feature.code],
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    FeatureMetadata.getTitle(feature.code),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: CommonStrings.close,
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    FocusManager.instance.primaryFocus?.unfocus();
                    setState(() {
                      _selected = null;
                      ++_revealRevision;
                    });
                    _buttons[feature.code]?.requestFocus();
                  },
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(OccasionSettingsStrings.featureEnabled),
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
    final stacked = statusWidth + 12 + actionWidth > contentWidth;
    final statusHeight = statuses
        .map(
          (text) => measure(
            text,
            theme.labelMedium,
            stacked ? contentWidth : contentWidth - actionWidth - 12,
          ).height,
        )
        .reduce(math.max);
    final footerHeight = stacked
        ? statusHeight + 8 + actionHeight
        : math.max(statusHeight, actionHeight);
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
    final status = Text(
      feature.isEnabled
          ? OccasionSettingsStrings.enabled
          : OccasionSettingsStrings.disabled,
      style: Theme.of(context).textTheme.labelMedium,
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
        onPressed: () {
          setState(() {
            _selected = feature.code;
            _visited.add(feature.code);
          });
          _scrollTo(feature.code);
        },
        child: Text(
          OccasionSettingsStrings.configure,
          textAlign: TextAlign.center,
        ),
      ),
    );
    return Container(
      key: ValueKey('feature-tile-${feature.code}'),
      height: extent.height,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: selected ? colors.primaryContainer : colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected ? colors.primary : colors.outlineVariant,
        ),
      ),
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
      final rendered = <String>{};
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
          for (final feature in row.where((f) => f.code == _selected)) {
            children.add(_host(feature, true));
            rendered.add(feature.code);
          }
        }
      }
      if (projection.isEmpty) {
        children.add(Text(OccasionSettingsStrings.noFeaturesFound));
      }
      for (final feature in _supported.where(
        (f) => _visited.contains(f.code) && !rendered.contains(f.code),
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
