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
    OccasionModel? occasion,
    {Future<ProductsEditBundle> Function(String)? loadProducts}) async {
  if (occasion == null) {
    return const EmailPreviewContextResult(EmailPreviewContext());
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
  final base = EmailPreviewContext(
      occasionTitle: occasion.title,
      ticketsEnabled:
          features.any((f) => f.code == FeatureConstants.ticket && f.isEnabled),
      blueprintEnabled: features
          .any((f) => f.code == FeatureConstants.blueprint && f.isEnabled),
      deadline: DateFormat.yMd().format(deadline));
  final link = occasion.link?.isNotEmpty == true
      ? occasion.link
      : current?.id == occasion.id
          ? current?.link
          : null;
  if (link == null || link.isEmpty) {
    return EmailPreviewContextResult(base, unavailable: true);
  }
  try {
    final bundle =
        await (loadProducts ?? DbEshop.getProductsAndTypesForOccasion)(link);
    final eligible = bundle.products
        .where((p) =>
            p.isHidden != true &&
            p.title?.trim().isNotEmpty == true &&
            p.price != null &&
            p.price!.isFinite &&
            p.price! >= 0)
        .toList();
    final first = eligible.where((p) => p.price! > 0).firstOrNull;
    if (first == null) return EmailPreviewContextResult(base);
    final currency = first.currencyCode ?? 'CZK';
    final selected = [
      first,
      ...eligible.where(
          (p) => !identical(p, first) && (p.currencyCode ?? 'CZK') == currency)
    ].take(base.singleApplication ? 1 : 2);
    final types = {for (final type in bundle.productTypes) type.id: type.title};
    return EmailPreviewContextResult(EmailPreviewContext(
      occasionTitle: occasion.title,
      deadline: base.deadline,
      ticketsEnabled: base.ticketsEnabled,
      blueprintEnabled: base.blueprintEnabled,
      products: selected
          .map((p) => EmailPreviewProduct(
              title: p.title!,
              typeTitle: types[p.productTypeId] ??
                  p.productTypeTitleString ??
                  (p.title ?? ''),
              price: p.price!,
              currency: currency))
          .toList(),
    ));
  } catch (_) {
    return EmailPreviewContextResult(base, unavailable: true);
  }
}
