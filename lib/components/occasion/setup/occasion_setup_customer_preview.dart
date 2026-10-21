import 'dart:convert';
import 'package:easy_localization/easy_localization.dart';
import 'package:festapp_core/email_templates.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:fstapp/components/email_templates/db_email_templates.dart';
import 'package:fstapp/components/email_templates/email_preview_examples.dart';
import 'package:fstapp/components/email_templates/email_preview_html.dart';
import 'package:fstapp/components/forms/form_session.dart';
import 'package:fstapp/components/forms/models/holder_models/form_holder.dart';
import 'package:fstapp/components/forms/widgets_view/form_helper.dart';
import 'package:fstapp/components/html/html_view.dart';
import 'package:fstapp/services/utilities_all.dart';
import '../occasion_sale_strings.dart';
import 'occasion_form_draft.dart';
import 'occasion_setup_story.dart';

/// Uses the customer fields and pricing session without checkout, persistence,
/// reservation callbacks or a public URL. Its copy is isolated from the draft.
class OccasionSetupCustomerPreview extends StatefulWidget {
  const OccasionSetupCustomerPreview(
      {super.key, required this.data, required this.unitId});
  final Map<String, dynamic> data;
  final int unitId;
  @override
  State<OccasionSetupCustomerPreview> createState() => _CustomerPreviewState();
}

class _CustomerPreviewState extends State<OccasionSetupCustomerPreview> {
  final _key = GlobalKey<FormBuilderState>();
  late final _bundle = draftFormBundle(Map<String, dynamic>.from(
      jsonDecode(jsonEncode(widget.data['formDraft']))));
  late final _holder = FormHolder.fromDefinition(_bundle.form.freeze());
  late final _session = FormSession(
      form: _bundle.form.toBundle(), formHolder: _holder, formKey: _key);
  late final _emails = _loadEmails();

  @override
  void initState() {
    super.initState();
    _holder.controller = FormHolderController(
      demoSimulation: true,
      globalKey: _key,
      updateTotalPrice: _session.recalculateTotals,
      // Seat selection in a draft must never acquire holds on a source event.
      showSeatReservation: (_) async => null,
    );
    _session.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _session.removeListener(_changed);
    _session.dispose();
    super.dispose();
  }

  Future<List<Widget>> _loadEmails() async {
    final source = widget.data['copyEmails'] == true
        ? widget.data['sourceId'] as int?
        : null;
    final scope =
        await DbEmailTemplates.getEntityEmailTemplates(unitId: widget.unitId);
    final templates = {
      for (final template in scope.templates) template.code: template
    };
    if (source != null) {
      final copied =
          await DbEmailTemplates.getEntityEmailTemplates(occasionId: source);
      for (final template
          in copied.templates.where((t) => t.occasion == source)) {
        templates[template.code] = template;
      }
    }
    final authoring = await DbEmailTemplates.getAuthoringContext(
        scope, 'TICKET_ORDER_CONFIRMATION');
    final raw = jsonDecode(await rootBundle
            .loadString('assets/email_templates/preview_examples.json'))
        as Map<String, dynamic>;
    final examples = EmailPreviewExamples.fromJson(raw,
        context: EmailPreviewContext(
          occasionTitle: widget.data['title'] as String?,
          ticketsEnabled: OccasionSetupStory.hasTickets(widget.data),
          products: [
            for (final product in _bundle.products)
              if (product.isHidden != true)
                EmailPreviewProduct(
                    title: product.title ?? '',
                    typeTitle: product.productTypeTitleString ?? '',
                    price: (product.price ?? 0).toDouble(),
                    currency: product.currencyCode ?? 'CZK')
          ],
        ));
    if (!mounted) return [];
    final locale = context.locale.languageCode;
    final defaults = widget.data['communicationDefaults'] as Map? ?? {};
    final tone = widget.data['communicationTone'] == 'inherit'
        ? defaults['tone'] ?? 'formal'
        : widget.data['communicationTone'] ?? 'formal';
    final result = <Widget>[];
    for (final code in [
      'TICKET_ORDER_CONFIRMATION',
      'TICKET_ORDER_PAYMENT_DONE'
    ]) {
      final template = templates[code];
      if (template == null) continue;
      final scenarios = examples.scenariosFor(code,
          paymentAccounts: authoring.paymentAccounts);
      final scenario = scenarios
          .where((s) =>
              s.locale == locale &&
              s.tone == tone &&
              s.scenario ==
                  (OccasionSetupStory.hasPaidProducts(widget.data)
                      ? (code == 'TICKET_ORDER_CONFIRMATION'
                          ? 'unpaid'
                          : 'paid')
                      : 'zero'))
          .firstOrNull;
      if (scenario == null) continue;
      result.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: EmailReceivedMessage(
              senderAddress: authoring.senderAddress,
              subject: scenario.composeSubject(template.subject ?? ''),
              html: authoring.composeHtml(scenario, template.html ?? ''),
              allowedRemoteImageSources: authoring.bannerImageSources)));
    }
    if (result.isEmpty) throw StateError('Preview examples unavailable');
    return result;
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(OccasionSaleStrings.text('previewSafe')),
          if (_bundle.form.usesSeatSelection) ...[
            const SizedBox(height: 12),
            Text(OccasionSaleStrings.text('previewSeats')),
          ],
          const SizedBox(height: 20),
          FormBuilder(
              key: _key,
              child: Column(children: [
                if (_bundle.form.definition.header?.isNotEmpty == true)
                  HtmlView(html: _bundle.form.definition.header!),
                ...FormHelper.getAllFormFields(context, _key, _holder),
              ])),
          const SizedBox(height: 12),
          Text(OccasionSaleStrings.text('previewTotal', {
            'amount': Utilities.formatPrice(context, _session.totalPrice,
                currencyCode: _session.currencyCode)
          })),
          const Divider(height: 40),
          Text(OccasionSaleStrings.text('previewEmail'),
              style: Theme.of(context).textTheme.titleMedium),
          Text(OccasionSaleStrings.text('previewEmailSample')),
          FutureBuilder<List<Widget>>(
              future: _emails,
              builder: (context, state) {
                if (state.hasError)
                  return Padding(
                      padding: const EdgeInsets.all(12),
                      child:
                          Text(OccasionSaleStrings.text('previewUnavailable')));
                if (!state.hasData) return const LinearProgressIndicator();
                return Column(children: state.data!);
              }),
        ]),
      );
}
