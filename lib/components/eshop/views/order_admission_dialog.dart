import 'package:festapp_core/eshop.dart';
import 'package:festapp_core/forms.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:material_ui/material_ui.dart';
import 'package:uuid/uuid.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../../_shared/common_strings.dart';
import '../../blueprint/seating_strings.dart';
import '../../forms/models/holder_models/form_holder.dart';
import '../../forms/models/holder_models/id_document_data.dart'
    show IdDocumentData;
import '../../forms/widgets_view/form_helper.dart';
import '../models/order_admin_detail.dart';
import '../order_detail_strings.dart';
import '../orders_strings.dart';
import '../../../widgets/app_dialog.dart';

class OrderAdmissionDialog extends StatefulWidget {
  const OrderAdmissionDialog({
    super.key,
    required this.orderId,
    this.ticketId,
    required this.ticketTerminology,
    required this.title,
    required this.currency,
    required this.rpc,
    required this.canWrite,
    required this.money,
  });

  final int orderId;
  final int? ticketId;
  final bool ticketTerminology;
  final String title, currency;
  final String Function(dynamic) money;
  final bool Function() canWrite;
  final Future<dynamic> Function(String, Map<String, dynamic>) rpc;
  @override
  State<OrderAdmissionDialog> createState() => _OrderAdmissionDialogState();
}

class _OrderAdmissionDialogState extends State<OrderAdmissionDialog> {
  bool _busy = true, _reloadRequired = false, _uncertain = false;
  List<Map<String, dynamic>> _options = [], _fields = [];
  Map<String, dynamic>? _selected, _preview;
  List<FormHolder> _forms = [];
  List<dynamic> _answers = [];
  String? _error, _command;

  Map<String, dynamic> get _scope => {
    'p_order_id': widget.orderId,
    'p_ticket_id': widget.ticketId,
  };
  bool get _adding => widget.ticketId == null;
  int get _quantity => _selected?['quantity'] as int? ?? 1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _select(Map<String, dynamic>? target) {
    _selected = target;
    final previous = _forms;
    _forms = !_adding || target == null
        ? []
        : List.generate(
            _quantity,
            (i) => i < previous.length ? previous[i] : _visitorForm(),
          );
  }

  FormHolder _visitorForm() {
    final form = FormHolder(
      isCardDesign: false,
      fields: [
        for (final field in _fields)
          FormHolder.createFieldHolder(
            FormFieldDefinition(
              id: field['id'],
              type: field['type'],
              title: field['title'],
              isRequired: field['required'] == true,
              data: {
                ...detailMap(field['data']),
                if (['select_one', 'select_many'].contains(field['type']) &&
                    field['options'] != null)
                  'options': [
                    for (final opt in detailRows(field['options']))
                      {'value': opt['title'] ?? opt['value']},
                  ],
              },
              productType: field['type'] == 'product_type'
                  ? ProductTypeModel(
                      title: field['title'],
                      products: [
                        for (final opt in detailRows(field['options']))
                          ProductModel.fromJson({
                            ...opt,
                            'id': opt['productId'],
                            'currency_code':
                                opt['currency_code'] ?? widget.currency,
                          }),
                      ],
                    )
                  : null,
            ),
          ),
      ],
    );
    form.controller = FormHolderController(
      globalKey: GlobalKey<FormBuilderState>(),
    )..currencyCode = widget.currency;
    return form;
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
      _reloadRequired = false;
    });
    try {
      final data = await _call('get_order_admission_options_v1', _scope);
      if (!mounted) return;
      _fields = detailRows(data['fields']);
      _options = detailRows(data['options']);
      _forms = [];
      _select(_options.length == 1 ? _options.first : null);
    } catch (error) {
      _reloadRequired = true;
      _error = _message(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> params,
  ) async {
    if (!widget.canWrite()) throw const _RejectedAdmission(403, 'FORBIDDEN');
    final dynamic result;
    try {
      result = await widget
          .rpc(name, params)
          .timeout(const Duration(seconds: 30));
    } on PostgrestException catch (error) {
      if (error.code == '42501')
        throw const _RejectedAdmission(403, 'FORBIDDEN');
      rethrow;
    }
    if (result is! Map || result['code'] is! int) throw const FormatException();
    if (result['code'] != 200)
      throw _RejectedAdmission(
        result['code'],
        (result['data']?['reason'] ?? result['reason'])?.toString(),
      );
    if (result['data'] is! Map) throw const FormatException();
    return detailMap(result['data']);
  }

  String _message(Object error) {
    if (error is _RejectedAdmission) {
      if (error.code == 403) return SeatingStrings.reason('FORBIDDEN');
      final reason = error.reason;
      final message = switch (reason) {
        'INVALID_EMAIL' => FormHelper.emailInvalidMessage(),
        'INVENTORY_CONFLICT' ||
        'SEAT_UNAVAILABLE' ||
        'HOLD_ACTIVE' ||
        'ADMISSION_SOURCE_REQUIRES_SEATING' ||
        'USED_TICKET_PROTECTED' ||
        'BATCH_TICKET_PRINT_IMMUTABLE' ||
        'ADMISSION_DATA_AMBIGUOUS' => SeatingStrings.reason(reason!),
        'BLUEPRINT_SEAT_UNAVAILABLE' => SeatingStrings.reason(
          'SEAT_UNAVAILABLE',
        ),
        'BLUEPRINT_INCOMPLETE_SELECTION_UNIT' => SeatingStrings.reason(
          'ATOMIC_UNIT_INCOMPLETE',
        ),
        'PRODUCT_CAPACITY_EXCEEDED' ||
        'FORM_CAPACITY_EXCEEDED' => OrderDetailStrings.text('admission_full'),
        'REQUIRED_FIELD_MISSING' => CommonStrings.fieldCannotBeEmpty,
        'PAYMENT_ACCOUNT_NOT_CONFIGURED' ||
        'PAYMENT_METHOD_POLICY_DISABLED' ||
        'ORDER_ADMISSION_DEPOSIT_UNSUPPORTED' ||
        'STRIPE_ORDER_PRICE_IMMUTABLE' ||
        'DISCOUNTED_ORDER_PRICE_IMMUTABLE' => OrderDetailStrings.text(
          'admission_finance_locked',
        ),
        _ => null,
      };
      return message ?? OrderDetailStrings.text('admission_conflict');
    }
    return _uncertain
        ? SeatingStrings.text('recoveryFailed')
        : SeatingStrings.text('UNAVAILABLE');
  }

  List<Map<String, dynamic>> _visitorAnswers(FormHolder form) {
    final rows = <Map<String, dynamic>>[];
    for (final field in form.fields) {
      final raw = FormHelper.getFieldData(form.controller!.globalKey, field);
      for (var value in (raw is List ? raw : [raw])) {
        if (value is FormOptionDefinition) value = value.toJson();
        if (value is IdDocumentData) value = value.toJson();
        if (value == null || value == '') continue;
        if (field.fieldType == 'product_type')
          value = int.parse(value.toString());
        rows.add({'_subFieldId': field.id.toString(), field.fieldType: value});
      }
    }
    return rows;
  }

  Future<void> _submit() async {
    if (_busy || _selected == null) return;
    final confirming = _preview != null;
    if (!confirming) {
      for (final form in _forms) {
        final key = form.controller!.globalKey;
        if (key.currentState?.saveAndValidate() != true) {
          await FormHelper.scrollToInvalidField(key);
          return;
        }
      }
      final visitors = _forms.map(_visitorAnswers).toList();
      _answers = visitors.length == 1 ? visitors.first : visitors;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await _call(
        confirming
            ? 'confirm_order_admission_change_v1'
            : 'preview_order_admission_change_v1',
        {
          ..._scope,
          'p_target': {
            'productId': _selected!['productId'],
            'spotId': _selected!['spotId'],
          },
          'p_answers': _answers,
          if (confirming) ...{
            'p_fingerprint': _preview!['fingerprint'],
            'p_command_id': _command,
          },
        },
      );
      if (!mounted) return;
      if (confirming) {
        Navigator.pop(context, true);
      } else {
        if (data['fingerprint'] is! String ||
            data['targetTitle'] is! String ||
            data['ticketCount'] is! int ||
            data['quantity'] != _quantity ||
            data['priceDelta'] == null ||
            data['total'] == null ||
            data['balance'] == null ||
            (!_adding && data['sourceTitle'] is! String))
          throw const FormatException();
        _preview = data;
        _command = const Uuid().v4();
      }
    } catch (error) {
      if (!mounted) return;
      if (error is _RejectedAdmission) {
        _uncertain = false;
        _preview = null;
        _command = null;
        _reloadRequired = !{
          'REQUIRED_FIELD_MISSING',
          'INVALID_EMAIL',
          'FORM_FIELD_VALUE_CONFLICT',
        }.contains(error.reason);
      } else if (confirming) {
        _uncertain = true;
      }
      _error = _message(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _count(int n) => OrderDetailStrings.count(
    widget.ticketTerminology ? 'tickets_count' : 'applications_count',
    n,
  );

  Widget _review(Map<String, dynamic> data) {
    final balance = num.parse(data['balance'].toString());
    final rows = [
      if (!_adding)
        (
          OrderDetailStrings.text('old_admission'),
          data['sourceTitle'].toString(),
        ),
      (
        OrderDetailStrings.text('new_admission'),
        data['targetTitle'].toString(),
      ),
      (OrderDetailStrings.text('contents'), _count(data['ticketCount'])),
      (OrdersStrings.priceChange, widget.money(data['priceDelta'])),
      (OrderDetailStrings.text('order_new_total'), widget.money(data['total'])),
      (
        OrderDetailStrings.text(balance < 0 ? 'preplatek' : 'zbyva_k_uhrade'),
        widget.money(balance.abs()),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!_adding) Text(OrderDetailStrings.text('move_reservation_hint')),
        if (_quantity > 1)
          Text(
            '${OrderDetailStrings.text('whole_unit')} · ${_count(_quantity)}',
          ),
        for (final (label, value) in rows)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(label),
            subtitle: Text(value),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final review = _preview;
    return PopScope(
      canPop: !_busy && !_uncertain,
      child: AppAlertDialog(
        title: Text(widget.title),
        dismissible: !_busy && !_uncertain,
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_busy) const LinearProgressIndicator(),
                if (_error != null)
                  Semantics(liveRegion: true, child: Text(_error!)),
                if (review != null) _review(review),
                if (_options.isEmpty && !_busy && _error == null)
                  Text(OrderDetailStrings.text('no_admission_targets')),
                if (_options.isNotEmpty && !_reloadRequired)
                  Offstage(
                    offstage: review != null,
                    child: IgnorePointer(
                      ignoring: _busy || review != null,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          DropdownButtonFormField<Map<String, dynamic>>(
                            initialValue: _selected,
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: OrderDetailStrings.text(
                                'new_admission',
                              ),
                            ),
                            items: [
                              for (final target in _options)
                                DropdownMenuItem(
                                  value: target,
                                  child: Text(
                                    target['title'].toString(),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: (target) =>
                                setState(() => _select(target)),
                          ),

                          for (var i = 0; i < _forms.length; i++) ...[
                            if (_forms.length > 1 && _fields.isNotEmpty)
                              Text(
                                '${OrderDetailStrings.text(widget.ticketTerminology ? 'ticket' : 'application')} ${i + 1}',
                              ),
                            FormBuilder(
                              key: _forms[i].controller!.globalKey,
                              child: Column(
                                children: FormHelper.getAllFormFields(
                                  context,
                                  _forms[i].controller!.globalKey,
                                  _forms[i],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          if (!_uncertain)
            TextButton(
              onPressed: _busy ? null : () => Navigator.pop(context),
              child: Text(CommonStrings.cancel),
            ),
          if (review != null && !_uncertain)
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _preview = null;
                      _command = null;
                    }),
              child: Text(CommonStrings.back),
            ),
          if (_reloadRequired)
            FilledButton(
              onPressed: _busy ? null : _load,
              child: Text(CommonStrings.retry),
            )
          else if (_options.isNotEmpty)
            FilledButton(
              onPressed: _busy || _selected == null ? null : _submit,
              child: Text(
                _uncertain
                    ? SeatingStrings.text('recover')
                    : review == null
                    ? OrderDetailStrings.text('review_admission')
                    : _quantity > 1 && _adding
                    ? '${OrderDetailStrings.text('confirm_whole_unit')} (${_count(_quantity)})'
                    : widget.title,
              ),
            ),
        ],
      ),
    );
  }
}

class _RejectedAdmission implements Exception {
  const _RejectedAdmission(this.code, this.reason);
  final int code;
  final String? reason;
}
