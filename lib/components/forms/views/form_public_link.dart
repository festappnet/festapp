import 'package:flutter/material.dart';
import 'package:url_launcher/link.dart';
import 'package:fstapp/app_config.dart';
import '../../_shared/copy_button.dart';
import '../form_strings.dart';

/// Public form address shared by creation and settings, with clipboard feedback.
class FormPublicLink extends StatelessWidget {
  final String link;
  const FormPublicLink({super.key, required this.link});

  @override
  Widget build(BuildContext context) {
    if (link.isEmpty) return const SizedBox.shrink();
    final url = '${AppConfig.webLink}/form/$link';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${FormStrings.formAvailableAt}:', style: const TextStyle(fontSize: 12)),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Flexible(child: Link(
            uri: Uri.parse(url),
            target: LinkTarget.blank,
            builder: (context, followLink) => InkWell(
              onTap: followLink,
              child: Text(url, style: TextStyle(fontSize: 12,
                  color: Theme.of(context).colorScheme.primary,
                  decoration: TextDecoration.underline)),
            ),
          )),
          const SizedBox(width: 2),
          CopyButton(value: url),
        ]),
      ],
    );
  }
}
