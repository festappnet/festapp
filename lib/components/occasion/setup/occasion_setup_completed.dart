import 'package:flutter/material.dart';
import '../db_occasions.dart';
import 'package:fstapp/services/exception_handler.dart';
import 'occasion_setup_strings.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:fstapp/components/forms/views/form_public_link.dart';
import 'occasion_setup_result.dart';
import '../occasion_sale_strings.dart';

enum OccasionSetupNext { list, manage }

class OccasionSetupCompleted extends StatefulWidget {
  final OccasionSetupResult result;
  const OccasionSetupCompleted({super.key, required this.result});
  @override
  State<OccasionSetupCompleted> createState() => _OccasionSetupCompletedState();
}

class _OccasionSetupCompletedState extends State<OccasionSetupCompleted> {
  bool _publishing = false, _published = false;
  OccasionSetupResult get result => widget.result;
  Future<void> _publish() async {
    setState(() => _publishing = true);
    final success =
        await ExceptionHandler.guardVoid(context, futureFunction: () async {
      final occasion = await DbOccasions.getOccasion(result.occasionId);
      occasion.isOpen = true;
      occasion.isHidden = occasion.data?['setup_listing_intent'] == false;
      await DbOccasions.updateOccasion(occasion);
    });
    if (mounted)
      setState(() {
        _publishing = false;
        _published = success;
      });
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_publishing,
      child: Scaffold(
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
                        OccasionSaleStrings.domainText(
                            result.hasTickets, 'completion.${result.saleMode}'),
                        textAlign: TextAlign.center),
                    const SizedBox(height: 24),
                    Card(
                        child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                      OccasionSaleStrings.domainText(
                                          result.hasTickets, 'salesLink'),
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
                  if (!_published)
                    FilledButton(
                        onPressed: _publishing ? null : _publish,
                        child:
                            Text(OccasionSetupStrings.story('publishEvent'))),
                  if (_published)
                    Text(OccasionSetupStrings.story('publishedEvent')),
                  const SizedBox(height: 8),
                  FilledButton(
                      onPressed: _publishing
                          ? null
                          : () =>
                              Navigator.of(context).pop(OccasionSetupNext.list),
                      child: Text(OccasionSaleStrings.text('backToList'))),
                  const SizedBox(height: 8),
                  OutlinedButton(
                      onPressed: _publishing
                          ? null
                          : () => Navigator.of(context)
                              .pop(OccasionSetupNext.manage),
                      child: Text(OccasionSaleStrings.text('manage'))),
                ]),
          )),
        )),
      ));
}
