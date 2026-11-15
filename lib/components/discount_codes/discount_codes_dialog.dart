import 'package:festapp_core/formatting.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
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
    this.client,
  });
  final int occasion;
  final ProductsEditBundle bundle;
  final SupabaseClient? client;
  @override
  State<DiscountCodesDialog> createState() => _DiscountCodesDialogState();
}

class _DiscountCodesDialogState extends State<DiscountCodesDialog> {
  List<Map<String, dynamic>>? rows;
  String? error;
  bool loading = false;
  int loadGeneration = 0;
  SupabaseClient get client => widget.client ?? Supabase.instance.client;
  bool get enabled =>
      FeatureService.isFeatureEnabled(FeatureConstants.discountCodes);
  bool get canEdit => RightsService.canUpdateOrders();

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final generation = ++loadGeneration;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final value = await client.rpc(
        'list_discount_codes',
        params: {'p_occasion': widget.occasion},
      );
      if (mounted && generation == loadGeneration) {
        setState(() {
          rows = (value as List)
              .map((r) => Map<String, dynamic>.from(r))
              .toList();
        });
      }
    } catch (_) {
      if (mounted && generation == loadGeneration) {
        setState(() => error = DiscountStrings.text('invalid'));
      }
    } finally {
      if (mounted && generation == loadGeneration) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> edit([Map<String, dynamic>? row]) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DiscountEditor(
        occasion: widget.occasion,
        bundle: widget.bundle,
        row: row,
        client: client,
        onSaved: load,
      ),
    );
    // A cancelled conflict must also return to the current server revision.
    if (mounted && saved != true) await load();
  }

  String total(Map<String, dynamic> row) {
    final totals = row['discountTotals'] as Map? ?? {};
    if (totals.isNotEmpty) {
      return totals.entries
          .map(
            (e) => Utilities.formatPrice(
              context,
              (e.value as num).toDouble(),
              currencyCode: e.key.toString(),
              decimalDigits: 2,
            ),
          )
          .join(', ');
    }
    if (row['uses'] == null) return '-';
    final currencies = widget.bundle.products
        .map((p) => p.currencyCode)
        .whereType<String>()
        .toSet();
    final currency =
        row['currency_code'] as String? ??
        (currencies.length == 1 ? currencies.single : null);
    return currency == null
        ? '0'
        : Utilities.formatPrice(
            context,
            0,
            currencyCode: currency,
            decimalDigits: 2,
          );
  }

  String value(Map<String, dynamic> row) => row['kind'] == 'percent'
      ? '${formatDisplayNumber((row['value'] as num) / 100, locale: context.locale.toLanguageTag())} %'
      : Utilities.formatPrice(
          context,
          (row['value'] as num).toDouble(),
          currencyCode: row['currency_code'],
          decimalDigits: 2,
        );

  @override
  Widget build(BuildContext context) => AppAlertDialog(
    title: Text(DiscountStrings.text('title')),
    content: SizedBox(
      width: 720,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .65,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!enabled)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(DiscountStrings.text('paused')),
                ),
              if (loading) const LinearProgressIndicator(),
              if (error != null)
                TextButton(onPressed: load, child: Text(error!)),
              if (rows?.isEmpty == true && !loading)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(DiscountStrings.text('empty')),
                ),
              for (final row in rows ?? <Map<String, dynamic>>[])
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  title: Text(
                    row['normalized_code'],
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${value(row)} · ${DiscountStrings.text('uses')}: ${row['uses'] == null ? '-' : formatDisplayNumber(row['uses'] as num, locale: context.locale.toLanguageTag())} / ${row['usage_limit'] == null ? '∞' : formatDisplayNumber(row['usage_limit'] as num, locale: context.locale.toLanguageTag())}',
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${DiscountStrings.text('history')}: ${total(row)}',
                        ),
                      ],
                    ),
                  ),
                  trailing: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        DiscountStrings.text(
                          row['is_active'] == true && enabled
                              ? 'active'
                              : 'inactive',
                        ),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (canEdit) const Icon(Icons.chevron_right),
                    ],
                  ),
                  onTap: canEdit ? () => edit(row) : null,
                ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      AppDialogActions(
        leading: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            IconButton(
              tooltip: DiscountStrings.text('help'),
              onPressed: () => launchUrl(
                Uri.parse(
                  '${AppConfig.webLink}${context.locale.languageCode == 'cs' ? '/napoveda/ceny-a-kapacity/#slevove-kody' : '/help/ticket-prices-capacity/#discount-codes'}',
                ),
              ),
              icon: const Icon(Icons.help_outline),
            ),
            IconButton(
              onPressed: loading ? null : load,
              tooltip: DiscountStrings.text('refresh'),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(CommonStrings.close),
          ),
          if (canEdit)
            FilledButton.icon(
              onPressed: enabled && !loading ? () => edit() : null,
              icon: const Icon(Icons.add),
              label: Text(DiscountStrings.text('create')),
            ),
        ],
      ),
    ],
  );
}

class _DiscountEditor extends StatefulWidget {
  const _DiscountEditor({
    required this.occasion,
    required this.bundle,
    this.row,
    required this.client,
    required this.onSaved,
  });
  final int occasion;
  final ProductsEditBundle bundle;
  final Map<String, dynamic>? row;
  final SupabaseClient client;
  final Future<void> Function() onSaved;
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
      await widget.client.rpc(
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
      await widget.onSaved();
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
  Widget build(BuildContext context) => AppAlertDialog(
    title: Text(DiscountStrings.text(widget.row == null ? 'create' : 'edit')),
    dismissible: !busy,
    onClose: () => Navigator.pop(context),
    content: SizedBox(
      width: 600,
      child: Form(
        key: formKey,
        child: ListView(
          shrinkWrap: true,
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
              isExpanded: true,
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
                forms.isEmpty ? DiscountStrings.text('all') : '${forms.length}',
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
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      AppDialogActions(
        actions: [
          TextButton(
            onPressed: busy ? null : () => Navigator.pop(context),
            child: Text(CommonStrings.cancel),
          ),
          FilledButton(
            onPressed: busy ? null : save,
            child: busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(CommonStrings.save),
          ),
        ],
      ),
    ],
  );
}
