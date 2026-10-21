import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:fstapp/components/forms/views/form_public_link.dart';
import 'occasion_setup_result.dart';
import '../occasion_sale_strings.dart';

enum OccasionSetupNext { list, manage }

class OccasionSetupCompleted extends StatelessWidget {
  final OccasionSetupResult result;
  const OccasionSetupCompleted({super.key, required this.result});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(OccasionSaleStrings.text('created'))),
        body: SafeArea(
            child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
              child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 24),
                  Icon(Icons.check_circle_outline,
                      size: 56, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(height: 20),
                  Text(result.title,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 16),
                  if (result.formLink != null) ...[
                    Text(
                        OccasionSaleStrings.text(
                            'completion.${result.saleMode}'),
                        textAlign: TextAlign.center),
                    const SizedBox(height: 24),
                    Card(
                        child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(OccasionSaleStrings.text('salesLink'),
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium),
                                  const SizedBox(height: 12),
                                  PublicLink(
                                      link: result.formLink!,
                                      savedLink: result.formLink!,
                                      showCopyLabel: true),
                                  const SizedBox(height: 8),
                                  TextButton.icon(
                                      icon: const Icon(Icons.open_in_new),
                                      label: Text(
                                          OccasionSaleStrings.text('openForm')),
                                      onPressed: () => launchUrl(
                                          Uri.parse(
                                              publicLinkUrl(result.formLink!)),
                                          mode:
                                              LaunchMode.externalApplication)),
                                ]))),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                      onPressed: () =>
                          Navigator.of(context).pop(OccasionSetupNext.list),
                      child: Text(OccasionSaleStrings.text('backToList'))),
                  const SizedBox(height: 8),
                  OutlinedButton(
                      onPressed: () =>
                          Navigator.of(context).pop(OccasionSetupNext.manage),
                      child: Text(OccasionSaleStrings.text('manage'))),
                ]),
          )),
        )),
      );
}
