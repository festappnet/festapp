import 'dart:convert';
import 'package:easy_localization/easy_localization.dart';
import 'package:festapp_core/forms.dart';
import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/blueprint/blueprint_seat_order_preview.dart';
import 'package:fstapp/components/blueprint/blueprint_command_rejection.dart';
import 'package:fstapp/components/blueprint/blueprint_strings.dart';
import 'package:fstapp/components/eshop/orders_strings.dart';
import 'package:fstapp/components/eshop/models/order_model.dart';
import 'package:fstapp/components/eshop/seat_order_commands.dart';
import 'package:fstapp/components/forms/models/holder_models/form_holder.dart';
import 'package:fstapp/components/forms/widgets_view/form_helper.dart';
import 'package:fstapp/widgets/app_dialog.dart';

class BlueprintCreateOrderDialog extends StatefulWidget {
  const BlueprintCreateOrderDialog(
      {super.key,
      required this.request,
      required this.commands,
      this.initialRequirements});
  final BlueprintSeatOrderRequest request;
  final SeatOrderCommands commands;
  final BlueprintSeatOrderRequirements? initialRequirements;
  @override
  State<BlueprintCreateOrderDialog> createState() =>
      _BlueprintCreateOrderDialogState();
}

class _BlueprintCreateOrderDialogState
    extends State<BlueprintCreateOrderDialog> {
  final _email = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  BlueprintSeatOrderRequirements? _requirements;
  BlueprintSeatOrderPreview? _preview;
  _OrderFormFields? _customerFields;
  final _ticketFields = <int, _OrderFormFields>{};
  bool _busy = false, _recoveryRequired = false;
  String? _error;
  String _copy(String key) => 'FeatureBlueprint.$key'.tr();
  @override
  void initState() {
    super.initState();
    final requirements = widget.initialRequirements;
    if (requirements != null)
      _accept(requirements);
    else
      _load();
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  void _accept(BlueprintSeatOrderRequirements value) {
    _requirements = value;
    final definitions = value.requiredFields
        .map((row) => FormFieldDefinition.fromJson(
            Map<String, dynamic>.from(jsonDecode(jsonEncode(row)) as Map)))
        .where((f) =>
            f.isRequired == true &&
            f.isHidden != true &&
            !{'ticket', 'spot', 'product_type'}.contains(f.type))
        .toList();
    final customer = definitions
        .where((f) => f.isTicketField != true && f.type != 'email')
        .toList();
    _customerFields = customer.isEmpty
        ? null
        : _OrderFormFields(customer, value.phonePrefixes);
    final ticket = definitions.where((f) => f.isTicketField == true).toList();
    _ticketFields.clear();
    for (final id in value.spotIds)
      if (ticket.isNotEmpty)
        _ticketFields[id] = _OrderFormFields(ticket, value.phonePrefixes);
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final recovered = await widget.commands.recover(widget.request);
      if (!mounted) return;
      if (recovered != null) {
        Navigator.of(context).pop(true);
        return;
      }
      final requirements = await widget.commands.requirements(widget.request);
      if (mounted) setState(() => _accept(requirements));
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Map<String, dynamic>? _input() {
    var valid = _formKey.currentState?.validate() ?? false;
    for (final group in [
      if (_customerFields != null) _customerFields!,
      ..._ticketFields.values
    ]) {
      if (!(group.key.currentState?.saveAndValidate() ?? false)) valid = false;
    }
    if (!valid) return null;
    return {
      'email': _email.text.trim(),
      'form_key': _requirements!.formKey,
      if (_customerFields != null)
        'fields': _customerFields!.values(ticket: false),
      if (_ticketFields.isNotEmpty)
        'ticket_fields': {
          for (final entry in _ticketFields.entries)
            entry.key.toString(): entry.value.values(ticket: true)
        }
    };
  }

  Future<void> _next() async {
    if (_busy) return;
    if (_recoveryRequired) {
      await _recover();
      return;
    }
    final input = _preview == null ? _input() : null;
    if (_preview == null && input == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final approved = _preview;
    try {
      if (approved == null) {
        final preview = await widget.commands.preview(_requirements!, input!);
        if (mounted) setState(() => _preview = preview);
      } else {
        // Once submitted, every ambiguous outcome must resume this original intent.
        _recoveryRequired = true;
        await widget.commands.create(approved);
        if (mounted) Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _recover() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final outcome = await widget.commands.recover(widget.request);
      if (!mounted) return;
      if (outcome != null) {
        Navigator.of(context).pop(true);
        return;
      }
      // A terminal rejection has retired its journal. Require a new quote.
      setState(() {
        _recoveryRequired = false;
        _preview = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _message(Object error) {
    if (error is BlueprintCommandRejection &&
        error.reason == 'REQUIRED_FIELD_MISSING') {
      for (final field
          in _requirements?.requiredFields ?? const <Map<String, dynamic>>[]) {
        if (field['id'] == error.data['fieldId'] && field['title'] is String) {
          return '${CommonStrings.fieldCannotBeEmpty}: ${field['title']}';
        }
      }
      return CommonStrings.fieldCannotBeEmpty;
    }
    if (error is SeatOrderPreparationPending)
      return 'FeatureBlueprint.orderPaymentPending'
          .tr(namedArgs: {'order': '${error.orderId}'});
    if (error is StateError &&
        error.message == 'LEGACY_ORDER_RECOVERY_REQUIRES_ORIGINAL_INPUT')
      return _copy('orderLegacyRecovery');
    return BlueprintStrings.layoutErrorMessage(error);
  }

  Widget _fields(_OrderFormFields fields) => FormBuilder(
      key: fields.key,
      enabled: !_busy && _preview == null,
      child: Column(
          children:
              FormHelper.getAllFormFields(context, fields.key, fields.holder)));
  Widget _conflicts(List<Map<String, dynamic>> groups) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final group in groups) ...[
          const Divider(),
          Text('${_copy('orderLabel')} #${group['orderId']}',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          Text((group['customer'] as Map? ?? const {})
              .values
              .whereType<String>()
              .where((s) => s.isNotEmpty)
              .join(' ')),
          for (final ticket in group['tickets'] as List) ...[
            Text(
                '${CommonStrings.ticket} ${ticket['ticketSymbol'] ?? ticket['ticketId']}'),
            for (final product in ticket['products'] as List)
              Text(
                  '${product['title'] ?? ''} - ${product['amount'] ?? _copy('orderPriceUnavailable')} ${product['currencyCode'] ?? ''}'),
          ],
        ]
      ]);
  Widget _form(BlueprintSeatOrderRequirements requirements) => Form(
      key: _formKey,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final item in requirements.items)
          ListTile(
              dense: true,
              title: Text('${item['title'] ?? item['spotId']}'),
              subtitle: Text('${item['productTitle'] ?? ''}'),
              trailing: Text(item['amount'] == null
                  ? _copy('orderPriceUnavailable')
                  : '${item['amount']} ${item['currencyCode'] ?? ''}')),
        _conflicts(requirements.conflicts),
        TextFormField(
            controller: _email,
            enabled: !_busy && _preview == null,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(labelText: OrdersStrings.gridEmail),
            validator: (value) => value == null || value.isEmpty
                ? CommonStrings.fieldCannotBeEmpty
                : !EmailAddress.isValid(value)
                    ? CommonStrings.invalidFormat
                    : null),
        if (_customerFields != null) _fields(_customerFields!),
        for (final entry in _ticketFields.entries) ...[
          Text('${CommonStrings.ticket} - ${entry.key}'),
          _fields(entry.value)
        ],
      ]));
  Widget _review(BlueprintSeatOrderPreview preview) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_copy('orderReview'),
            style: Theme.of(context).textTheme.titleMedium),
        Text('${OrdersStrings.gridEmail}: ${preview.inputData['email']}'),
        Text(
            '${OrdersStrings.newOrderTotal}: ${preview.newOrderAmount} ${preview.currencyCode}'),
        Text(_copy('orderAffectedSeats')),
        for (final seat in preview.seats)
          ListTile(
              dense: true,
              title: Text(
                  '${seat['title'] ?? seat['spotTitle'] ?? seat['spotId']} - ${seat['blueprintTitle'] ?? ''}'),
              subtitle: Text(
                  '${seat['productTitle'] ?? ''} - ${_state(seat['stateBefore'])} → ${_state(seat['stateAfter'])}')),
        _conflicts(preview.conflicts),
        for (final order in preview.orders)
          Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                  '${_copy('orderLabel')} #${order.orderId}: ${order.beforeAmount} → ${order.afterAmount} ${order.currencyCode} (${order.delta}) - ${OrderModel.stateToLocale(order.beforeState)} → ${OrderModel.stateToLocale(order.afterState)}')),
        if (preview.orders.isNotEmpty) Text(_copy('orderNoAutomaticRefund')),
      ]);
  String _state(Object? state) => switch (state) {
        'available' => BlueprintStrings.swapSummaryAvailable,
        'selected' => BlueprintStrings.swapSummarySelected,
        'ordered' => BlueprintStrings.swapSummaryOccupied,
        'used' => BlueprintStrings.swapSummaryUsed,
        _ => ''
      };
  @override
  Widget build(BuildContext context) => AppAlertDialog(
          onClose: _busy ? null : () => Navigator.of(context).pop(),
          dismissible: !_busy,
          title: Text(BlueprintStrings.legendCreateOrder),
          content: SizedBox(
              width: 620,
              child: SingleChildScrollView(
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    if (_error != null)
                      Semantics(
                          liveRegion: true,
                          child: Text(_error!,
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.error))),
                    if (_requirements != null)
                      Offstage(
                          offstage: _preview != null,
                          child: _form(_requirements!)),
                    if (_preview != null) _review(_preview!),
                    if (_busy) Text(CommonStrings.processing),
                  ]))),
          actions: [
            TextButton(
                onPressed: _busy ? null : () => Navigator.of(context).pop(),
                child: Text(CommonStrings.cancel)),
            if (_preview != null && !_recoveryRequired)
              TextButton(
                  onPressed:
                      _busy ? null : () => setState(() => _preview = null),
                  child: Text(CommonStrings.back)),
            ElevatedButton(
                onPressed: _busy
                    ? null
                    : _requirements == null
                        ? _load
                        : _next,
                child: Text(_recoveryRequired || _requirements == null
                    ? CommonStrings.retry
                    : _preview == null
                        ? _copy('orderReview')
                        : BlueprintStrings.confirmOrder)),
          ]);
}

class _OrderFormFields {
  _OrderFormFields(List<FormFieldDefinition> definitions, Object? prefixes)
      : holder = FormHolder(
            fields: definitions.map(FormHolder.createFieldHolder).toList(),
            isCardDesign: false,
            phonePrefixes:
                prefixes is List ? prefixes.cast<String>() : const []) {
    holder.controller = FormHolderController(globalKey: key);
  }
  final key = GlobalKey<FormBuilderState>();
  final FormHolder holder;
  List<Map<String, dynamic>> values({required bool ticket}) => [
        for (final field in holder.fields)
          {
            field.id.toString(): FormHelper.getFieldData(key, field),
            if (ticket) field.fieldType: FormHelper.getFieldData(key, field),
          },
      ];
}
