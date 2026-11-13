import 'package:material_ui/material_ui.dart';

import '../_shared/editor_scroll.dart';
import 'occasion_settings_strings.dart';

enum OccasionSettingsChapter { details, appearance, features, advanced }

class OccasionSettingsLayoutController extends ChangeNotifier {
  final ScrollController scrollController = ScrollController();
  final Map<OccasionSettingsChapter, GlobalKey> anchors = {
    for (final chapter in OccasionSettingsChapter.values) chapter: GlobalKey(),
  };
  final Set<OccasionSettingsChapter> expanded;
  bool _disposed = false;
  OccasionSettingsLayoutController({
    OccasionSettingsChapter initialChapter = OccasionSettingsChapter.details,
  }) : expanded = {initialChapter};
  void toggle(OccasionSettingsChapter chapter) {
    if (!expanded.remove(chapter)) expanded.add(chapter);
    notifyListeners();
  }

  void reveal(OccasionSettingsChapter chapter, {BuildContext? target}) {
    if (_disposed) return;
    expanded.add(chapter);
    notifyListeners();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed) return;
      final context = target?.mounted == true
          ? target
          : anchors[chapter]?.currentContext;
      if (context == null || !context.mounted) return;
      revealEditorTarget(context, controller: scrollController);
    });
  }

  @override
  void dispose() {
    _disposed = true;
    scrollController.dispose();
    super.dispose();
  }
}

class OccasionSettingsChapterScope extends InheritedWidget {
  final OccasionSettingsChapter chapter;
  final bool mobile;
  const OccasionSettingsChapterScope({
    super.key,
    required this.chapter,
    this.mobile = false,
    required super.child,
  });
  static OccasionSettingsChapter? of(BuildContext context) => context
      .getInheritedWidgetOfExactType<OccasionSettingsChapterScope>()
      ?.chapter;
  static bool? mobileOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<OccasionSettingsChapterScope>()
      ?.mobile;
  @override
  bool updateShouldNotify(OccasionSettingsChapterScope oldWidget) =>
      chapter != oldWidget.chapter || mobile != oldWidget.mobile;
}

/// The document retains the same chapter topology across every breakpoint.
class OccasionSettingsLayout extends StatelessWidget {
  final OccasionSettingsLayoutController controller;
  final Widget details, appearance, features, advanced;
  final Widget? deletion;
  const OccasionSettingsLayout({
    super.key,
    required this.controller,
    required this.details,
    required this.appearance,
    required this.features,
    required this.advanced,
    this.deletion,
  });
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final mobile = constraints.maxWidth <= 700;
      final labels = <OccasionSettingsChapter, String>{
        OccasionSettingsChapter.details: OccasionSettingsStrings.eventDetails,
        OccasionSettingsChapter.appearance:
            OccasionSettingsStrings.appearanceVisibility,
        OccasionSettingsChapter.features: OccasionSettingsStrings.features,
        OccasionSettingsChapter.advanced:
            OccasionSettingsStrings.advancedSettings,
      };
      final contents = [details, appearance, features, advanced];
      return AnimatedBuilder(
        animation: controller,
        builder: (context, _) => Column(
          children: [
            if (!mobile)
              Align(
                alignment: Alignment.center,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1210),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 8,
                    ),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final chapter in OccasionSettingsChapter.values)
                          TextButton(
                            onPressed: () => controller.reveal(chapter),
                            child: Text(labels[chapter]!),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            Expanded(
              key: const ValueKey('document-scroll'),
              child: SingleChildScrollView(
                controller: controller.scrollController,
                padding: EdgeInsets.symmetric(
                  horizontal: mobile ? 16 : 32,
                  vertical: mobile ? 8 : 24,
                ),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1146),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final chapter in OccasionSettingsChapter.values)
                          OccasionSettingsChapterScope(
                            chapter: chapter,
                            mobile: mobile,
                            child: Padding(
                              key: controller.anchors[chapter],
                              padding: const EdgeInsets.only(bottom: 24),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Semantics(
                                    header: true,
                                    child: mobile
                                        ? TextButton(
                                            style: TextButton.styleFrom(
                                              alignment: Alignment.centerLeft,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 16,
                                                    horizontal: 4,
                                                  ),
                                            ),
                                            onPressed: () {
                                              FocusManager.instance.primaryFocus
                                                  ?.unfocus();
                                              controller.toggle(chapter);
                                            },
                                            child: Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    labels[chapter]!,
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .titleLarge,
                                                  ),
                                                ),
                                                Icon(
                                                  controller.expanded.contains(
                                                        chapter,
                                                      )
                                                      ? Icons.expand_less
                                                      : Icons.expand_more,
                                                ),
                                              ],
                                            ),
                                          )
                                        : Padding(
                                            padding: const EdgeInsets.only(
                                              bottom: 20,
                                            ),
                                            child: Text(
                                              labels[chapter]!,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleLarge,
                                            ),
                                          ),
                                  ),
                                  Offstage(
                                    offstage:
                                        mobile &&
                                        !controller.expanded.contains(chapter),
                                    child: TickerMode(
                                      enabled:
                                          !mobile ||
                                          controller.expanded.contains(chapter),
                                      child: ExcludeFocus(
                                        excluding:
                                            mobile &&
                                            !controller.expanded.contains(
                                              chapter,
                                            ),
                                        child: contents[chapter.index],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  const Divider(height: 1),
                                ],
                              ),
                            ),
                          ),
                        ?deletion,
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

/// Keeps the live editor subtree in one parent while preview moves beside it.
class OccasionAppearanceLayout extends StatelessWidget {
  final Widget editor, preview;
  const OccasionAppearanceLayout({
    super.key,
    required this.editor,
    required this.preview,
  });
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 950;
      return Wrap(
        spacing: 28,
        runSpacing: 24,
        children: [
          SizedBox(
            width: wide ? constraints.maxWidth - 348 : constraints.maxWidth,
            child: editor,
          ),
          SizedBox(
            width: wide ? 320 : constraints.maxWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  OccasionSettingsStrings.preview,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 12),
                IgnorePointer(child: ExcludeFocus(child: preview)),
              ],
            ),
          ),
        ],
      );
    },
  );
}

/// Keep ordinary event fields readable inside the wider feature document.
class OccasionDetailsLayout extends StatelessWidget {
  final Widget child;
  const OccasionDetailsLayout({super.key, required this.child});
  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.topStart,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: child,
    ),
  );
}

/// Date/time and its secondary timezone share a compact, stable visual group.
class OccasionTermLayout extends StatelessWidget {
  final Widget child;
  const OccasionTermLayout({super.key, required this.child});
  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.topStart,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        child: Padding(padding: const EdgeInsets.all(16), child: child),
      ),
    ),
  );
}
