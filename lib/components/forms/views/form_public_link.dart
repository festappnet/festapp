import 'package:fstapp/widgets/app_dialog.dart';
import 'form_embed_code.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/link.dart';
import 'package:fstapp/app_config.dart';
import '../../_shared/copy_button.dart';
import '../form_strings.dart';

/// Only newly entered or changed slugs use this format. Legacy values stay exact.
bool isValidPublicSlug(String value, {bool allowEmpty = false}) =>
    (allowEmpty && value.isEmpty) ||
    (value.length <= 80 &&
        RegExp(r'^[a-z0-9]+(?:[-_][a-z0-9]+)*$').hasMatch(value));

String publicLinkUrl(String link, {bool isForm = true}) =>
    '${AppConfig.webLink}/${isForm ? 'form/' : ''}${Uri.encodeComponent(link)}${isForm ? '' : '/event'}';

/// Draft addresses are plain text; saved addresses can be opened and copied.
class PublicLink extends StatelessWidget {
  final String link;
  final String? savedLink;
  final bool isForm;
  final bool showCopyLabel;
  const PublicLink(
      {super.key,
      required this.link,
      this.savedLink,
      this.isForm = true,
      this.showCopyLabel = false});

  @override
  Widget build(BuildContext context) {
    final saved = savedLink;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (saved != null && saved.isNotEmpty) ...[
        Text(FormStrings.savedPublicLink, style: const TextStyle(fontSize: 12)),
        Row(children: [
          Expanded(
            child: Link(
              uri: Uri.parse(publicLinkUrl(saved, isForm: isForm)),
              target: LinkTarget.blank,
              builder: (context, followLink) => InkWell(
                onTap: followLink,
                child: Text(
                  publicLinkUrl(saved, isForm: isForm),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
          ),
          CopyButton(
              value: publicLinkUrl(saved, isForm: isForm),
              showLabel: showCopyLabel),
        ]),
      ],
      if (link != saved) ...[
        Text(
            link.isEmpty
                ? FormStrings.automaticPublicLink
                : FormStrings.publicLinkPreview,
            style: const TextStyle(fontSize: 12)),
        if (link.isNotEmpty)
          SelectableText(publicLinkUrl(link, isForm: isForm)),
      ],
    ]);
  }
}

class FormPublicLink extends StatelessWidget {
  final String link;
  final String? savedLink;
  const FormPublicLink({super.key, required this.link, this.savedLink});

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        PublicLink(link: link, savedLink: savedLink),
        if (savedLink != null && savedLink!.isNotEmpty)
          TextButton.icon(
            icon: const Icon(Icons.code),
            label: Text(FormStrings.embedAction),
            onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => _EmbedDialog(savedLink: savedLink!)),
          )
        else
          Text(FormStrings.embedSaveFirst),
      ]);
}

class _EmbedDialog extends StatefulWidget {
  final String savedLink;
  const _EmbedDialog({required this.savedLink});

  @override
  State<_EmbedDialog> createState() => _EmbedDialogState();
}

class _EmbedDialogState extends State<_EmbedDialog> {
  bool automatic = true;

  @override
  Widget build(BuildContext context) {
    final code = formEmbedCode(
        tenantUrl: AppConfig.webLink,
        savedLink: widget.savedLink,
        title: FormStrings.embedTitle,
        fallbackLabel: FormStrings.embedFallback,
        automatic: automatic);
    return AppAlertDialog(
      title: Text(FormStrings.embedAction),
      content: SizedBox(
          width: 600,
          child: SingleChildScrollView(
              child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(FormStrings.embedHelp),
              const SizedBox(height: 12),
              DropdownButton<bool>(
                value: automatic,
                isExpanded: true,
                items: [
                  DropdownMenuItem(
                      value: true, child: Text(FormStrings.embedAutomatic)),
                  DropdownMenuItem(
                      value: false, child: Text(FormStrings.embedFixed)),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => automatic = value);
                },
              ),
              const SizedBox(height: 12),
              SelectableText(code),
              Align(
                  alignment: Alignment.centerRight,
                  child: CopyButton(value: code)),
            ],
          ))),
    );
  }
}
