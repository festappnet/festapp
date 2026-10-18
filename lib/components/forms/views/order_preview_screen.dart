import '../models/verified_organization_identity.dart';
import '../widgets_view/organization_identity_footer.dart';
import 'package:fstapp/components/eshop/order_item_strings.dart';
import 'package:festapp_core/forms.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/components/forms/models/holder_models/id_document_data.dart';
import 'package:fstapp/components/forms/widgets_view/form_helper.dart';
import 'package:fstapp/components/forms/widgets_view/option_field_helper.dart';
import 'package:fstapp/services/utilities_all.dart';
import 'package:fstapp/styles/styles_config.dart';
import 'package:fstapp/theme_config.dart';
import 'package:fstapp/widgets/buttons_helper.dart';

import 'package:collection/collection.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/features/feature_constants.dart';
import 'package:fstapp/components/features/feature_service.dart';
import 'package:fstapp/components/forms/public_order_strings.dart';
import '../models/holder_models/form_holder.dart';
import '../models/holder_models/ticket_holder.dart';

class OrderPreviewScreen extends StatefulWidget {
  final FormHolder formHolder;
  final double totalPrice;
  final VoidCallback onSendPressed;
  final VoidCallback? onClose;
  final String? tone;
  final VerifiedOrganizationIdentity? organizationIdentity;
  final bool hasTickets;
  final Map<String, double> metaSurchargeSums;

  static const double fontSizeFactor = 1.1;

  const OrderPreviewScreen({
    super.key,
    required this.formHolder,
    required this.totalPrice,
    required this.onSendPressed,
    this.onClose,
    this.tone,
    this.organizationIdentity,
    this.hasTickets = true,
    this.metaSurchargeSums = const {},
  });

  @override
  _OrderPreviewScreenState createState() => _OrderPreviewScreenState();
}

class _OrderPreviewScreenState extends State<OrderPreviewScreen> {
  late ScrollController _scrollController;
  String _paymentType = 'full';

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();

    // After the frame is rendered, animate scroll to the bottom to reveal the Submit button.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(seconds: 1),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // Helper method to intersperse dividers between widgets.
  List<Widget> _addDividers(List<Widget> widgets) {
    if (widgets.isEmpty) return widgets;
    final List<Widget> result = [];
    for (int i = 0; i < widgets.length; i++) {
      result.add(widgets[i]);
      if (i != widgets.length - 1) {
        result.add(const Divider());
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Stack(
        children: [
          IntrinsicHeight(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: StylesConfig.formMaxWidth,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Header
                        Center(
                          child: Text(
                            PublicOrderStrings.summary,
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(
                                  fontSize:
                                      18 * OrderPreviewScreen.fontSizeFactor,
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Personal Info Section with dividers between rows (no extra divider at end)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: _addDividers(_buildDataSection(context)),
                        ),

                        const SizedBox(height: 16),

                        // Tickets Section
                        _buildTicketsSection(context),

                        const SizedBox(height: 16),

                        // Payment type choice (deposit vs full), only for on-site deposit
                        if (_hasDepositProducts() &&
                            FeatureService.isDepositChoiceAvailable())
                          _buildDepositSection(context),

                        // Total Price
                        _buildTotalPrice(context),

                        const SizedBox(height: 16),

                        // Submit Button
                        Center(
                          child: ButtonsHelper.primaryButton(
                            context: context,
                            onPressed: () {
                              widget.formHolder.paymentType = _paymentType;
                              widget.onSendPressed();
                            },
                            label: PublicOrderStrings.getSubmitButton(
                                widget.hasTickets, widget.tone),
                            height: 50.0,
                            width: 250.0,
                          ),
                        ),
                        OrganizationIdentityFooter(
                            identity: widget.organizationIdentity),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Close Icon
          Positioned(
            top: 0,
            right: 0,
            child: IconButton(
              icon: Icon(
                Icons.close,
                size: 24 * OrderPreviewScreen.fontSizeFactor,
              ),
              onPressed: () {
                if (widget.onClose != null) {
                  widget.onClose!();
                } else {
                  Navigator.of(context).pop();
                }
              },
              tooltip: CommonStrings.close,
            ),
          ),
        ],
      ),
    );
  }

  // Builds a list of info rows for the personal data section.
  List<Widget> _buildDataSection(BuildContext context) {
    final dataFields = widget.formHolder.fields.where((field) {
      return field.fieldType != FormMetadata.fieldTypeTicket;
    }).toList();

    final List<Widget> infoRows = [];
    for (var field in dataFields) {
      var value = field.getValue(widget.formHolder.controller!.globalKey);
      String? valueString = value.toString();
      if (value is IPreviewable) {
        valueString = value.toPreviewString(context: context);
      }
      if (value != null) {
        infoRows.add(_buildInfoRow(
          context,
          field.title!,
          valueString,
          field.fieldType,
        ));
      }
    }
    return infoRows;
  }

  Widget _buildTicketsSection(BuildContext context) {
    final ticketHolder = widget.formHolder.fields.firstWhere(
      (field) => field.fieldType == FormMetadata.fieldTypeTicket,
    ) as TicketHolder;

    return Column(
      children: ticketHolder.tickets.asMap().entries.map((entry) {
        final ticketIndex = entry.key + 1;
        final ticket = entry.value;

        final List<Widget> ticketInfoRows = [];

        ticketInfoRows.add(Text(
          ticketHolder.tickets.length > 1
              ? "${OrderItemStrings.itemSingular} $ticketIndex"
              : OrderItemStrings.itemSingular,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontSize: 16 * OrderPreviewScreen.fontSizeFactor,
                fontWeight: FontWeight.bold,
              ),
        ));

        // If there is a seat, add it.
        if (ticket.seat != null) {
          ticketInfoRows.add(_buildInfoRow(
            context,
            FormHelper.spotLabel(),
            ticket.seat!.seat.toString(),
          ));
        } else if (ticket.seat == null && ticketHolder.hasSpot) {
          // Add warning if no seat selected but spots are enabled/required
          ticketInfoRows.add(_buildInfoRow(
            context,
            FormHelper.spotLabel(),
            PublicOrderStrings.selectSeat(widget.tone),
          ));
        }

        // Add ticket details rows.
        final ticketDetails = ticket.ticketValues.where((entry) {
          final value = entry.getValue(ticket.ticketKey);
          return value != null && value.toString().isNotEmpty;
        }).map((entry) {
          String s;
          String? priceText;
          var value = entry.getValue(ticket.ticketKey);
          if (value is FormOptionDefinition) {
            s = OptionFieldHelper.buildOptionTitle(context, value);
            priceText = OptionFieldHelper.buildPriceText(context, value);
            final metaText =
                OptionFieldHelper.buildMetaSurchargeText(context, value);
            if (metaText != null) s = '$s\n$metaText';
          } else {
            if (value is Iterable &&
                value.isNotEmpty &&
                value.first is FormOptionProductModel) {
              var sectionPrice = 0.0;
              var products = List<FormOptionProductModel>.from(value);
              sectionPrice +=
                  products.fold(0, (sum, product) => sum + product.price);
              s = value.toString();
              priceText =
                  '+ ${Utilities.formatPrice(context, sectionPrice, currencyCode: widget.formHolder.controller!.currencyCode)}';
              final metaTexts = products
                  .map((p) =>
                      OptionFieldHelper.buildMetaSurchargeText(context, p))
                  .whereType<String>()
                  .toList();
              if (metaTexts.isNotEmpty) {
                s = '$s\n${metaTexts.join('\n')}';
              }
            } else if (value.isEmpty) {
              s = "";
            } else {
              s = value.toString();
            }
          }
          return _buildInfoRow(
              context, entry.title!, s, entry.fieldType, priceText);
        }).toList();

        // Combine all ticket info rows with dividers.
        final List<Widget> combinedRows =
            _addDividers(ticketInfoRows + ticketDetails);

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: ThemeConfig.whiteColor(context),
              border: Border.all(
                color: Theme.of(context).primaryColor,
                width: 2.0,
              ),
              borderRadius: BorderRadius.circular(8.0),
            ),
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: combinedRows,
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildInfoRow(BuildContext context, String label, String value,
      [String? fieldType, String? priceText]) {
    final labelValueWidget = SelectableText.rich(
      TextSpan(
        children: [
          TextSpan(
            text: "$label: ",
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontSize: 14 * OrderPreviewScreen.fontSizeFactor,
                    ) ??
                TextStyle(fontSize: 14 * OrderPreviewScreen.fontSizeFactor),
          ),
          TextSpan(
            text: FormHelper.fieldTypeValue(context, value, fieldType),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontSize: 14 * OrderPreviewScreen.fontSizeFactor,
                      fontWeight: FontWeight.bold,
                    ) ??
                TextStyle(
                    fontSize: 14 * OrderPreviewScreen.fontSizeFactor,
                    fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );

    if (priceText == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4.0),
        child: labelValueWidget,
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Expanded(child: labelValueWidget),
          Text(
            priceText,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontSize: 14 * OrderPreviewScreen.fontSizeFactor,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).primaryColor,
                    ) ??
                TextStyle(
                    fontSize: 14 * OrderPreviewScreen.fontSizeFactor,
                    fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildTotalPrice(BuildContext context) {
    // Visual-only meta-surcharge totals (per currency). Never affect totalPrice.
    final metaLines = OptionFieldHelper.formatMetaSurchargeSumLines(
        context, widget.metaSurchargeSums);

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            PublicOrderStrings.totalPrice(
                context,
                Utilities.formatPrice(context, widget.totalPrice,
                    currencyCode: widget.formHolder.controller!.currencyCode)),
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontSize: 16 * OrderPreviewScreen.fontSizeFactor,
                  fontWeight: FontWeight.bold,
                ),
          ),
          for (final line in metaLines)
            Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Text(
                line,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontSize: 14 * OrderPreviewScreen.fontSizeFactor,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
        ],
      ),
    );
  }

  bool _hasDepositProducts() {
    if (!FeatureService.isFeatureEnabled(FeatureConstants.deposit))
      return false;
    final ticketHolder = widget.formHolder.fields.firstWhereOrNull(
      (field) => field.fieldType == FormMetadata.fieldTypeTicket,
    ) as TicketHolder?;
    if (ticketHolder == null) return false;
    for (final ticket in ticketHolder.tickets) {
      for (final entry in ticket.ticketValues) {
        final value = entry.getValue(ticket.ticketKey);
        if (value is FormOptionProductModel && value.depositAmount != null) {
          return true;
        }
        if (value is Iterable) {
          for (final item in value) {
            if (item is FormOptionProductModel && item.depositAmount != null) {
              return true;
            }
          }
        }
      }
    }
    return false;
  }

  double _calculateDepositTotal() {
    double total = 0;
    final ticketHolder = widget.formHolder.fields.firstWhereOrNull(
      (field) => field.fieldType == FormMetadata.fieldTypeTicket,
    ) as TicketHolder?;
    if (ticketHolder == null) return total;
    for (final ticket in ticketHolder.tickets) {
      for (final entry in ticket.ticketValues) {
        final value = entry.getValue(ticket.ticketKey);
        if (value is FormOptionProductModel) {
          total += value.depositAmount ?? value.price;
        } else if (value is Iterable) {
          for (final item in value) {
            if (item is FormOptionProductModel) {
              total += item.depositAmount ?? item.price;
            }
          }
        }
      }
    }
    return total;
  }

  Widget _buildDepositSection(BuildContext context) {
    final depositTotal = _calculateDepositTotal();
    final currencyCode = widget.formHolder.controller!.currencyCode;
    final depositFeature = FeatureService.getDepositFeature();
    final isOnSite = depositFeature?.depositDeadline == "on_site";
    final infoText = isOnSite
        ? PublicOrderStrings.depositInfoOnSite
        : PublicOrderStrings.depositInfoDaysBefore(
            depositFeature?.depositDeadlineDays ?? 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          PublicOrderStrings.paymentMethod,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontSize: 15 * OrderPreviewScreen.fontSizeFactor,
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 8),
        RadioListTile<String>(
          value: 'deposit',
          groupValue: _paymentType,
          onChanged: (v) => setState(() => _paymentType = v!),
          title: Text(
            '${PublicOrderStrings.payWithDeposit} (${Utilities.formatPrice(context, depositTotal, currencyCode: currencyCode)})',
            style: TextStyle(fontSize: 14 * OrderPreviewScreen.fontSizeFactor),
          ),
          subtitle: Text(
            infoText,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontSize: 13 * OrderPreviewScreen.fontSizeFactor,
                  fontStyle: FontStyle.italic,
                ),
          ),
          dense: true,
          contentPadding: EdgeInsets.zero,
        ),
        RadioListTile<String>(
          value: 'full',
          groupValue: _paymentType,
          onChanged: (v) => setState(() => _paymentType = v!),
          title: Text(
            '${PublicOrderStrings.payFullAmount} (${Utilities.formatPrice(context, widget.totalPrice, currencyCode: currencyCode)})',
            style: TextStyle(fontSize: 14 * OrderPreviewScreen.fontSizeFactor),
          ),
          dense: true,
          contentPadding: EdgeInsets.zero,
        ),
      ],
    );
  }
}
