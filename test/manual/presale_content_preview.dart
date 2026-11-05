// Disposable real-widget QA surface. No backend connection or production writes.
import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:festapp_core/time.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/forms/models/form_editor_draft.dart';
import 'package:fstapp/components/forms/views/presale_content_editor.dart';
import 'package:fstapp/components/html/rich_html_editor_controller.dart';
import 'package:fstapp/widgets/dependency_material_bridge.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();
  OccasionTimeContext.initializeTimeZones();
  OccasionTimeContext.setLocalLocation('Europe/Prague');
  runApp(
    EasyLocalization(
      supportedLocales: const [Locale('cs')],
      startLocale: const Locale('cs'),
      path: 'assets/translations',
      child: const _App(),
    ),
  );
}

class _App extends StatelessWidget {
  const _App();
  @override
  Widget build(BuildContext context) => MaterialApp(
    locale: context.locale,
    supportedLocales: context.supportedLocales,
    localizationsDelegates: [
      ...context.localizationDelegates,
      ...GlobalMaterialLocalizations.delegates,
    ],
    builder: DependencyMaterialBridge.builder,
    home: const _Preview(),
  );
}

class _Preview extends StatefulWidget {
  const _Preview();
  @override
  State<_Preview> createState() => _PreviewState();
}

class _PreviewState extends State<_Preview> {
  final media = HtmlSaveCoordinator();
  FormEditorDraft form = FormEditorDraft(
    id: 1,
    title: 'Podzimní ples',
    occasionId: 1,
    isOpen: true,
    data: {
      'design': {'presale_header': 'event_and_date'},
      'schedule': {
        'start_time': '2099-11-05T17:00:00Z',
        'countdown_title': '<p>Večer plný hudby a tance.</p>',
      },
    },
  );
  late String baseline = jsonEncode(form.toEditedJson());
  bool dark = false;
  @override
  void dispose() {
    media.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dirty = jsonEncode(form.toEditedJson()) != baseline;
    return Theme(
      data: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Náhled editoru - lokální data'),
          actions: [
            IconButton(
              tooltip: 'Změnit motiv',
              onPressed: () => setState(() => dark = !dark),
              icon: const Icon(Icons.brightness_6),
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    dirty ? 'Neuložené změny' : 'Beze změn',
                    key: const ValueKey('draft-status'),
                  ),
                  PresaleContentEditor(
                    form: form,
                    coordinator: media,
                    canEdit: true,
                    loadSummary: (_) async => {},
                    onChanged: () => setState(() {}),
                  ),
                  FilledButton(
                    onPressed: dirty
                        ? () {
                            media.flush();
                            setState(() {
                              form = FormEditorDraft.fromJson(form.toJson());
                              baseline = jsonEncode(form.toEditedJson());
                            });
                          }
                        : null,
                    child: Text(CommonStrings.save),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
