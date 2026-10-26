import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/features/feature_constants.dart';
import 'package:fstapp/components/features/feature_service.dart';
import 'package:fstapp/components/forms/form_strings.dart';
import 'package:festapp_core/forms.dart';
import 'package:fstapp/components/forms/widgets_view/form_helper.dart';
import 'package:fstapp/components/html/html_helper.dart';
import 'package:fstapp/services/utilities_all.dart';
import 'package:fstapp/theme_config.dart';
import 'package:fstapp/components/html/html_view.dart';

/// A helper class to centralize all duplicated UI logic for building
/// label styles, card layouts, etc. used by both Checkbox and Radio fields.
class OptionFieldHelper {
  // Adjust as needed; you can also make this configurable if it's dynamic.

  /// Text style used for option titles in checkboxes/radios.
  static TextStyle optionTitleTextStyle() {
    return TextStyle(fontSize: 14.0 * FormHelper.fontSizeFactor);
  }

  /// Returns just the option title (without price).
  static String buildOptionTitle(
    BuildContext context,
    FormOptionDefinition option,
  ) {
    return option.title;
  }

  /// Returns formatted price string like "+ 1 000 CZK", or null if no price.
  static String? buildPriceText(
      BuildContext context, FormOptionDefinition option) {
    if (option is FormOptionProductModel && option.price > 0) {
      return '+ ${Utilities.formatPrice(context, option.price, currencyCode: option.currencyCode, decimalDigits: option.price == option.price.truncateToDouble() ? 0 : null)}';
    }
    return null;
  }

  /// Formatted deposit label: "záloha: 500 CZK"
  static String buildDepositText(
      BuildContext context, FormOptionProductModel option) {
    final depositStr = Utilities.formatPrice(context, option.depositAmount!,
        currencyCode: option.currencyCode, decimalDigits: option.price == option.price.truncateToDouble() ? 0 : null);
    return '${FormStrings.depositInfo}: $depositStr';
  }

  /// Returns the visual meta-surcharge text for a product option, or null when
  /// nothing should be rendered (DepositFeature off, no amount and no description).
  /// Format:
  ///   "+ 200 EUR — popisek" / "+ 200 EUR" — positive amount (surcharge)
  ///   "− 200 EUR — popisek" / "− 200 EUR" — negative amount (sleva / discount)
  ///   "popisek" — description only
  /// NEVER affects payment/order totals.
  /// Fallback when admin leaves the per-product surcharge currency empty —
  /// matches the placeholder shown in the inline editor input ("EUR").
  /// Independent of the product price currency (surcharge doesn't go through
  /// the bank, so it doesn't share the price currency).
  static const String defaultMetaSurchargeCurrency = 'EUR';

  static String? buildMetaSurchargeText(
      BuildContext context, FormOptionDefinition option) {
    if (!FeatureService.isFeatureEnabled(FeatureConstants.deposit)) return null;
    // Meta surcharge applies only to product options.
    if (option is! FormOptionProductModel) return null;
    final desc = FeatureService.getMetaSurchargeDescription();
    final amount = option.metaSurchargeAmount;
    final currency =
        option.metaSurchargeCurrency ?? defaultMetaSurchargeCurrency;
    final hasAmount = amount != null && amount != 0;
    // No amount → render nothing. Global description alone is not enough.
    if (!hasAmount) return null;
    final amountText = formatMetaSurchargeAmount(context, amount!, currency);
    return desc != null ? '$amountText — $desc' : amountText;
  }

  /// Formats a single signed meta-surcharge amount in the standard
  /// "+ 200 EUR" / "− 200 EUR" form. Caller is responsible for filtering
  /// zero/null amounts.
  static String formatMetaSurchargeAmount(
      BuildContext context, double amount, String currency) {
    final sign = amount < 0 ? '− ' : '+ ';
    final priceStr =
        Utilities.formatPrice(context, amount.abs(), currencyCode: currency);
    return '$sign$priceStr';
  }

  /// Formats per-currency meta-surcharge sums into display strings.
  /// Zero entries are filtered out so callers can render the result directly.
  /// Used by the price widget (live total) and order preview (final total).
  static List<String> formatMetaSurchargeSumLines(
      BuildContext context, Map<String, double> sums) {
    return sums.entries
        .where((e) => e.value != 0)
        .map((e) => formatMetaSurchargeAmount(context, e.value, e.key))
        .toList();
  }

  /// Builds a card with a leading widget (checkbox or radio), a title, and an optional HTML description.
  static Widget buildOptionCard({
    required BuildContext context,
    required bool isSelected,
    required Widget leading,
    required String title,
    String? priceText,
    required String? description,
    required VoidCallback? onTap,
  }) {
    final bool hasDescription = !HtmlHelper.isHtmlEmptyOrNull(description);

    return InkWell(
      onTap: onTap,
      child: Card(
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: isSelected
                ? Theme.of(context).primaryColor
                : ThemeConfig.grey500(context),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            crossAxisAlignment: hasDescription
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.center,
            children: [
              leading,
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: FormHelper.cardOptionTitleTextStyle(),
                          ),
                        ),
                        if (priceText != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            priceText,
                            style:
                                FormHelper.cardOptionTitleTextStyle().copyWith(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).primaryColor,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (hasDescription)
                      Padding(
                        padding: const EdgeInsets.only(top: 4.0),
                        child: HtmlView(
                          color: ThemeConfig.grey600(context),
                          html: description!,
                          fontSize: FormHelper.optionDescriptionFontSize(),
                          isSelectable: false,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
