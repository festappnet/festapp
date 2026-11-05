import 'package:super_editor/super_editor.dart';
import 'package:html/parser.dart' as parser;
import 'package:festapp_core/forms.dart';

import '../html/rich_html_editor_controller.dart';
import 'models/form_editor_draft.dart';
import 'widgets_view/presale_content.dart';

typedef PresaleDraftState = ({
  bool timer,
  bool enabled,
  bool paused,
  String header,
  bool emailPresent,
  bool emailAuthorized,
});

/// The form owns persistence, versions and command identity. The native HTML
/// history owns this small immutable participant alongside every text edit.
class PresaleContentDraft {
  PresaleContentDraft(this.form, {required this.editor});
  final FormEditorDraft form;
  final RichHtmlEditorController editor;
  static PresaleDraftState stateOf(FormDefinition d) => (
    timer: d.enableCountdown,
    enabled: d.saleOpeningEnabled,
    paused: d.saleOpeningPaused,
    header: d.presaleHeader,
    emailPresent: hasPresaleSlot(
      d.presaleContent ?? '',
      'form-sale-opening-notification',
    ),
    emailAuthorized:
        d.saleOpeningEnabled &&
        !d.saleOpeningPaused &&
        hasPresaleSlot(
          d.presaleContent ?? '',
          'form-sale-opening-notification',
        ),
  );

  static HtmlHistoryBinding binding(
    FormEditorDraft form,
    void Function() changed,
  ) {
    final initial = form.definition;
    final baseline = stateOf(initial);
    return HtmlHistoryBinding(
      initialState: baseline,
      reconcile: (html, value) {
        final state = value as PresaleDraftState;
        final present = hasPresaleSlot(html, 'form-sale-opening-notification');
        return (
          timer: state.timer && hasPresaleSlot(html, 'form-countdown'),
          enabled: state.enabled,
          paused:
              state.paused ||
              (state.enabled &&
                  ((state.emailPresent && !present) ||
                      (!state.emailPresent &&
                          present &&
                          !state.emailAuthorized))),
          header: state.header,
          emailPresent: present,
          emailAuthorized: state.emailAuthorized && present,
        );
      },
      publish: (html, value) {
        final state = value as PresaleDraftState;
        html = presaleEditedHtml(html, initial.presaleContent);
        var d = form.definition.withPresaleContent(
          html == (initial.presaleContent ?? '')
              ? initial.presaleContent
              : html,
        );
        // Restore absence/null exactly on Undo without rolling back unrelated
        // schedule changes. Only this participant's four keys belong to history.
        final data = {...?d.data};
        void assign(String section, String key, Object v, Object base) {
          final target = Map<String, dynamic>.from(data[section] as Map? ?? {});
          final original = initial.data?[section] as Map? ?? {};
          if (v == base) {
            if (original.containsKey(key)) {
              target[key] = original[key];
            } else {
              target.remove(key);
            }
          } else {
            target[key] = v;
          }
          if (target.isEmpty && !((initial.data ?? {}).containsKey(section))) {
            data.remove(section);
          } else {
            data[section] = target;
          }
        }

        assign('schedule', 'enable_countdown', state.timer, baseline.timer);
        assign(
          'sale_opening_notifications',
          'enabled',
          state.enabled,
          baseline.enabled,
        );
        assign(
          'sale_opening_notifications',
          'collection_paused',
          state.paused,
          baseline.paused,
        );
        assign('design', 'presale_header', state.header, baseline.header);
        form.definition = d.copyWith(data: data);
        changed();
      },
    );
  }

  static FormDefinition collectDefinition(FormDefinition d) => d
      .withSaleOpening(enabled: true, paused: false)
      .withPresaleContent(
        insertSaleOpeningBlock(
          d.enableCountdown
              ? countdownContent(d.presaleContent)
              : d.presaleContent ?? '',
        ),
      );

  void collect() {
    final d = form.definition;
    if (d.startTimeUtc?.isAfter(DateTime.now()) != true || d.isOpen != true) {
      throw StateError('sale_opening_requires_future_start');
    }
    editor.transact(
      (
        timer: d.enableCountdown,
        enabled: true,
        paused: false,
        header: d.presaleHeader,
        emailPresent: hasPresaleSlot(
          editor.html,
          'form-sale-opening-notification',
        ),
        emailAuthorized: true,
      ),
      () {
        if (!hasPresaleSlot(editor.html, 'form-sale-opening-notification')) {
          final timers = editor.editor.document.where(
            (node) =>
                editor.embeddedBlockFor(node)?.cssClass == 'form-countdown',
          );
          editor.insertEmbeddedBlock(
            editor.embeddedBlocks.firstWhere(
              (b) => b.cssClass == 'form-sale-opening-notification',
            ),
            afterNodeId: timers.isEmpty ? null : timers.first.id,
            atEnd: timers.isEmpty,
          );
        }
      },
    );
  }

  void pause() => _state(paused: true);
  void end() => _state(enabled: false, paused: false);
  void header(String header) => _state(header: header);
  void countdown(bool enabled) {
    final d = form.definition;
    editor.transact(
      (
        timer: enabled,
        enabled: d.saleOpeningEnabled,
        paused: d.saleOpeningPaused,
        header: d.presaleHeader,
        emailPresent: stateOf(d).emailPresent,
        emailAuthorized: stateOf(d).emailAuthorized,
      ),
      () {
        if (enabled)
          editor.insertEmbeddedBlock(
            editor.embeddedBlocks.firstWhere(
              (b) => b.cssClass == 'form-countdown',
            ),
            atEnd: true,
          );
      },
    );
  }

  void _state({bool? enabled, bool? paused, String? header}) {
    final d = form.definition;
    editor.transact((
      timer: d.enableCountdown,
      enabled: enabled ?? d.saleOpeningEnabled,
      paused: paused ?? d.saleOpeningPaused,
      header: header ?? d.presaleHeader,
      emailPresent: stateOf(d).emailPresent,
      emailAuthorized: stateOf(d).emailAuthorized,
    ), () {});
  }
}

/// Recovery is an explicit draft edit. Historically inert slots stay inert.
String inertPresaleSecondary(String html) {
  final root = parser.parseFragment(html);
  for (final node in root.querySelectorAll('*')) {
    node.classes.removeAll([
      'html-editor-block',
      'form-countdown',
      'form-sale-opening-notification',
      'form-presale-system-title',
    ]);
  }
  return '<div class="form-presale-legacy-secondary" style="text-align:left;font-size:18px">${root.outerHtml}</div>';
}

bool hasPresaleSlot(String html, String type) =>
    parser.parseFragment(html).querySelector('div.html-editor-block.$type') !=
    null;

/// A migrated system paragraph remains localized until its contents are
/// deliberately edited. Styling or replacing that text makes it authored HTML;
/// public renderers must then preserve the user's edit. Undo retains the marker.
String presaleEditedHtml(String html, String? original) {
  if (!html.contains('form-presale-system-title')) return html;
  final root = parser.parseFragment(html);
  final baseline = parser
      .parseFragment(original ?? '')
      .querySelectorAll('.form-presale-system-title');
  var changed = false;
  final current = root.querySelectorAll('.form-presale-system-title');
  for (var i = 0; i < current.length; i++) {
    if (i < baseline.length && current[i].innerHtml == baseline[i].innerHtml)
      continue;
    current[i].classes.remove('form-presale-system-title');
    if (current[i].classes.isEmpty) current[i].attributes.remove('class');
    changed = true;
  }
  return changed ? root.outerHtml : html;
}
