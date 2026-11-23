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
  final bool showOpenAction;
  const PublicLink({
    super.key,
    required this.link,
    this.savedLink,
    this.isForm = true,
    this.showCopyLabel = false,
    this.showOpenAction = false,
  });

  @override
  Widget build(BuildContext context) {
    final saved = savedLink;
    final labelStyle = Theme.of(context).textTheme.labelMedium;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (saved != null && saved.isNotEmpty) ...[
          Text(FormStrings.savedPublicLink, style: labelStyle),
          const SizedBox(height: 4),
          if (showOpenAction) ...[
            SelectableText(publicLinkUrl(saved, isForm: isForm)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Link(
                  uri: Uri.parse(publicLinkUrl(saved, isForm: isForm)),
                  target: LinkTarget.blank,
                  builder: (context, followLink) => TextButton.icon(
                    onPressed: followLink,
                    icon: const Icon(Icons.open_in_new),
                    label: Text(FormStrings.openPublicLink),
                  ),
                ),
                CopyButton(
                  value: publicLinkUrl(saved, isForm: isForm),
                  showLabel: true,
                ),
              ],
            ),
          ] else
            Row(
              children: [
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
                  showLabel: showCopyLabel,
                ),
              ],
            ),
        ],
        if (link != saved) ...[
          if (saved != null && saved.isNotEmpty) const SizedBox(height: 8),
          Text(
            link.isEmpty
                ? FormStrings.automaticPublicLink
                : FormStrings.publicLinkPreview,
            style: labelStyle,
          ),
          if (link.isNotEmpty) ...[
            const SizedBox(height: 4),
            SelectableText(publicLinkUrl(link, isForm: isForm)),
          ],
        ],
      ],
    );
  }
}

class FormPublicLink extends StatelessWidget {
  final String link;
  final String? savedLink;
  final VoidCallback? onOpenAppearance;
  const FormPublicLink({
    super.key,
    required this.link,
    this.savedLink,
    this.onOpenAppearance,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      PublicLink(link: link, savedLink: savedLink),
      FormEmbedAction(savedLink: savedLink, onOpenAppearance: onOpenAppearance),
    ],
  );
}

class FormEmbedAction extends StatelessWidget {
  const FormEmbedAction({
    super.key,
    required this.savedLink,
    this.onOpenAppearance,
  });

  final String? savedLink;
  final VoidCallback? onOpenAppearance;

  @override
  Widget build(BuildContext context) {
    final link = savedLink;
    if (link == null || link.isEmpty) return Text(FormStrings.embedSaveFirst);
    return TextButton.icon(
      icon: const Icon(Icons.code),
      label: Text(FormStrings.embedAction),
      onPressed: () => showDialog<void>(
        context: context,
        builder: (_) =>
            _EmbedDialog(savedLink: link, onOpenAppearance: onOpenAppearance),
      ),
    );
  }
}

class _EmbedDialog extends StatefulWidget {
  final String savedLink;
  final VoidCallback? onOpenAppearance;
  const _EmbedDialog({required this.savedLink, this.onOpenAppearance});

  @override
  State<_EmbedDialog> createState() => _EmbedDialogState();
}

class _EmbedDialogState extends State<_EmbedDialog> {
  bool automatic = true;
  bool hostDataLayer = true;
  bool importEnabled = false;
  final _consentExport = TextEditingController();
  @override
  void dispose() {
    _consentExport.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final importValid =
        parseFormConsentExport(
          _consentExport.text,
          AppConfig.webLink.replaceFirst(RegExp(r'/+$'), ''),
        ) !=
        null;
    final valid = !importEnabled || importValid;
    final code = valid
        ? formEmbedCode(
            tenantUrl: AppConfig.webLink,
            savedLink: widget.savedLink,
            title: FormStrings.embedTitle,
            fallbackLabel: FormStrings.embedFallback,
            automatic: automatic,
            hostDataLayer: hostDataLayer,
            consentExport: importEnabled ? _consentExport.text : null,
          )
        : null;
    final theme = Theme.of(context);
    final hintStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return AppAlertDialog(
      title: Text(FormStrings.embedAction),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(FormStrings.embedHelp),
              const SizedBox(height: 16),
              ExpansionTile(
                key: const ValueKey('embed-display'),
                tilePadding: EdgeInsets.zero,
                title: Text(FormStrings.embedDisplay),
                children: [
                  DropdownButton<bool>(
                    value: automatic,
                    isExpanded: true,
                    items: [
                      DropdownMenuItem(
                        value: true,
                        child: Text(FormStrings.embedAutomatic),
                      ),
                      DropdownMenuItem(
                        value: false,
                        child: Text(FormStrings.embedFixed),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => automatic = value);
                    },
                  ),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(FormStrings.embedScriptHint, style: hintStyle),
                  ),
                  if (widget.onOpenAppearance != null)
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton.icon(
                        key: const ValueKey('embed-open-appearance'),
                        icon: const Icon(Icons.palette_outlined),
                        label: Text(FormStrings.embedOpenAppearance),
                        onPressed: () {
                          Navigator.of(context).pop();
                          widget.onOpenAppearance!();
                        },
                      ),
                    ),
                  const SizedBox(height: 8),
                ],
              ),
              ExpansionTile(
                key: const ValueKey('embed-tracking'),
                tilePadding: EdgeInsets.zero,
                title: Text(FormStrings.embedTracking),
                children: [
                  CheckboxListTile(
                    key: const ValueKey('embed-host-datalayer'),
                    title: Text(FormStrings.embedHostDataLayer),
                    subtitle: Text(
                      hostDataLayer
                          ? FormStrings.embedHostHint
                          : FormStrings.embedOrganizerHint,
                    ),
                    value: hostDataLayer,
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (value) {
                      if (value != null) setState(() => hostDataLayer = value);
                    },
                  ),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      FormStrings.embedConversionHint,
                      style: hintStyle,
                    ),
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    key: const ValueKey('embed-consent-import'),
                    title: Text(FormStrings.cmsEnableImport),
                    value: importEnabled,
                    onChanged: (value) =>
                        setState(() => importEnabled = value == true),
                  ),
                  if (importEnabled) ...[
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        FormStrings.cmsHtmlImportHelp,
                        style: hintStyle,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      key: const ValueKey('embed-consent-export'),
                      controller: _consentExport,
                      minLines: 2,
                      maxLines: 4,
                      maxLength: 16384,
                      decoration: InputDecoration(
                        labelText: FormStrings.cmsImportLabel,
                        errorText: _consentExport.text.isEmpty || importValid
                            ? null
                            : FormStrings.cmsImportInvalid,
                        errorMaxLines: 3,
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ],
                  const SizedBox(height: 8),
                ],
              ),
              if (code != null)
                ExpansionTile(
                  key: const ValueKey('embed-preview'),
                  tilePadding: EdgeInsets.zero,
                  title: Text(FormStrings.embedPreview),
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: SelectableText(
                        code,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
      actions: [
        CopyButton(value: code ?? '', primaryLabel: FormStrings.embedCopy),
      ],
    );
  }
}
