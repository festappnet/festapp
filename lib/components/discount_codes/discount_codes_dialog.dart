import 'package:festapp_core/formatting.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:fstapp/app_config.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fstapp/widgets/app_dialog.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/components/features/feature_service.dart';
import 'package:fstapp/components/features/feature_constants.dart';
import 'package:fstapp/components/eshop/models/product_edit_bundle.dart';
import 'package:fstapp/services/utilities_all.dart';
import 'package:fstapp/services/time_helper.dart';

import 'discount_strings.dart';

class DiscountCodesDialog extends StatefulWidget {
  const DiscountCodesDialog({
    super.key,
    required this.occasion,
    required this.bundle,
  });
  final int occasion;
  final ProductsEditBundle bundle;
  @override
  State<DiscountCodesDialog> createState() => _DiscountCodesDialogState();
}

class _DiscountCodesDialogState extends State<DiscountCodesDialog> {
  List<Map<String, dynamic>>? rows;
  String? error;
  bool busy = false;
  bool get enabled =>
      FeatureService.isFeatureEnabled(FeatureConstants.discountCodes);
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final value = await Supabase.instance.client.rpc(
        'list_discount_codes',
        params: {'p_occasion': widget.occasion},
      );
      if (mounted) {
        setState(() {
          rows = (value as List)
              .map((r) => Map<String, dynamic>.from(r))
              .toList();
          error = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => error = DiscountStrings.text('invalid'));
    }
  }

  Future<void> edit([Map<String, dynamic>? row]) async {
    await showDialog<bool>(
      context: context,
      builder: (_) => _DiscountEditor(
        occasion: widget.occasion,
        bundle: widget.bundle,
        row: row,
      ),
    );
    if (mounted) await load();
  }

  @override
  Widget build(BuildContext context) => AppDialog.fullscreen(
    dismissible: !busy,
    child: Scaffold(
      appBar: AppDialogAppBar(
        title: Text(DiscountStrings.text('title')),
        onClose: () => Navigator.pop(context),
        closeEnabled: !busy,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            if (!enabled) Text(DiscountStrings.text('paused')),
            Text(DiscountStrings.text('restriction')),
            TextButton(
              onPressed: () => launchUrl(
                Uri.parse(
                  '${AppConfig.webLink}${context.locale.languageCode == 'cs' ? '/napoveda/ceny-a-kapacity/#slevove-kody' : '/help/ticket-prices-capacity/#discount-codes'}',
                ),
              ),
              child: Text(DiscountStrings.text('help')),
            ),
            if (RightsService.canUpdateOrders() && enabled)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => edit(),
                  child: Text(DiscountStrings.text('create')),
                ),
              ),
            if (error != null) TextButton(onPressed: load, child: Text(error!)),
            if (rows == null && error == null)
              const Center(child: CircularProgressIndicator()),
            for (final row in rows ?? <Map<String, dynamic>>[])
              ListTile(
                title: Text(row['normalized_code']),
                subtitle: Text(
                  '${row['kind'] == 'percent' ? '${formatDisplayNumber((row['value'] as num) / 100, locale: context.locale.toLanguageTag())} %' : Utilities.formatPrice(context, (row['value'] as num).toDouble(), currencyCode: row['currency_code'], decimalDigits: 2)} · ${DiscountStrings.text('uses')}: ${row['uses'] == null ? '-' : formatDisplayNumber(row['uses'] as num, locale: context.locale.toLanguageTag())} / ${row['usage_limit'] == null ? '∞' : formatDisplayNumber(row['usage_limit'] as num, locale: context.locale.toLanguageTag())}\n${DiscountStrings.text('history')}: ${(row['discountTotals'] as Map? ?? {}).entries.map((e) => Utilities.formatPrice(context, (e.value as num).toDouble(), currencyCode: e.key.toString(), decimalDigits: 2)).join(', ')}',
                ),
                trailing: Text(
                  row['is_active'] == true && enabled
                      ? DiscountStrings.text('active')
                      : DiscountStrings.text('inactive'),
                ),
                onTap: RightsService.canUpdateOrders() ? () => edit(row) : null,
              ),
          ],
        ),
      ),
    ),
  );
}

class _DiscountEditor extends StatefulWidget {
  const _DiscountEditor({
    required this.occasion,
    required this.bundle,
    this.row,
  });
  final int occasion;
  final ProductsEditBundle bundle;
  final Map<String, dynamic>? row;
  @override
  State<_DiscountEditor> createState() => _DiscountEditorState();
}

class _DiscountEditorState extends State<_DiscountEditor> {
  final formKey = GlobalKey<FormState>();
  late final TextEditingController code, value, currency, limit;
  late String kind;
  late bool active;
  late Set<int> forms, products;
  DateTime? from, until;
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    final r = widget.row;
    kind = r?['kind'] ?? 'percent';
    active = r?['is_active'] ?? false;
    code = TextEditingController(text: r?['normalized_code'] ?? '');
    value = TextEditingController(
      text: r == null
          ? ''
          : '${kind == 'percent' ? (r['value'] as num) / 100 : r['value']}',
    );
    currency = TextEditingController(text: r?['currency_code'] ?? 'CZK');
    limit = TextEditingController(text: r?['usage_limit']?.toString() ?? '');
    forms = Set<int>.from(r?['form_ids'] ?? []);
    products = Set<int>.from(r?['product_ids'] ?? []);
    from = DateTime.tryParse(r?['valid_from'] ?? '')?.toOccasionTime();
    until = DateTime.tryParse(r?['valid_until'] ?? '')?.toOccasionTime();
  }

  @override
  void dispose() {
    for (final c in [code, value, currency, limit]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> date(bool start) async {
    final current = (start ? from : until) ?? TimeHelper.now();
    final d = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (t == null || !mounted) return;
    final instant = DateTime(
      d.year,
      d.month,
      d.day,
      t.hour,
      t.minute,
    ).toUtcFromOccasionTime();
    setState(() {
      if (start) {
        from = instant.toOccasionTime();
      } else {
        until = instant.toOccasionTime();
      }
    });
  }

  Future<void> save() async {
    if (!formKey.currentState!.validate()) return;
    setState(() => busy = true);
    try {
      final parsed = num.parse(value.text.replaceAll(',', '.'));
      await Supabase.instance.client.rpc(
        'save_discount_code',
        params: {
          'p_occasion': widget.occasion,
          'p_id': widget.row?['id'],
          'p_expected_revision': widget.row?['revision'],
          'p_definition': {
            'code': code.text.trim(),
            'kind': kind,
            'value': kind == 'percent'
                ? int.parse(value.text.replaceAll(',', '.').split('.').first) *
                          100 +
                      int.parse(
                        (value.text
                                    .replaceAll(',', '.')
                                    .split('.')
                                    .skip(1)
                                    .firstOrNull ??
                                '')
                            .padRight(2, '0'),
                      )
                : parsed,
            'currency': currency.text.trim().toUpperCase(),
            'formIds': forms.toList(),
            'productIds': products.toList(),
            'isActive': active,
            'usageLimit': int.tryParse(limit.text),
            'validFrom': from?.toUtc().toIso8601String(),
            'validUntil': until?.toUtc().toIso8601String(),
          },
        },
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      final key = e is PostgrestException && e.code == '23505'
          ? 'duplicate'
          : e is PostgrestException &&
                e.message == 'DISCOUNT_IDENTITY_IMMUTABLE'
          ? 'immutable'
          : e is PostgrestException && e.message == 'DISCOUNT_REVISION_CONFLICT'
          ? 'conflict'
          : 'invalid';
      if (mounted) setState(() => error = DiscountStrings.text(key));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AppDialog(
    dismissible: !busy,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 600),
      child: Scaffold(
        appBar: AppDialogAppBar(
          title: Text(
            DiscountStrings.text(widget.row == null ? 'create' : 'edit'),
          ),
          onClose: () => Navigator.pop(context),
          closeEnabled: !busy,
        ),
        body: Form(
          key: formKey,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              TextFormField(
                controller: code,
                enabled: !busy,
                decoration: InputDecoration(
                  labelText: DiscountStrings.text('code'),
                ),
                maxLength: 32,
                validator: (v) =>
                    RegExp(r'^[A-Za-z0-9-]{4,32}$').hasMatch(v?.trim() ?? '')
                    ? null
                    : DiscountStrings.text('invalid'),
              ),
              DropdownButtonFormField<String>(
                initialValue: kind,
                items: ['percent', 'fixed']
                    .map(
                      (k) => DropdownMenuItem(
                        value: k,
                        child: Text(DiscountStrings.text(k)),
                      ),
                    )
                    .toList(),
                onChanged: busy ? null : (v) => setState(() => kind = v!),
              ),
              TextFormField(
                controller: value,
                enabled: !busy,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: DiscountStrings.text('value'),
                ),
                validator: (v) {
                  final n = num.tryParse((v ?? '').replaceAll(',', '.'));
                  return n != null &&
                          n > 0 &&
                          RegExp(r'^\d+([.,]\d{1,2})?$').hasMatch(v ?? '') &&
                          (kind != 'percent' || n <= 100)
                      ? null
                      : DiscountStrings.text('invalid');
                },
              ),
              if (kind == 'fixed')
                TextFormField(
                  controller: currency,
                  enabled: !busy,
                  maxLength: 3,
                  decoration: InputDecoration(
                    labelText: DiscountStrings.text('currency'),
                  ),
                ),
              TextFormField(
                controller: limit,
                enabled: !busy,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: DiscountStrings.text('limit'),
                ),
                validator: (v) =>
                    v == null || v.isEmpty || (int.tryParse(v) ?? 0) > 0
                    ? null
                    : DiscountStrings.text('invalid'),
              ),
              SwitchListTile(
                title: Text(DiscountStrings.text('active')),
                value: active,
                onChanged: busy ? null : (v) => setState(() => active = v),
              ),
              for (final start in [true, false])
                ListTile(
                  title: Text(DiscountStrings.text(start ? 'from' : 'until')),
                  subtitle: Text(
                    (start ? from : until) == null
                        ? '-'
                        : DateFormat.yMd().add_jm().format(
                            (start ? from : until)!,
                          ),
                  ),
                  onTap: busy ? null : () => date(start),
                  trailing: IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: busy
                        ? null
                        : () => setState(() {
                            if (start) {
                              from = null;
                            } else {
                              until = null;
                            }
                          }),
                  ),
                ),
              ExpansionTile(
                title: Text(DiscountStrings.text('forms')),
                subtitle: Text(
                  forms.isEmpty
                      ? DiscountStrings.text('all')
                      : '${forms.length}',
                ),
                children: [
                  for (final f in widget.bundle.forms)
                    CheckboxListTile(
                      title: Text(f.definition.title ?? ''),
                      value: forms.contains(f.definition.id),
                      onChanged: busy
                          ? null
                          : (v) => setState(() {
                              if (v == true) {
                                forms.add(f.definition.id!);
                              } else {
                                forms.remove(f.definition.id);
                              }
                            }),
                    ),
                ],
              ),
              ExpansionTile(
                title: Text(DiscountStrings.text('products')),
                subtitle: Text(
                  products.isEmpty
                      ? DiscountStrings.text('all')
                      : '${products.length}',
                ),
                children: [
                  for (final p in widget.bundle.products)
                    CheckboxListTile(
                      title: Text(p.title ?? ''),
                      value: products.contains(p.id),
                      onChanged: busy
                          ? null
                          : (v) => setState(() {
                              if (v == true) {
                                products.add(p.id!);
                              } else {
                                products.remove(p.id);
                              }
                            }),
                    ),
                ],
              ),
              Text(DiscountStrings.text('restriction')),
              if (error != null)
                Semantics(
                  liveRegion: true,
                  child: Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              Wrap(
                spacing: 12,
                children: [
                  TextButton(
                    onPressed: busy ? null : save,
                    child: Text(DiscountStrings.text('save')),
                  ),
                  TextButton(
                    onPressed: busy ? null : () => Navigator.pop(context),
                    child: Text(DiscountStrings.text('cancel')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
