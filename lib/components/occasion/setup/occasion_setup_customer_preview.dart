import 'dart:convert';
import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:fstapp/components/email_templates/email_preview_html.dart';
import 'package:fstapp/components/forms/form_session.dart';
import 'package:fstapp/components/forms/models/holder_models/form_holder.dart';
import 'package:fstapp/components/forms/widgets_view/form_helper.dart';
import 'package:fstapp/components/html/html_view.dart';
import 'package:fstapp/services/utilities_all.dart';
import '../occasion_sale_strings.dart';
import 'occasion_form_draft.dart';
import 'occasion_setup_seat_preview.dart';
import 'blueprint_setup_layout_draft.dart';
import 'package:fstapp/components/blueprint/blueprint_layout_contract.dart';
import 'package:fstapp/components/forms/models/holder_models/ticket_holder.dart';
import 'package:festapp_core/forms.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fstapp/components/_shared/common_strings.dart';

/// Uses the customer fields and pricing session without checkout, persistence,
/// reservation callbacks or a public URL. Its copy is isolated from the draft.
class OccasionSetupCustomerPreview extends StatefulWidget {
  const OccasionSetupCustomerPreview(
      {super.key,
      required this.data,
      required this.unitId,
      required this.draftId,
      this.loadBlueprintResources,
      this.emailLoader});
  final Map<String, dynamic> data;
  final int unitId;
  final String draftId;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic>)?
      emailLoader;
  final Future<Map<String, dynamic>> Function()? loadBlueprintResources;
  @override
  State<OccasionSetupCustomerPreview> createState() => _CustomerPreviewState();
}

class _CustomerPreviewState extends State<OccasionSetupCustomerPreview> {
  final _key = GlobalKey<FormBuilderState>();
  late final _bundle = () {
    final data = Map<String, dynamic>.from(
        jsonDecode(jsonEncode(widget.data['formDraft'])));
    final fields = (data['fields'] as List? ?? []).cast<Map>();
    final used = fields.map((f) => f['id']).whereType<int>().toSet();
    var next = -1;
    for (final field in fields) {
      if (field['id'] != null) continue;
      while (used.contains(next)) {
        next--;
      }
      field['id'] = next;
      used.add(next--);
    }
    return draftFormBundle(data);
  }();
  late final _holder = FormHolder.fromDefinition(_bundle.form.freeze());
  late final _session = FormSession(
      form: _bundle.form.toBundle(), formHolder: _holder, formKey: _key);
  Future<List<Widget>>? _emails;

  @override
  void initState() {
    super.initState();
    _holder.controller = FormHolderController(
      demoSimulation: true,
      globalKey: _key,
      updateTotalPrice: _session.recalculateTotals,
      showSeatReservation: (selected) async {
        final raw = widget.data['blueprintLayoutDraft'];
        if (raw is! Map || widget.loadBlueprintResources == null) return null;
        final result = await showDialog<OccasionSetupSeatSelection>(
            context: context,
            builder: (_) => OccasionSetupSeatPreview(
                  draft: BlueprintSetupLayoutDraft.fromJson(
                      Map<String, dynamic>.from(raw)),
                  products: _bundle.products,
                  maximum: _holder.getTicket()?.maxTickets ?? 1,
                  quantities: {
                    for (final area in raw['areaBindings'] as List? ?? [])
                      area['nodeId'] as String:
                          _session.areaQuantity(area['nodeId'] as String)
                  },
                  selected: selected,
                  loadResources: widget.loadBlueprintResources!,
                ));
        if (!mounted || result == null) return null;
        _session.updateSeats(result.seats);
        for (final area in (raw['areaBindings'] as List? ?? [])) {
          final binding =
              BlueprintAreaBinding.fromJson(Map<String, dynamic>.from(area));
          _session.setAreaQuantity(
              binding, result.quantities[binding.nodeId] ?? 0,
              available: area['capacity'] as int? ?? 0,
              product: _bundle.products
                  .where((p) => p.id == binding.productId)
                  .firstOrNull);
        }
        return result.seats;
      },
    );
    _session.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() => _emails = null);
  }

  @override
  void dispose() {
    _session.removeListener(_changed);
    _session.dispose();
    super.dispose();
  }

  Future<List<Widget>> _loadEmails() async {
    List<int> ids(dynamic value) {
      if (value is FormOptionProductModel) return [int.parse(value.id)];
      if (value is Iterable) return value.expand(ids).toList();
      return [];
    }

    final tickets = <Map<String, dynamic>>[];
    final fields = <String, String>{};
    final extras = <int>[];
    for (final field in _holder.fields) {
      if (field is TicketHolder) {
        for (final ticket in field.tickets) {
          final selected = <int>[
            if (ticket.seat?.seat?.product?.id != null)
              ticket.seat!.seat!.product!.id!,
            for (final entry in ticket.ticketValues)
              if (entry.fieldType == FormMetadata.fieldTypeProductType)
                ...ids(entry.getValue(ticket.ticketKey) ??
                    ticket.productDefaults[entry.id]),
          ];
          tickets.add({
            'products': selected,
            if (ticket.seat != null)
              'seat': {
                'group': ticket.seat!.seat?.group?.title ?? '',
                'title': ticket.seat!.seat?.title ?? ''
              }
          });
        }
      } else {
        final value = field.getValue(_key);
        if (field.fieldType == FormMetadata.fieldTypeProductType)
          extras.addAll(ids(value));
        if (['name', 'surname', 'email', 'phone', 'note']
                .contains(field.fieldType) &&
            value is String) fields[field.fieldType] = value;
      }
    }
    if (extras.isNotEmpty) tickets.add({'products': extras});
    final input = <String, dynamic>{
      'action': 'setupPreview',
      'draftId': widget.draftId,
      'locale': context.locale.languageCode,
      'tickets': tickets,
      'fields': fields
    };
    final result = widget.emailLoader != null
        ? await widget.emailLoader!(input)
        : Map<String, dynamic>.from((await Supabase.instance.client.functions
                .invoke('send-custom-email', body: input))
            .data as Map);
    return [
      for (final message in result['messages'] as List)
        Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: EmailReceivedMessage(
                recipientLabel: fields['email']?.isNotEmpty == true
                    ? fields['email']
                    : 'preview@example.invalid',
                senderAddress: message['senderAddress'],
                subject: message['subject'],
                html: message['html']))
    ];
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(OccasionSaleStrings.text('previewSafe')),
          const SizedBox(height: 20),
          FormBuilder(
              key: _key,
              onChanged: _changed,
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
          Text(OccasionSaleStrings.text('previewEmailSelection')),
          OutlinedButton.icon(
            onPressed: () {
              final request = _loadEmails();
              request.ignore();
              setState(() {
                _emails = request;
              });
            },
            icon: const Icon(Icons.email_outlined),
            label: Text(_emails == null
                ? OccasionSaleStrings.text('previewSelectedEmails')
                : CommonStrings.retry),
          ),
          if (_emails != null)
            FutureBuilder<List<Widget>>(
                future: _emails,
                builder: (context, state) {
                  if (state.hasError)
                    return Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                            OccasionSaleStrings.text('previewUnavailable')));
                  if (!state.hasData) return const LinearProgressIndicator();
                  return Column(children: state.data!);
                }),
        ]),
      );
}
