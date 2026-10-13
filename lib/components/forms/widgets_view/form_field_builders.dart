import '../waitlist_strings.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:fstapp/components/blueprint/blueprint_seat.dart';
import 'package:fstapp/components/eshop/db_orders.dart';
import 'package:fstapp/components/eshop/orders_strings.dart';
import 'package:fstapp/components/forms/models/holder_models/id_document_field_holder.dart';
import 'package:fstapp/components/forms/public_order_strings.dart';
import 'package:fstapp/components/forms/form_strings.dart';
import 'package:fstapp/components/forms/widgets_view/form_helper.dart';
import 'package:fstapp/theme_config.dart';
import 'package:fstapp/widgets/buttons_helper.dart';
import 'package:fstapp/components/_shared/common_strings.dart';

import '../models/holder_models/form_ticket_model.dart';
import '../models/holder_models/ticket_holder.dart';
import 'birth_year_field_builder.dart';
import '../models/holder_models/field_holder.dart';
import '../models/holder_models/form_holder.dart';

import 'id_document_field_builder.dart';
import 'text_field_builder.dart';

class FormFieldBuilders {
  static Widget buildTitleWidget(
      String displayTitle, bool isRequired, BuildContext context,
      {FocusNode? focusNode,
      TextStyle? textStyle,
      TextEditingController? controller}) {
    final TextStyle themeLabelStyle =
        Theme.of(context).inputDecorationTheme.labelStyle ??
            TextStyle(color: ThemeConfig.grey600(context));

    final TextStyle defaultLabelStyle = themeLabelStyle.copyWith(
      fontSize: 16 * FormHelper.fontSizeFactor,
      fontFamily: ThemeConfig.fontFamily,
    );
    final TextStyle effectiveBaseStyle = textStyle != null
        ? defaultLabelStyle.merge(textStyle)
        : defaultLabelStyle;

    if (focusNode != null || controller != null) {
      final List<Listenable> listenables = [];
      if (focusNode != null) listenables.add(focusNode);
      if (controller != null) listenables.add(controller);

      return AnimatedBuilder(
        animation: Listenable.merge(listenables),
        builder: (context, child) {
          final bool isFocused = focusNode?.hasFocus ?? false;
          final bool hasContent = controller?.text.isNotEmpty ?? false;
          // Color if focused OR has content (i.e., when label is floating)
          final bool showColor =
              (controller != null) ? (isFocused || hasContent) : isFocused;

          final TextStyle effectiveStyle = effectiveBaseStyle.copyWith(
            color: showColor
                ? Theme.of(context).primaryColor
                : effectiveBaseStyle.color,
          );
          final TextSpan? requiredStar = isRequired
              ? TextSpan(
                  text: ' *',
                  style: TextStyle(color: ThemeConfig.redColor(context)))
              : null;
          return RichText(
            text: TextSpan(
              style: effectiveStyle,
              text: displayTitle,
              children: [if (requiredStar != null) requiredStar],
            ),
          );
        },
      );
    } else {
      final TextSpan? requiredStar = isRequired
          ? TextSpan(
              text: ' *',
              style: TextStyle(color: ThemeConfig.redColor(context)))
          : null;
      return RichText(
        text: TextSpan(
          style: effectiveBaseStyle,
          text: displayTitle,
          children: [if (requiredStar != null) requiredStar],
        ),
      );
    }
  }

  static Widget buildTicketField(
      BuildContext context, FormHolder formHolder, TicketHolder ticket) {
    // Initial values register during the first frame without firing onChanged.
    // Recalculate once the new ticket forms have registered all their fields.
    if (ticket.tickets.any((t) => t.ticketKey.currentState == null) ||
        (ticket.tickets.isEmpty && !ticket.hasSpot)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (formHolder.controller?.globalKey.currentState != null) {
          formHolder.controller?.updateTotalPrice?.call();
        }
      });
    }
    if (ticket.fields.none((f) => f.fieldType == FormHelper.fieldTypeSpot)) {
      if (ticket.tickets.isEmpty &&
          !ticket.fixedParticipants &&
          ticket.maxTickets > 0) {
        ticket.tickets.add(FormTicketModel(
            ticketValues: ticket.fields,
            ticketKey: GlobalKey<FormBuilderState>()));
      }
      return StatefulBuilder(
          builder: (context, update) => Column(children: [
                for (var i = 0; i < ticket.tickets.length; i++) ...[
                  if (ticket.maxTickets > 1)
                    Row(children: [
                      Expanded(
                          child: Text(
                              '${WaitlistStrings.text('person')} ${i + 1}')),
                      if (!ticket.fixedParticipants &&
                          ticket.tickets.length > 1)
                        IconButton(
                          tooltip: CommonStrings.delete,
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            update(() => ticket.tickets.removeAt(i));
                            formHolder.controller!.updateTotalPrice?.call();
                          },
                        ),
                    ]),
                  FormBuilder(
                      key: ticket.tickets[i].ticketKey,
                      onChanged: formHolder.controller!.updateTotalPrice,
                      child: Column(
                          children: FormHelper.getFormFields(
                              context,
                              ticket.tickets[i].ticketKey,
                              formHolder,
                              ticket.tickets[i].ticketValues))),
                ],
                if (!ticket.fixedParticipants &&
                    ticket.tickets.length < ticket.maxTickets)
                  TextButton.icon(
                    icon: const Icon(Icons.add),
                    label: Text(WaitlistStrings.text('addPerson')),
                    onPressed: () {
                      update(() => ticket.tickets.add(FormTicketModel(
                          ticketValues: ticket.fields,
                          ticketKey: GlobalKey<FormBuilderState>())));
                      formHolder.controller!.updateTotalPrice?.call();
                    },
                  ),
              ]));
    }
    return StatefulBuilder(
      builder: (context, setState) {
        Future<void> removeTicket(int index) async {
          await DbOrders.selectSpot(
              context,
              formHolder.controller!.formKey!,
              formHolder.controller!.secret!,
              ticket.tickets[index].seat!.seat!.id!,
              false);
          setState(() {
            ticket.tickets.removeAt(index);
          });
          formHolder.controller!.updateTotalPrice?.call();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),
            Center(
              child: ButtonsHelper.primaryButton(
                context: context,
                onPressed: () async {
                  var seats = await formHolder.controller!.showSeatReservation!(
                      ticket.tickets.map((t) => t.seat!).toList());
                  if (seats != null) {
                    ticket.updateTickets(seats);
                  }
                  formHolder.controller!.updateTotalPrice?.call();
                },
                label: FormStrings.seatSelection,
                height: 50.0,
                width: 250.0,
                suffixIcon: Icon(Icons.event_seat),
              ),
            ),
            const SizedBox(height: 12),
            for (int i = 0; i < ticket.tickets.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Align(
                  alignment: Alignment.center,
                  child: Container(
                    decoration: BoxDecoration(
                      color: ThemeConfig.whiteColor(context),
                      border: Border.all(
                          color: Theme.of(context).primaryColor, width: 2.0),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Stack(
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Align(
                                alignment: Alignment.center,
                                child: buildTitleWidget(
                                  "${OrdersStrings.itemSingular} ${i + 1}",
                                  false,
                                  context,
                                ),
                              ),
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: IconButton(
                                onPressed: () => removeTicket(i),
                                icon: Icon(Icons.delete),
                                tooltip: CommonStrings.delete,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          "${ticket.tickets[i].seat!.seat}",
                          style: TextStyle(
                              fontSize: 14 * FormHelper.fontSizeFactor),
                        ),
                        Divider(color: Colors.black),
                        FormBuilder(
                          key: ticket.tickets[i].ticketKey,
                          onChanged: formHolder.controller!.updateTotalPrice,
                          child: Column(
                            children: FormHelper.getFormFields(
                                context,
                                ticket.tickets[i].ticketKey,
                                formHolder,
                                ticket.tickets[i].ticketValues
                                    .where((f) =>
                                        f.fieldType != FormHelper.fieldTypeSpot)
                                    .toList()),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  static Widget buildSpotField(
      BuildContext context,
      GlobalKey<FormBuilderState> formKey,
      FormHolder formHolder,
      FieldHolder fieldHolder) {
    FocusNode focusNode = FocusNode();
    TextEditingController textController = TextEditingController();
    return FormBuilderField<BlueprintSeat>(
      name: fieldHolder.fieldType,
      validator: FormBuilderValidators.compose([
        if (fieldHolder.isRequired)
          FormBuilderValidators.required(
              errorText: CommonStrings.fieldCannotBeEmpty),
        (value) => value == null ? PublicOrderStrings.selectSeat(null) : null,
      ]),
      builder: (FormFieldState<BlueprintSeat?> field) {
        BlueprintSeat? seat = field.value;
        textController.text = seat?.seat?.toString() ?? FormHelper.metaEmpty;
        return TextField(
          controller: textController,
          focusNode: focusNode,
          readOnly: true,
          canRequestFocus: true,
          decoration: InputDecoration(
            label: buildTitleWidget(
                fieldHolder.title!, fieldHolder.isRequired, context,
                focusNode: focusNode, controller: textController),
            suffixIcon: const Icon(Icons.event_seat),
            errorText: field.errorText,
            filled: true,
            fillColor: Colors.transparent,
          ),
          onTap: () async {
            await formHolder
                .controller!.showSeatReservation!(seat == null ? [] : [seat]);
          },
        );
      },
    );
  }

  static Widget buildTextField(BuildContext context, FormHolder formHolder,
      FieldHolder fieldHolder, Iterable<String> autofillHints) {
    return TextFieldBuilder(
      fieldHolder: fieldHolder,
      formHolder: formHolder,
      autofillHints: autofillHints,
      isEmail: false,
    );
  }

  static Widget buildEmailField(
      BuildContext context, FormHolder formHolder, FieldHolder fieldHolder) {
    return TextFieldBuilder(
      fieldHolder: fieldHolder,
      formHolder: formHolder,
      autofillHints: [AutofillHints.email],
      isEmail: true,
    );
  }

  static Widget buildPhoneNumber(
      BuildContext context, FormHolder formHolder, FieldHolder fieldHolder) {
    return TextFieldBuilder(
      fieldHolder: fieldHolder,
      formHolder: formHolder,
      autofillHints: [AutofillHints.telephoneNumber],
      isPhone: true,
    );
  }

  static Widget buildAddressField(
      BuildContext context, FormHolder formHolder, FieldHolder fieldHolder) {
    return TextFieldBuilder(
      fieldHolder: fieldHolder,
      formHolder: formHolder,
      autofillHints: [
        AutofillHints.fullStreetAddress,
        AutofillHints.streetAddressLevel1,
        AutofillHints.postalCode,
        AutofillHints.addressCity,
        AutofillHints.countryName,
      ],
      isAddress: true,
    );
  }

  static Widget buildNationalityField(
      BuildContext context, FormHolder formHolder, FieldHolder fieldHolder) {
    return TextFieldBuilder(
      fieldHolder: fieldHolder,
      formHolder: formHolder,
      autofillHints: [AutofillHints.countryName],
      isNationality: true,
    );
  }

  static Widget buildIdDocumentField(
      BuildContext context,
      GlobalKey<FormBuilderState> formKey,
      FormHolder formHolder,
      IdDocumentFieldHolder fieldHolder) {
    return IdDocumentFieldBuilder.buildIdDocumentField(
      context: context,
      fieldHolder: fieldHolder,
      formKey: formKey,
      formHolder: formHolder,
    );
  }

  static Widget buildBirthYearField(
      BuildContext context, FormHolder formHolder, FieldHolder fieldHolder) {
    return BirthYearFieldBuilder(
      fieldHolder: fieldHolder,
      formHolder: formHolder,
    );
  }
}
