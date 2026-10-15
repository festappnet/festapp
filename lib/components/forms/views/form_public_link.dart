import 'package:flutter/material.dart';
import 'package:fstapp/app_config.dart';
import '../../_shared/copy_button.dart';
import '../form_strings.dart';

/// Only newly entered or changed slugs use this format. Legacy values stay exact.
bool isValidPublicSlug(String value, {bool allowEmpty = false}) =>
    (allowEmpty && value.isEmpty) ||
    (value.length <= 80 &&
        RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$').hasMatch(value));

String publicLinkUrl(String link, {bool isForm = true}) =>
    '${AppConfig.webLink}/${isForm ? 'form/' : ''}${Uri.encodeComponent(link)}${isForm ? '' : '/event'}';

/// Draft addresses are plain text; only the independently saved baseline copies.
class PublicLink extends StatelessWidget {
  final String link;
  final String? savedLink;
  final bool isForm;
  const PublicLink({super.key, required this.link, this.savedLink,
    this.isForm = true});

  @override
  Widget build(BuildContext context) {
    final saved = savedLink;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (saved != null && saved.isNotEmpty) ...[
        Text(FormStrings.savedPublicLink, style: const TextStyle(fontSize: 12)),
        Row(children: [
          Expanded(child: SelectableText(publicLinkUrl(saved, isForm: isForm))),
          CopyButton(value: publicLinkUrl(saved, isForm: isForm)),
        ]),
      ],
      if (link != saved) ...[
        Text(link.isEmpty ? FormStrings.automaticPublicLink : FormStrings.publicLinkPreview,
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
  Widget build(BuildContext context) => PublicLink(link: link, savedLink: savedLink);
}
