import 'package:festapp_core/communication_tone.dart';

import '../forms/db_forms.dart';
import '../forms/models/form_bundle.dart';

import 'package:festapp_core/email_templates.dart';
import 'package:intl/intl.dart';

import '../occasion/occasion_model.dart';
import '../features/feature_constants.dart';
import '../eshop/db_eshop.dart';
import '../eshop/models/product_edit_bundle.dart';
import '../../data_services/rights_service.dart';

class EmailPreviewContextResult {
  final EmailPreviewContext context;
  final bool unavailable;
  const EmailPreviewContextResult(this.context, {this.unavailable = false});
}

/// Uses the existing permission-checked catalog, never customers or orders.
Future<EmailPreviewContextResult> loadEmailPreviewContext(
  OccasionModel? occasion, {
  Future<ProductsEditBundle> Function(String)? loadProducts,
  Future<List<FormBundle>> Function(String)? loadForms,
  Object? inheritedTone,
}) async {
  if (occasion == null) {
    return EmailPreviewContextResult(
      EmailPreviewContext(
        communicationTone: CommunicationTone.resolve(null, inheritedTone),
      ),
    );
  }
  final now = DateTime.now();
  final start = occasion.startTime;
  final deadline =
      start != null && start.isAfter(now.add(const Duration(days: 14)))
      ? start.subtract(const Duration(days: 7))
      : now.add(const Duration(days: 7));
  final current = RightsService.currentOccasion();
  final features = occasion.features.isNotEmpty
      ? occasion.features
      : current?.id == occasion.id
      ? current!.features
      : occasion.features;
  var tone = CommunicationTone.resolve(null, inheritedTone);
  final link = occasion.link?.isNotEmpty == true
      ? occasion.link
      : current?.id == occasion.id
      ? current?.link
      : null;
  var unavailable = false;
  if (link != null && link.isNotEmpty) {
    try {
      final forms = await (loadForms ?? DbForms.getAllFormsByOccasionLink)(
        link,
      );
      tone = CommunicationTone.resolve(
        forms.firstOrNull?.definition.data?['communication_tone'],
        inheritedTone,
      );
    } catch (_) {
      unavailable = true;
    }
  }
  final base = EmailPreviewContext(
    communicationTone: tone,
    occasionTitle: occasion.title,
    ticketsEnabled: features.any(
      (f) => f.code == FeatureConstants.ticket && f.isEnabled,
    ),
    blueprintEnabled: features.any(
      (f) => f.code == FeatureConstants.blueprint && f.isEnabled,
    ),
    deadline: DateFormat.yMd().format(deadline),
  );
  if (link == null || link.isEmpty) {
    return EmailPreviewContextResult(base, unavailable: true);
  }
  try {
    final bundle =
        await (loadProducts ?? DbEshop.getProductsAndTypesForOccasion)(link);
    final eligible = bundle.products
        .where(
          (p) =>
              p.isHidden != true &&
              p.title?.trim().isNotEmpty == true &&
              p.price != null &&
              p.price!.isFinite &&
              p.price! >= 0,
        )
        .toList();
    final first = eligible.where((p) => p.price! > 0).firstOrNull;
    if (first == null)
      return EmailPreviewContextResult(base, unavailable: unavailable);
    final currency = first.currencyCode ?? 'CZK';
    final selected = [
      first,
      ...eligible.where(
        (p) => !identical(p, first) && (p.currencyCode ?? 'CZK') == currency,
      ),
    ].take(base.singleApplication ? 1 : 2);
    final types = {for (final type in bundle.productTypes) type.id: type.title};
    return EmailPreviewContextResult(
      EmailPreviewContext(
        occasionTitle: occasion.title,
        communicationTone: tone,
        deadline: base.deadline,
        ticketsEnabled: base.ticketsEnabled,
        blueprintEnabled: base.blueprintEnabled,
        products: selected
            .map(
              (p) => EmailPreviewProduct(
                title: p.title!,
                typeTitle:
                    types[p.productTypeId] ??
                    p.productTypeTitleString ??
                    (p.title ?? ''),
                price: p.price!,
                currency: currency,
              ),
            )
            .toList(),
      ),
      unavailable: unavailable,
    );
  } catch (_) {
    return EmailPreviewContextResult(base, unavailable: true);
  }
}
