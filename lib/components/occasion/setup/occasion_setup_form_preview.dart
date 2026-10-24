import 'package:festapp_core/forms.dart';
import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import '../../fonts/form_font_catalog.dart';
import '../../forms/models/holder_models/form_holder.dart';
import '../../forms/widgets_view/form_helper.dart';
import 'occasion_form_draft.dart';
import 'occasion_setup_appearance.dart';

// Draft fields have no database identity yet. Public builders require an ID;
// assign stable local identities on a copy, never in the persisted draft.
FormDefinition occasionSetupPreviewDefinition(Map<String, dynamic> draft) {
  final bundle =
      draftFormBundle(Map<String, dynamic>.from(draft['formDraft'] as Map));
  return bundle.form.definition.copyWith(relatedFields: [
    for (var i = 0; i < bundle.form.relatedFields.length; i++)
      bundle.form.relatedFields[i].definition.copyWith(id: -(i + 1)),
  ]);
}

/// Uses the public form's field builders, definitions and font catalog.
class OccasionSetupFormPreview extends StatefulWidget {
  final Map<String, dynamic> draft;
  const OccasionSetupFormPreview({super.key, required this.draft});
  @override
  State<OccasionSetupFormPreview> createState() =>
      _OccasionSetupFormPreviewState();
}

class _OccasionSetupFormPreviewState extends State<OccasionSetupFormPreview> {
  final _key = GlobalKey<FormBuilderState>();
  Future<FormFontCatalog> _loadFonts() async {
    final fonts = await FormFontCatalog.load();
    await fonts.ensureFamily(
        OccasionSetupAppearance.read(widget.draft)['fontFamily'] as String);
    return fonts;
  }

  late Future<FormFontCatalog> _fonts = _loadFonts();
  @override
  Widget build(BuildContext context) => FutureBuilder<FormFontCatalog>(
      future: _fonts,
      builder: (context, snapshot) {
        if (snapshot.hasError)
          return TextButton(
              onPressed: () => setState(() => _fonts = _loadFonts()),
              child: const Text('Písmo se nepodařilo načíst. Zkusit znovu'));
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());
        final definition = occasionSetupPreviewDefinition(widget.draft);
        final holder = FormHolder.fromDefinition(definition);
        holder.controller = FormHolderController(globalKey: _key);
        final appearance = OccasionSetupAppearance.read(widget.draft);
        Color color(String key) =>
            Color(int.parse('ff${appearance[key]}', radix: 16));
        final theme = Theme.of(context);
        return Theme(
            data: theme.copyWith(
                textTheme: snapshot.data!.getTextTheme(
                    appearance['fontFamily'] as String, theme.textTheme)),
            child: Builder(
                builder: (context) => Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                          color: color('primary'),
                          gradient: appearance['gradient'] == true
                              ? LinearGradient(colors: [
                                  color('primary'),
                                  color('secondary')
                                ])
                              : null,
                          borderRadius: BorderRadius.circular(12)),
                      child: Card(
                          child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text(definition.title ?? '',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleLarge),
                                    const SizedBox(height: 8),
                                    Text(MaterialLocalizations.of(context)
                                        .formatMediumDate(DateTime.parse(
                                            widget.draft['start'] as String))),
                                    const SizedBox(height: 16),
                                    IgnorePointer(
                                        child: FormBuilder(
                                            key: _key,
                                            child: Column(
                                                children:
                                                    FormHelper.getAllFormFields(
                                                        context,
                                                        _key,
                                                        holder)))),
                                  ]))),
                    )));
      });
}
