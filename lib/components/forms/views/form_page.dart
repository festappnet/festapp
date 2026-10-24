import '../payment_quote_refresh.dart';
import 'package:intl/intl.dart';
import 'package:fstapp/services/time_helper.dart';
import 'package:fstapp/components/blueprint/blueprint_layout_adapter.dart';
import 'package:fstapp/components/forms/reservation_capability_store.dart';
import '../widgets_view/form_total_price.dart';
import '../models/verified_organization_identity.dart';
import '../payment_method_strings.dart';
import '../models/holder_models/field_holder.dart';
import '../widgets_view/organization_identity_footer.dart';
import 'package:fstapp/components/forms/models/form_presentation.dart';
import 'package:festapp_core/forms.dart';
import 'package:fstapp/components/forms/order_overview_strings.dart';
import 'customer_order_overview.dart';
import 'package:fstapp/components/stripe_payments/stripe_payment_browser_stub.dart'
    if (dart.library.html) 'package:fstapp/components/stripe_payments/stripe_payment_browser_web.dart'
    if (dart.library.js_interop) 'package:fstapp/components/stripe_payments/stripe_payment_browser_web.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fstapp/components/forms/waitlist_commands.dart';
import 'package:fstapp/components/forms/waitlist_strings.dart';
import 'package:fstapp/components/forms/models/holder_models/form_ticket_model.dart';
import 'package:fstapp/services/dialog_helper.dart';
import 'dart:async';
import 'package:fstapp/components/forms/widgets_view/countdown_content.dart';
import 'package:fstapp/components/fonts/form_font_catalog.dart';
import 'package:fstapp/components/_shared/common_strings.dart';

import 'package:auto_route/auto_route.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:fstapp/components/blueprint/blueprint_seat.dart';
import 'package:fstapp/components/blueprint/seat_reservation/widgets/seat_reservation_widget.dart';
import 'package:fstapp/components/forms/views/reservation_page.dart';
import 'package:fstapp/router_service.dart';
import 'package:fstapp/services/app_logger.dart';
import 'package:fstapp/components/forms/models/form_bundle.dart';
import 'package:fstapp/components/forms/form_session.dart';
import 'package:festapp_core/eshop.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/components/forms/db_forms.dart';
import 'package:fstapp/components/eshop/db_orders.dart';
import 'package:fstapp/components/forms/views/order_preview_screen.dart';
import 'package:fstapp/components/forms/widgets_view/form_helper.dart';
import 'package:fstapp/components/forms/widgets_view/option_field_helper.dart';
import '../../features/feature_constants.dart';
import '../../features/feature_service.dart';
import 'package:fstapp/styles/styles_config.dart';
import 'package:fstapp/theme_config.dart';
import 'package:fstapp/widgets/buttons_helper.dart';
import 'package:flutter/services.dart';
import 'package:fstapp/components/html/html_view.dart';

import '../models/holder_models/form_holder.dart';
import '../form_strings.dart';
import 'order_finish_screen.dart';

@RoutePage()
class FormPage extends StatefulWidget {
  static const ROUTE = "form";

  String? formLink;
  final String? offerId;
  final int? waitlistOrderId;
  FormPage(
      {super.key,
      @pathParam this.formLink,
      this.offerId,
      this.waitlistOrderId});

  @override
  _FormPageState createState() => _FormPageState();
}

class _FormPageState extends State<FormPage> {
  final _waitlist = WaitlistCommands();
  Map<String, dynamic>? _offerBundle;
  CustomerOrderScope? _overviewScope;
  bool _showOverview = false;
  bool _overviewAccessFailed = false;
  String? _offerId;
  int? _waitlistOrderId;
  String? _waitlistToken;
  final Set<int> _selectedTicketIds = {};
  final Map<int, FormTicketModel> _ticketDrafts = {};
  String? _waitlistMessage;
  bool _demoCompleted = false;
  FormBundle? _changedCapacityForm;
  String? _paymentChangeReason;
  bool get _paymentReviewRequired => _paymentChangeReason != null;
  bool _refreshingChangedForm = false;
  bool _isLoading = false;
  bool _formNotAvailable = false;
  bool _formLoadFailed = false;
  FormFontCatalog? _fonts;
  bool _fontLoadFailed = false;

  Map<String, dynamic>? formResult;
  FormHolder? formHolder;
  FormBundle? form;
  VerifiedOrganizationIdentity? _terminalIdentity;
  FormSession? formSession;

  var _formKey = GlobalKey<FormBuilderState>();
  final ScrollController _scrollController = ScrollController();

  bool _isSeatReservationVisible = false;
  bool _isOrderPreviewVisible = false;
  Completer<List<BlueprintSeat>?>? _seatReservationCompleter;
  StreamSubscription<dynamic>? _popStateSubscription;
  bool _isClosingProgrammatically = false;

  bool _dependenciesInitialized = false;

  @override
  void dispose() {
    _popStateSubscription?.cancel();
    formSession?.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies(); // Call super FIRST

    // This ensures that if the widget rebuilds (e.g., from pop state),
    // we don't re-trigger the data load, but we do re-subscribe the listener.
    if (_dependenciesInitialized) {
      _popStateSubscription?.cancel();
      _popStateSubscription = RouterService.onPopState.listen(_handlePopState);
      return;
    }

    if (widget.formLink == null && context.routeData.hasPendingChildren) {
      widget.formLink =
          context.routeData.pendingChildren[0].params.getString("formLink");
    }

    // Call loadData, but DO NOT await it.
    // `loadData` correctly sets _isLoading, and the `build` method
    // will show a CircularProgressIndicator. This is the correct pattern.
    loadData();

    // Add the popstate listener from RouterService
    _popStateSubscription?.cancel(); // Cancel any old one
    _popStateSubscription = RouterService.onPopState.listen(_handlePopState);

    _dependenciesInitialized = true; // Mark as initialized
  }

  /// Handles browser back/forward events
  void _handlePopState(dynamic event) {
    if (_isClosingProgrammatically) {
      // This was a "Confirm" click from _hideSeatReservation or _hideOrderPreview.
      // The history is popped, and the overlay is already closing.
      // We just reset the flag and do nothing.
      _isClosingProgrammatically = false;
      _replaceOverviewUrl();
      return;
    }

    if (_isOrderPreviewVisible) {
      // Browser Back clicked while Order Preview is open.
      // URL is already popped. We just need to close the sheet and update state.
      // We set the flag to false BEFORE popping to prevent whenComplete from triggering _hideOrderPreview.
      setState(() {
        _isOrderPreviewVisible = false;
      });
      Navigator.of(context).pop();
      return;
    }

    // This was a "Browser Back" click.
    if (_isSeatReservationVisible) {
      if (formHolder?.controller?.reservationPending == true) {
        RouterService.pushOverlayState('seat-reservation');
        return;
      }
      // The overlay is visible, so this pop event must close it.
      // This handles both the "Confirm" case (if user uses fwd/back)
      // and the "Cancel" case (where user hits back to clear the hash).
      setState(() {
        _isSeatReservationVisible = false;
      });

      if (_seatReservationCompleter != null &&
          !_seatReservationCompleter!.isCompleted) {
        // User wants browser back to function as a "Confirm"
        formSession?.confirmSeatSelection();
        _seatReservationCompleter!.complete(formSession?.currentSeats);
      }
      _seatReservationCompleter = null;
    }
    // If the overlay is *not* visible, this pop event was
    // just cleaning up a dangling state from a "Cancel".
    // We don't need to do anything. The browser handles the URL.
  }

  Future<List<BlueprintSeat>?> _showSeatReservation(List<BlueprintSeat> seats) {
    if (_isSeatReservationVisible) return _seatReservationCompleter!.future;

    // Push a new history state via RouterService
    RouterService.pushOverlayState('seat-reservation');

    formSession!.startSeatSelection();
    // No need to updateSeats(seats) here as we are just opening it,
    // unless 'seats' differs from what's in ticket holder which shouldn't happen if we strictly follow ticket holder.
    // However, if the caller passed explicit seats (like from a specific ticket edit), we might want to respect that?
    // In `TicketFieldBuilder`, it passes `ticket.tickets.map((t) => t.seat!).toList()`.
    // Since we are using ticket holder as truth, we should be fine.

    setState(() {
      _isSeatReservationVisible = true;
    });

    _seatReservationCompleter = Completer<List<BlueprintSeat>?>();

    return _seatReservationCompleter!.future;
  }

  /// Hides the SeatReservationWidget and resolves the completer
  void _hideSeatReservation(List<BlueprintSeat>? seats) {
    if (!_isSeatReservationVisible ||
        (seats != null && formHolder?.controller?.reservationPending == true))
      return;
    _isClosingProgrammatically = true;
    RouterService.goBackProgrammatically();

    setState(() {
      _isSeatReservationVisible = false;
    });
    // If seats is null, it's a cancel (back button logic handles confirm via completer check above?)
    // Wait, _hideSeatReservation is called by US manually OR by history pop?
    // If `seats` is NOT null, it's a confirm.
    if (seats != null) {
      formSession!.confirmSeatSelection();
    } else {
      formSession!.cancelSeatSelection();
    }

    // Complete the future with the result (null for cancel, list for confirm)
    if (_seatReservationCompleter != null &&
        !_seatReservationCompleter!.isCompleted) {
      _seatReservationCompleter!.complete(seats);
    }
    _seatReservationCompleter = null;
  }

  void _hideOrderPreview() {
    // This is called when we want to forcefully close the sheet and history (e.g. submit success),
    // OR when the sheet has already closed (swipe/close button) and we just need to sync history.
    if (!_isOrderPreviewVisible) return;

    _isClosingProgrammatically = true;
    RouterService.goBackProgrammatically();

    setState(() {
      _isOrderPreviewVisible = false;
    });
  }

  Widget _buildSeatReservationOverlay() {
    if (!_isSeatReservationVisible) return const SizedBox.shrink();

    return Positioned.fill(
      child: Container(
        color: ThemeConfig.dddBackground, // Dim background
        child: Center(
          child: SeatReservationWidget(
            secret: formHolder!.controller!.secret!,
            formDataKey: formHolder!.controller!.formKey!,
            blueprintId: formHolder!.controller!.blueprintId!,
            demoSimulation: form!.demoSimulation,
            selectedSeats: formSession!.currentSeats,
            maxTickets: formHolder!.getTicket()?.maxTickets,
            selectedAreaQuantity: (id) => formSession!.areaQuantity(id),
            onQuantityRequested: (binding, quantity, available, product) async {
              formSession!.setAreaQuantity(binding, quantity,
                  available: available, product: product);
            },
            onPendingChanged: (pending) {
              formHolder!.controller!.reservationPending = pending;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() {});
              });
            },
            beforeReservationRequest:
                formHolder!.controller!.rememberReservation,
            onSessionChanged: formHolder!.controller!.updateReservationSession,
            onSelectionChanged: (sts) {
              formSession!.updateSeats(sts);
            },
            onCloseSeatReservation:
                formHolder!.controller!.onCloseSeatReservation!,
          ),
        ),
      ),
    );
  }

  // _buildOrderPreviewOverlay removed as we use showModalBottomSheet

  Widget _buildPriceAndTicketInfo() {
    if ((formSession?.totalPrice ?? 0) <= 0)
      return SizedBox(); // Do not display if total price is 0

    // Visual-only meta-surcharge totals (per currency). Never affect totalPrice.
    final metaLines = OptionFieldHelper.formatMetaSurchargeSumLines(
        context, formSession?.metaSurchargeSums ?? const {});

    return Positioned(
      top: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        decoration: BoxDecoration(
          color: form?.definition.primaryColor != null
              ? Color(form!.definition.primaryColor!)
              : Theme.of(context).primaryColor,
          borderRadius: BorderRadius.circular(8.0),
          boxShadow: [BoxShadow(blurRadius: 5, color: Colors.black26)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "${formSession?.totalTickets ?? 0}x",
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  Icons.local_activity,
                  color: Colors.white,
                  size: 24,
                ),
                const SizedBox(width: 10),
                FormTotalPrice(
                  amount: formSession?.totalPrice ?? 0,
                  currencyCode: formHolder!.controller!.currencyCode,
                  payments: form?.definition.payments,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            for (final line in metaLines)
              Padding(
                padding: const EdgeInsets.only(top: 2.0),
                child: Text(
                  line,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showOrderPreview(BuildContext scrollContext) async {
    if (formHolder?.controller?.reservationPending == true) return;
    if (_paymentReviewRequired) {
      await _applyChangedCapacity();
      return;
    }
    TextInput.finishAutofillContext();
    final ticket = formHolder?.getTicket();
    if (ticket != null &&
        (ticket.tickets.isEmpty || ticket.tickets.length > ticket.maxTickets)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(WaitlistStrings.text('FORM_CAPACITY_EXCEEDED'))));
      return;
    }
    var valid = await FormHelper.saveValidateAndScroll(formHolder!);
    if (!mounted || formHolder?.controller?.reservationPending == true) return;
    setState(() {});
    if (valid &&
        !form!.definition.demoSimulation &&
        form!.definition.isWaitlist &&
        _offerBundle == null) {
      final confirmed = await DialogHelper.showConfirmationDialog(
          context, WaitlistStrings.title, WaitlistStrings.explanation);
      if (!confirmed || !mounted) return;
      setState(() => _isLoading = true);
      try {
        final data = FormHelper.getDataFromForm(formHolder!);
        final payload = <String, dynamic>{
          'form': form!.definition.key,
          'fields': data['fields'],
          'tickets': [
            for (final person in (data['ticket'] as List? ?? []))
              {
                'fields': [
                  for (final field in person['fields'])
                    {
                      for (final entry in (field as Map).entries)
                        if (int.tryParse(entry.key.toString()) != null)
                          entry.key.toString(): entry.value
                    },
                ]
              },
          ]
        };
        for (final field in formHolder!.fields) {
          if (['email', 'name', 'surname', 'phone'].contains(field.fieldType))
            payload[field.fieldType] = field.getValue(_formKey);
        }
        final result = await _waitlist.command('register', payload);
        if (result['orderOverviewUrl'] is String) {
          final scope =
              CustomerOrderScope.fromUri(Uri.parse(result['orderOverviewUrl']));
          if (mounted)
            setState(() {
              _overviewScope = scope;
              _showOverview = scope != null;
            });
          _replaceOverviewUrl();
          return;
        }
        if (mounted)
          setState(() {
            _waitlistMessage =
                '${WaitlistStrings.registered} ${result['order']?['order_symbol'] ?? ''}. ${WaitlistStrings.explanation} ${WaitlistStrings.queued}';
          });
      } catch (e) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('${WaitlistStrings.stale} ($e)')));
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
      return;
    }
    if (valid) {
      RouterService.pushOverlayState('order-preview');
      setState(() {
        _isOrderPreviewVisible = true;
      });

      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (_) {
          // Inherit the theme from the current context (which has the form's custom theme)
          return Theme(
            data: _buildFormTheme(context),
            child: OrderPreviewScreen(
              organizationIdentity: form?.organizationIdentity,
              formHolder: formHolder!,
              totalPrice: formSession?.totalPrice ?? 0,
              payments: form!.definition.payments,
              paymentSurface: stripePaymentSurface(),
              metaSurchargeSums: formSession?.metaSurchargeSums ?? const {},
              onSendPressed: _sendOrder,
              // When user clicks Close in UI, we just pop the sheet.
              // verification of _isOrderPreviewVisible in whenComplete will handle history sync.

              // verification of _isOrderPreviewVisible in whenComplete will handle history sync.
              onClose: () => Navigator.of(context).pop(),
              tone: form!.definition.data?[FormMetadata.metaCommunicationTone],
              hasTickets: FeatureService.isFeatureEnabled(
                  FeatureConstants.ticket,
                  features: form!.occasion?.features),
            ),
          );
        },
      ).whenComplete(() {
        // If flag is still true, it means the sheet was closed via swipe or UI close button,
        // (not by our back button handler which sets it to false first).
        // So we need to sync history (pop the hash).
        if (_isOrderPreviewVisible) {
          _hideOrderPreview();
        }
      });
    }
  }

  void _scrollToTop() {
    if (_scrollController.hasClients) _scrollController.jumpTo(0.0);
  }

  Future<void> _sendOrder() async {
    if (_isLoading ||
        formHolder == null ||
        form == null ||
        formHolder?.controller?.reservationPending == true) return;
    if (form!.demoSimulation) {
      _hideOrderPreview();
      setState(() => _demoCompleted = true);
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final submittingController = formHolder!.controller!;
    // Snapshot mounted form fields before persistence yields and loading hides them.
    var data = FormHelper.getDataFromForm(formHolder!);
    data = FormHelper.replaceSpotWithId(data);
    data[FormMetadata.metaSecret] =
        formHolder?.controller?.secret ?? form!.definition.secret;
    data[FormMetadata.metaForm] = form!.definition.key;
    if (formHolder!.paymentType != null) {
      data['payment_type'] = formHolder!.paymentType;
    }
    if (formHolder!.paymentMethod == 'stripe') {
      data['payment_method'] = 'stripe';
      data['payment_type'] = 'full';
      data['expected_payment_amount_minor'] = formHolder!.paymentAmountMinor;
      data['expected_payment_currency'] = formHolder!.paymentCurrency;
      data['stripe_connection_id'] = formHolder!.paymentConnectionId;
      data['payment_surface'] = stripePaymentSurface();
    }
    formResult = data;
    await submittingController.rememberReservation();
    final submittedCapability = submittingController.capability;
    if (!mounted) return;

    await showGeneralDialog(
      context: context,
      barrierDismissible: false, // Disable dismissing by tapping outside
      barrierLabel: "FinishOrderDialog",
      pageBuilder: (context, anim1, anim2) => FinishOrderScreen(
        organizationIdentity: form?.organizationIdentity,
        overviewAvailable: _overviewScope != null,
        occasionTitle: form!.occasion?.title ?? form!.definition.title,
        orderFutureFunction: () async {
          if (_offerId != null) {
            try {
              final result = await _waitlist.accept(
                  offerId: _offerId!,
                  token: _waitlistToken,
                  ticketIds: _selectedTicketIds.toList(),
                  orderDetails: data);
              return FunctionResponse(status: 200, data: {
                ...result,
                'ticketOrder': {'order': result['order']}
              });
            } on WaitlistCommandException catch (e) {
              return FunctionResponse(status: 200, data: e.data);
            }
          }
          final response = await DbOrders.sendTicketOrder(data);
          if (response.data is Map &&
              {'STRIPE_PRICE_CHANGED', 'STRIPE_RECIPIENT_CHANGED'}
                  .contains(response.data['errorCode'])) {
            if (mounted)
              setState(() =>
                  _paymentChangeReason = response.data['errorCode'] as String);
          }
          if (response.data is Map &&
              response.data['errorCode'] == 'FORM_CAPACITY_EXCEEDED' &&
              widget.formLink != null) {
            final latest = await DbForms.getFormFromLink(widget.formLink!);
            if (mounted) setState(() => _changedCapacityForm = latest);
          }
          return response;
        },
        onOrderConfirmed: () async {
          await submittingController.capabilityStore
              ?.clear(submittedCapability);
          // Reset session tickets?
          // `_formKey.currentState?.reset()` resets the form fields.
          // TicketHolder might need manual reset or re-loadData will handle it.
          // formSession updateSeats([]) is effectively clearing it.
          // But since we use TicketHolder, we should reload data.
          if (_offerId != null && _overviewScope != null) {
            if (mounted) setState(() => _showOverview = true);
          } else {
            await loadData();
            formSession?.recalculateTotals();
          }
        },
        onSuccess: () async {
          if (!mounted) return;
          Navigator.of(context).pop(); // Close the OrderPreview BottomSheet
          _scrollToTop();
        },
        tone: form!.definition.data?[FormMetadata.metaCommunicationTone],
        hasTickets: FeatureService.isFeatureEnabled(FeatureConstants.ticket,
            features: form!.occasion?.features),
      ),
      transitionBuilder: (context, anim1, anim2, child) {
        return Theme(
          data: _buildFormTheme(context),
          child: FadeTransition(
            opacity: anim1, // Fade animation
            child: child,
          ),
        );
      },
    );

    if (!mounted) return;
    if (_paymentReviewRequired && _isOrderPreviewVisible) {
      Navigator.of(context)
          .pop(); // Retire the stale quote after closing its error.
      _scrollToTop();
    }
    setState(() {
      _isLoading = false;
    });
  }

// ... (imports)

  ThemeData _buildFormTheme(BuildContext context) {
    var theme = Theme.of(context);
    var form = this.form; // Use class member

    if (form != null) {
      if (form.definition.fontFamily != null && _fonts != null) {
        try {
          theme = theme.copyWith(
            textTheme: _fonts!
                .getTextTheme(form.definition.fontFamily!, theme.textTheme),
          );
        } catch (e) {
          AppLogger.error(e.toString());
        }
      }

      int? primaryInt = form.definition.primaryColor;
      int? secondaryInt = form.definition.secondaryColor;

      Color? primary = primaryInt != null ? Color(primaryInt) : null;
      Color? secondary = secondaryInt != null ? Color(secondaryInt) : null;

      // Check brightness to respect system theme (dark/light) unless we want to force something.
      bool isDark = theme.brightness == Brightness.dark;

      if (primary != null) {
        // SMART COLOR LOGIC FOR DARK MODE
        // Ensure the primary color is bright enough to be visible against dark background.
        final hsl = HSLColor.fromColor(primary);
        // Boost lightness more aggressively for dark mode to ensure visibility
        if (isDark && hsl.lightness < 0.75) {
          primary = hsl.withLightness(0.75).toColor();
          // Also optionally boost saturation if it's very low, to make it pop
          if (hsl.saturation < 0.3) {
            primary = HSLColor.fromColor(primary).withSaturation(0.4).toColor();
          }
        }

        // Auto-calculate secondary if not provided
        secondary ??= HSLColor.fromColor(primary)
            .withLightness((isDark ? 0.85 : 0.9).clamp(0.0, 1.0))
            .toColor();

        theme = theme.copyWith(
            primaryColor: primary,
            // Use a very subtle tint of the primary color for background in light mode
            // User requested "very slightly colored" and "solid opaque" background
            // Round 12: Increased opacity to 0.12 ("even darker") for light mode.
            scaffoldBackgroundColor: Color.alphaBlend(
                primary.withOpacity(isDark ? 0.05 : 0.07),
                isDark ? Colors.grey.shade900 : Colors.white),
            colorScheme: ThemeConfig.colorSchemeForBrand(
              primary: primary,
              secondary: secondary,
              brightness: theme.brightness,
            ).copyWith(
              // Only force white surface if strictly desired, otherwise let theme decide or use a light tint
              surface: isDark ? null : Colors.white,
            ),
            checkboxTheme: CheckboxThemeData(
              fillColor: WidgetStateProperty.resolveWith<Color>((states) {
                if (states.contains(WidgetState.selected)) {
                  return primary!;
                }
                return isDark ? Colors.grey.shade400 : Colors.grey.shade600;
              }),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4)),
              side: BorderSide(
                  color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                  width: 2),
            ),
            radioTheme: RadioThemeData(
              fillColor: WidgetStateProperty.resolveWith<Color>((states) {
                if (states.contains(WidgetState.selected)) {
                  return primary!;
                }
                return isDark ? Colors.grey.shade400 : Colors.grey.shade600;
              }),
            ),
            switchTheme: SwitchThemeData(
              thumbColor: WidgetStateProperty.resolveWith<Color>((states) {
                if (states.contains(WidgetState.selected)) {
                  return primary!;
                }
                return isDark ? Colors.grey.shade400 : Colors.grey.shade200;
              }),
              trackColor: WidgetStateProperty.resolveWith<Color>((states) {
                if (states.contains(WidgetState.selected)) {
                  return primary!.withOpacity(0.5);
                }
                return isDark ? Colors.grey.shade700 : Colors.grey.shade400;
              }),
            ),
            inputDecorationTheme: theme.inputDecorationTheme.copyWith(
              filled: true,
              // In dark mode, white fill is bad. Use a dark surface color or transparent.
              fillColor: isDark ? Colors.grey.shade800 : Colors.white,
              labelStyle: TextStyle(
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade700),
            ),
            elevatedButtonTheme: ElevatedButtonThemeData(
                style: ElevatedButton.styleFrom(
              backgroundColor: primary,
              foregroundColor: ThemeConfig.textColorForBackground(primary),
            )));
      }
    }
    return theme;
  }

  Widget _withIdentity(Widget child) =>
      Column(mainAxisSize: MainAxisSize.min, children: [
        child,
        OrganizationIdentityFooter(
            identity: form?.organizationIdentity ?? _terminalIdentity)
      ]);

  @override
  Widget build(BuildContext context) {
    // Check time limits
    bool isClosed = false;
    bool isBeforeStart = false;

    if (form != null && _offerBundle == null) {
      final now = DateTime.now();
      if (form!.definition.isOpen == false) {
        isClosed = true;
      } else if (form!.definition.startTime != null &&
          now.isBefore(form!.definition.startTime!)) {
        isClosed = true;
        isBeforeStart = true;
      } else if (form!.definition.endTime != null &&
          now.isAfter(form!.definition.endTime!)) {
        isClosed = true;
      }
    }

    dynamic previewParam = context.routeData.queryParams.get('preview', false);
    bool isPreviewParam = previewParam.toString().toLowerCase() == 'true';
    bool canPreview = RightsService.canSeeReservations();
    // Only allow preview if specifically requested AND user is editor
    bool showPreview = canPreview && isPreviewParam;
    bool showCountdown = isBeforeStart &&
        (form?.definition.enableCountdown ?? false) &&
        !showPreview;

    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_formLoadFailed) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(CommonStrings.unexpectedError, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              TextButton(onPressed: loadData, child: Text(CommonStrings.retry)),
            ]),
          ),
        ),
      );
    }

    if (_showOverview && _overviewScope != null) {
      return Scaffold(
          body:
              SafeArea(child: SingleChildScrollView(child: _buildOverview())));
    }
    if (_fontLoadFailed) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(FormStrings.fontLoadFailed),
              TextButton(onPressed: loadData, child: Text(CommonStrings.retry)),
            ],
          ),
        ),
      );
    }

    if (_demoCompleted) {
      return Scaffold(
          body: Center(
              child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(FormStrings.demoComplete,
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          Text(FormStrings.demoResult, textAlign: TextAlign.center),
          const SizedBox(height: 24),
          TextButton(
              onPressed: () => setState(() => _demoCompleted = false),
              child: Text(CommonStrings.close)),
        ]),
      )));
    }
    if (_waitlistMessage != null)
      return Scaffold(
          body: Center(
              child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: SingleChildScrollView(
                      child: _withIdentity(Text(_waitlistMessage!))))));
    if (_offerBundle != null &&
        (_offerId == null ||
            (_offerBundle!['pendingCount'] as num? ?? 0) == 0)) {
      return Scaffold(
          body: SingleChildScrollView(
              child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(children: [
                    _buildOverview(),
                    _buildWaitlistPeople(manage: true),
                    OrganizationIdentityFooter(
                        identity:
                            form?.organizationIdentity ?? _terminalIdentity)
                  ]))));
    }
    if (form?.definition.registrationMode == 'full' && !isClosed) {
      return Scaffold(
          body: Center(
              child: SingleChildScrollView(
                  child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: StylesConfig.formMaxWidth),
        child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              if (form?.definition.header != null)
                HtmlView(html: form!.definition.header!, isSelectable: true),
              Text(WaitlistStrings.full),
              OrganizationIdentityFooter(
                  identity: form?.organizationIdentity ?? _terminalIdentity),
            ])),
      ))));
    }
    if (_formNotAvailable || (isClosed && !showPreview && !showCountdown)) {
      return Scaffold(
          body: SingleChildScrollView(
              child: _withIdentity(_buildFormNotAvailableMessage())));
    }

    ThemeData theme = _buildFormTheme(context);

    Widget bodyContent;

    if (showCountdown) {
      bodyContent = Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: StylesConfig.formMaxWidth),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CountdownContent(
                targetTime: form!.definition.startTime!,
                html: form!.definition.countdownTitle,
                onFinished: loadData,
              ),
              if (form!.definition.showBeforeStartMessage &&
                  (form!.definition.beforeStartMessage?.trim().isNotEmpty ??
                      false))
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: SizedBox(
                    width: double.infinity,
                    child: HtmlView(
                      html: form!.definition.beforeStartMessage!,
                      isSelectable: true,
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    } else {
      // Main Form Content
      bodyContent = SafeArea(
        child: Stack(
          children: [
            Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints:
                    BoxConstraints(maxWidth: StylesConfig.formMaxWidth),
                child: Builder(
                  builder: (scrollContext) {
                    return SingleChildScrollView(
                      controller: _scrollController,
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          children: [
                            if (form!.demoSimulation)
                              Padding(
                                  padding: const EdgeInsets.only(bottom: 16),
                                  child: Text(FormStrings.demoNotice,
                                      textAlign: TextAlign.center)),
                            if (showPreview)
                              Container(
                                width: double.infinity,
                                color: Colors.orangeAccent,
                                padding: const EdgeInsets.all(8.0),
                                margin: const EdgeInsets.only(bottom: 16.0),
                                child: Text(
                                  FormStrings.previewMode,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: Colors.black),
                                ),
                              ),
                            if (formHolder == null)
                              const Center(child: CircularProgressIndicator())
                            else
                              FormBuilder(
                                key: _formKey,
                                child: Builder(builder: (context) {
                                  return AutofillGroup(
                                    child: Column(
                                      children: [
                                        if (form!.definition.header != null)
                                          Column(
                                            children: [
                                              HtmlView(
                                                  html:
                                                      form!.definition.header!,
                                                  isSelectable: true),
                                              const SizedBox(height: 16),
                                            ],
                                          ),
                                        if (_changedCapacityForm != null ||
                                            _paymentReviewRequired)
                                          Column(children: [
                                            Text(_paymentReviewRequired
                                                ? PaymentMethodStrings.text(
                                                    _paymentChangeReason ==
                                                            'STRIPE_RECIPIENT_CHANGED'
                                                        ? 'reason_recipient_changed'
                                                        : 'priceChanged')
                                                : WaitlistStrings.text(
                                                    'FORM_CAPACITY_EXCEEDED')),
                                            TextButton(
                                                onPressed:
                                                    _refreshingChangedForm
                                                        ? null
                                                        : _applyChangedCapacity,
                                                child: Text(
                                                    (_changedCapacityForm
                                                                ?.definition
                                                                .isWaitlist ??
                                                            false)
                                                        ? WaitlistStrings.text(
                                                            'regularToWaitlist')
                                                        : WaitlistStrings
                                                            .refresh)),
                                          ]),
                                        if (form!.definition.isWaitlist)
                                          Text(
                                              '${WaitlistStrings.title}. ${WaitlistStrings.explanation}'),
                                        if (_offerBundle != null) ...[
                                          _buildOverview(),
                                          _buildWaitlistPeople(),
                                        ],
                                        if (_offerBundle == null &&
                                            form!.definition.capacity
                                                    ?.showRemaining ==
                                                true &&
                                            form!.definition.capacity
                                                    ?.remainingPublic !=
                                                null)
                                          Text(
                                              '${WaitlistStrings.remaining}: ${form!.definition.capacity!.remainingPublic}'),
                                        ...FormHelper.getAllFormFields(
                                            context, _formKey, formHolder!),
                                        const SizedBox(height: 32),
                                        ButtonsHelper.primaryButton(
                                          context: context,
                                          onPressed: (_isLoading ||
                                                  formHolder?.controller
                                                          ?.reservationPending ==
                                                      true ||
                                                  (!form!.definition
                                                          .isWaitlist &&
                                                      (formSession?.totalProducts ??
                                                              0) ==
                                                          0))
                                              ? null
                                              : () => _showOrderPreview(
                                                  scrollContext),
                                          label: form!.definition.isWaitlist
                                              ? WaitlistStrings.register
                                              : (_offerId != null
                                                  ? WaitlistStrings.accept
                                                  : FormStrings.buttonContinue),
                                          isLoading: _isLoading,
                                          height: 50.0,
                                          width: 250.0,
                                        ),
                                        const SizedBox(height: 32),
                                      ],
                                    ),
                                  );
                                }),
                              ),
                            OrganizationIdentityFooter(
                                identity: form?.organizationIdentity ??
                                    _terminalIdentity),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            _buildSeatReservationOverlay(),
            if (form?.definition.isWaitlist != true) _buildPriceAndTicketInfo(),
          ],
        ),
      );
    }

    final sharedDesign = form?.definition.data?['design'] as Map?;
    if (['solid', 'gradient'].contains(sharedDesign?['background_mode']) &&
        form?.definition.primaryColor != null) {
      final primary = Color(form!.definition.primaryColor!);
      bodyContent = DecoratedBox(
          decoration: BoxDecoration(
              color: primary,
              gradient: sharedDesign?['background_mode'] == 'gradient' &&
                      form!.definition.secondaryColor != null
                  ? LinearGradient(colors: [
                      primary,
                      Color(form!.definition.secondaryColor!)
                    ])
                  : null),
          child: Padding(
              padding: const EdgeInsets.all(12),
              child: ColoredBox(
                  color: theme.scaffoldBackgroundColor, child: bodyContent)));
    }

    return Theme(
      data: theme,
      child: Scaffold(
        body: showCountdown
            ? SafeArea(
                child: SingleChildScrollView(child: _withIdentity(bodyContent)))
            : bodyContent,
        floatingActionButtonLocation: FloatingActionButtonLocation.endDocked,
        floatingActionButton: Padding(
          padding: EdgeInsets.only(bottom: 24),
          child: Visibility(
            visible: RightsService.canSeeReservations(),
            child: FloatingActionButton(
              backgroundColor: theme.primaryColor,
              foregroundColor: theme.colorScheme.onPrimary,
              onPressed: () {
                RouterService.navigateOccasion(context, ReservationsPage.ROUTE)
                    .then((value) => loadData());
              },
              child: const Icon(Icons.edit),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFormNotAvailableMessage() {
    String notAvailableText = (form?.definition.headerOff?.isNotEmpty ?? false)
        ? form!.definition.headerOff!
        : FormStrings.reservationUnavailableMessage;
    return Center(
      child: Container(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.event_busy,
              size: 60,
            ),
            const SizedBox(height: 16),
            Text(
              FormStrings.reservationUnavailable,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            IntrinsicWidth(
              child: HtmlView(
                html: notAvailableText,
                isSelectable: true,
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  // Function to generate options for a specific item type and add them to the ticket fields
  Map<String, dynamic> generateOptionsForItemType(
      List<ProductTypeModel> allItems, String itemType) {
    var itemTypeModel =
        allItems.firstWhereOrNull((item) => item.type == itemType);

    if (itemTypeModel == null || itemTypeModel.products == null) {
      return {};
    }

    List<Map<String, dynamic>> options = [];

    for (var item in itemTypeModel.products!) {
      options.add({
        FormOptionDefinition.metaOptionsName: item.title.toString(),
        FormOptionDefinition.metaOptionsId: item.id.toString(),
        FormOptionDefinition.metaOptionsPrice:
            item.price ?? 0.0, // Include price in the options
      });
    }

    return {
      FormMetadata.metaType: FormMetadata.fieldTypeSelectOne,
      FormMetadata.metaOptions: options,
      FormMetadata.metaLabel: itemTypeModel.title,
      FormMetadata.metaOptionsType: itemType,
    };
  }

  Future<void> _applyChangedCapacity() async {
    if (formHolder == null || _refreshingChangedForm) return;
    final previousHolder = formHolder!;
    final review = _paymentReviewRequired;
    setState(() => _refreshingChangedForm = true);
    try {
      var latest = review && widget.formLink != null
          ? await DbForms.getFormFromLink(widget.formLink!)
          : _changedCapacityForm;
      if (latest == null || !mounted || formHolder != previousHolder) return;
      if (latest.definition.isWaitlist &&
          !await DialogHelper.showConfirmationDialog(
              context, WaitlistStrings.title, WaitlistStrings.explanation))
        return;
      if (!mounted) return;
      // Preserve the hold capability, but never prices from an old seat model.
      latest = latest.withDefinition(
          latest.definition.copyWith(secret: form!.definition.secret));
      final refreshed = latest;
      final previousTickets =
          previousHolder.getTicket()?.tickets ?? <FormTicketModel>[];
      final refreshedSeats = <int, BlueprintSeat>{};
      if (!refreshed.definition.isWaitlist &&
          previousTickets.any((ticket) => ticket.seat != null)) {
        final blueprintId = refreshed.definition.blueprint;
        if (blueprintId == null) throw StateError('Missing blueprint');
        final blueprint = await DbForms.getBlueprint(
            refreshed.definition.secret!,
            refreshed.definition.key!,
            blueprintId);
        if (blueprint == null) throw StateError('Blueprint unavailable');
        refreshedSeats.addAll(refreshedReservedPaymentSeats(
            blueprint,
            previousTickets
                .map((ticket) => ticket.seat?.seatId)
                .whereType<int>()));
      }
      if (!mounted || formHolder != previousHolder) return;
      final holder = FormHolder.fromDefinition(refreshed.definition);
      void restoreFields(List<FieldHolder> target, List<FieldHolder> previous,
          GlobalKey<FormBuilderState> key) {
        for (final field in target) {
          final old = previous
              .firstWhereOrNull((candidate) => candidate.id == field.id);
          if (old == null) continue;
          final value = old.getValue(key);
          if (field is OptionsFieldProductHolder) {
            final values = value is List ? value : [value];
            final ids = values
                .map((item) =>
                    item is FormOptionDefinition ? item.id : item?.toString())
                .toSet();
            final selected = field.options
                .whereType<FormOptionProductModel>()
                .where(
                    (option) => ids.contains(option.id) && option.isAvailable)
                .map((option) => option.id)
                .toList();
            field.defaultValue = field.selectionType ==
                    OptionsFieldProductSelectionType.selectMany
                ? selected
                : selected.firstOrNull;
          } else if (field.fieldType != FormMetadata.fieldTypeSpot &&
              field.fieldType != FormMetadata.fieldTypeTicket) {
            field.defaultValue =
                value is FormOptionDefinition ? value.id : value;
          }
        }
      }

      restoreFields(holder.fields, previousHolder.fields,
          previousHolder.controller!.globalKey);
      holder.getTicket()?.tickets = previousTickets.map((person) {
        final fields =
            FormHolder.fromDefinition(refreshed.definition).getTicket()!.fields;
        restoreFields(fields, person.ticketValues, person.ticketKey);
        return FormTicketModel(
            ticketValues: fields,
            ticketKey: GlobalKey<FormBuilderState>(),
            ticketId: person.ticketId,
            seat: refreshedSeats[person.seat?.seat?.id]);
      }).toList();
      formSession?.dispose();
      setState(() {
        _formKey = GlobalKey<FormBuilderState>();
        form = refreshed;
        formHolder = holder;
        _changedCapacityForm = null;
        _paymentChangeReason = null;
        holder.controller = FormHolderController(
            globalKey: _formKey,
            secret: refreshed.definition.secret,
            blueprintId: refreshed.definition.blueprint,
            formKey: refreshed.definition.key,
            showSeatReservation: _showSeatReservation,
            onCloseSeatReservation: _hideSeatReservation);
        formSession =
            FormSession(form: refreshed, formHolder: holder, formKey: _formKey);
        formSession!.addListener(() {
          if (mounted) setState(() {});
        });
        holder.controller!.updateTotalPrice = formSession!.recalculateTotals;
      });
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      formSession!.recalculateTotals();
      if (review && !refreshed.definition.isWaitlist)
        await _showOrderPreview(context);
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(PaymentMethodStrings.text('refreshFailed'))));
    } finally {
      if (mounted) setState(() => _refreshingChangedForm = false);
    }
  }

  void _populateOfferPeople() {
    final ticket = formHolder!.getTicket();
    if (ticket == null) return;
    ticket.fixedTickets = true;
    ticket.maxTickets = (_offerBundle!['pendingCount'] as num?)?.toInt() ?? 0;
    for (final t in ticket.tickets) {
      for (final field in t.ticketValues) {
        if (t.ticketKey.currentState != null)
          field.defaultValue = field.getValue(t.ticketKey);
      }
      if (t.ticketId != null) _ticketDrafts[t.ticketId!] = t;
    }
    final existing = _ticketDrafts;
    ticket.tickets = [
      for (final person in _offerBundle!['tickets'] as List)
        if (_selectedTicketIds.contains(person['id']))
          existing[person['id']] ?? _personTicket(person),
    ];
    final values = <String, dynamic>{};
    for (final field in _offerBundle!['orderData']?['fields'] ?? []) {
      values.addAll(Map<String, dynamic>.from(field));
    }
    for (final field in formHolder!.fields) {
      if (values.containsKey(field.id.toString()))
        field.defaultValue = values[field.id.toString()];
    }
  }

  FormTicketModel _personTicket(dynamic person) {
    final fields =
        FormHolder.fromDefinition(form!.definition).getTicket()!.fields;
    final answers = <String, dynamic>{};
    for (final field in person['answers']?['fields'] ?? []) {
      answers.addAll(Map<String, dynamic>.from(field));
    }
    for (final field in fields) {
      if (answers.containsKey(field.id.toString()))
        field.defaultValue = answers[field.id.toString()];
    }
    return FormTicketModel(
        ticketId: person['id'],
        ticketValues: fields,
        ticketKey: GlobalKey<FormBuilderState>());
  }

  void _replaceOverviewUrl() {
    if (!_showOverview || _overviewScope == null) return;
    RouterService.changeUrl(_overviewScope!.uri.toString());
  }

  Future<void> _resolveOverviewAccess() async {
    final token = _waitlistToken;
    final offerId = _offerId;
    final orderId = _waitlistOrderId;
    bool current() =>
        mounted &&
        token == _waitlistToken &&
        offerId == _offerId &&
        orderId == _waitlistOrderId;
    try {
      final scope = await _waitlist.overviewAccess(
          token: token, offerId: offerId, orderId: orderId);
      if (current())
        setState(() {
          _overviewScope = scope;
          _overviewAccessFailed = false;
        });
    } catch (_) {
      if (current()) setState(() => _overviewAccessFailed = true);
    }
  }

  Widget _buildOverview() {
    final scope = _overviewScope;
    if (scope == null) {
      if (!_overviewAccessFailed) return const SizedBox.shrink();
      return Column(children: [
        Text(OrderOverviewStrings.text('failed')),
        TextButton(
            onPressed: _resolveOverviewAccess,
            child: Text(WaitlistStrings.refresh)),
      ]);
    }
    return CustomerOrderOverviewView(
      key: ValueKey((scope, _showOverview)),
      load: () async {
        final result = await _waitlist.overview(scope);
        final canonical = result.root['formLink'] as String?;
        RouterService.canonicalizePublicLink(
            'form', widget.formLink, canonical);
        if (canonical != null) widget.formLink = canonical;
        return result;
      },
      offerInPage: !_showOverview,
      onContinue: _offerId == null || !_showOverview
          ? null
          : () async {
              try {
                final bundle = await _waitlist.read(
                    token: _waitlistToken, offerId: _offerId);
                if (bundle['form'] == null ||
                    (bundle['pendingCount'] as num? ?? 0) == 0) return;
                if (!mounted ||
                    _overviewScope?.orderId != scope.orderId ||
                    _overviewScope?.token != scope.token) return;
                setState(() => _showOverview = false);
                // Keep the write capability in memory; reload never recovers it from a view token.
                await _loadOfferContinuation();
              } catch (_) {
                /* Keep the overview when the offer is no longer active. */
              }
            },
    );
  }

  Future<void> _loadOfferContinuation() async {
    // The loader reads the in-memory offer scope. Avoid re-parsing the view URL.
    await loadData(continueOffer: true);
  }

  Widget _buildWaitlistPeople({bool manage = false}) {
    final bundle = _offerBundle!;
    final expires = DateTime.tryParse(bundle['expiresAt'] ?? '');
    final expiryLabel = expires == null
        ? ''
        : DateFormat.yMd()
            .add_jm()
            .format(expires.toOccasionTime(bundle['timeZone'] as String?));
    final canDecline = _selectedTicketIds.every((id) =>
        (bundle['slots'] as List)
            .any((s) => s['ticketId'] == id && s['outcome'] == 'pending'));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(
          manage && _offerId != null
              ? WaitlistStrings.expired
              : WaitlistStrings.selectPeople,
          style: Theme.of(context).textTheme.titleLarge),
      if (_offerId != null)
        Wrap(spacing: 16, runSpacing: 4, children: [
          Text(
              '${WaitlistStrings.text('offeredPlaces')}: ${bundle['pendingCount']}'),
          if (expiryLabel.isNotEmpty)
            Text('${WaitlistStrings.expiresAt}: $expiryLabel'),
        ]),
      if (!manage) Text(WaitlistStrings.productAvailability),
      for (final person in bundle['tickets'] as List)
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: Text((person['answers']?['fields'] as List? ?? [])
              .expand((f) => (f as Map).values)
              .join(' · ')),
          subtitle: Text(WaitlistStrings.text(person['lifecycle'])),
          value: _selectedTicketIds.contains(person['id']),
          onChanged: (['admitted', 'cancelled', 'withdrawn']
                      .contains(person['lifecycle']) ||
                  (!manage &&
                      person['lifecycle'] == 'offered' &&
                      !(bundle['slots'] as List).any((s) =>
                          s['ticketId'] == person['id'] &&
                          s['outcome'] == 'pending')))
              ? null
              : (checked) {
                  if (checked == true &&
                      !manage &&
                      _selectedTicketIds.length >=
                          (bundle['pendingCount'] as num)) return;
                  setState(() {
                    if (checked == true) {
                      _selectedTicketIds.add(person['id']);
                    } else {
                      _selectedTicketIds.remove(person['id']);
                    }
                    if (!manage) _populateOfferPeople();
                  });
                },
        ),
      if (_selectedTicketIds.isEmpty) Text(WaitlistStrings.selectPeople),
      if (!manage && !canDecline) Text(WaitlistStrings.text('declineAssigned')),
      if (!manage || _offerId == null)
        TextButton(
          onPressed: _selectedTicketIds.isEmpty || (!manage && !canDecline)
              ? null
              : () => _resolveWaitlist(manage ? 'withdraw' : 'decline'),
          child:
              Text(manage ? WaitlistStrings.withdraw : WaitlistStrings.decline),
        ),
    ]);
  }

  Future<void> _resolveWaitlist(String operation) async {
    final confirmed = await DialogHelper.showConfirmationDialog(
        context, WaitlistStrings.title, WaitlistStrings.confirm);
    if (!confirmed || !mounted) return;
    setState(() => _isLoading = true);
    try {
      await _waitlist.command(operation, {
        if (_offerId != null) 'offerId': _offerId,
        if (_waitlistOrderId != null) 'orderId': _waitlistOrderId,
        if (_waitlistToken != null) 'token': _waitlistToken,
        'ticketIds': _selectedTicketIds.toList()
      });
      await loadData();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${WaitlistStrings.stale} ($e)')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> loadData({bool continueOffer = false}) async {
    setState(() {
      _isLoading = true;
      _fontLoadFailed = false;
      _formNotAvailable = false; // Reset the message flag
      _formLoadFailed = false;
      form = null;
      _terminalIdentity = null;
    });

    if (widget.formLink == null &&
        widget.offerId == null &&
        widget.waitlistOrderId == null) {
      setState(() {
        _isLoading = false;
        _formNotAvailable = true; // Show message if formLink is null
      });
      return;
    }
    //var key = UuidConverter.base62ToUuid(widget.id!);

    try {
      _offerId ??= widget.offerId;
      _waitlistOrderId ??= widget.waitlistOrderId;
      if (!continueOffer && _showOverview && _overviewScope != null) {
        setState(() {
          _isLoading = false;
        });
        return;
      }
      if (_offerId != null || _waitlistOrderId != null) {
        _offerBundle = await _waitlist.read(
            token: _waitlistToken,
            offerId: _offerId,
            orderId: _waitlistOrderId);
        final canonical = (_offerBundle!['form'] as Map?)?['link'] as String? ??
            _offerBundle!['formLink'] as String?;
        RouterService.canonicalizePublicLink(
            'form', widget.formLink, canonical);
        if (canonical != null) widget.formLink = canonical;
        _terminalIdentity = VerifiedOrganizationIdentity.tryParse(
            _offerBundle!['organizationIdentity']);
        if (_offerBundle!['form'] == null) {
          if (mounted)
            setState(() {
              _waitlistMessage = WaitlistStrings.text(
                  _offerBundle!['offerStatus'] ?? 'invalid');
              _isLoading = false;
            });
          return;
        }
        form = FormBundle.fromJson(
            Map<String, dynamic>.from(_offerBundle!['form']));
        unawaited(_resolveOverviewAccess());
      } else
        form = await DbForms.getFormFromLink(widget.formLink!);
      if (form == null) {
        setState(() {
          _isLoading = false;
          _formNotAvailable = true; // Show message if form is not found
        });
        return;
      }

      RouterService.canonicalizePublicLink(
          'form', widget.formLink, form!.definition.link);
      widget.formLink = form!.definition.link;
      if (widget.formLink != null)
        await RightsService.updateAppData(
            formLink: widget.formLink, refreshOffline: false);

      _fonts = null;
      if (form!.definition.fontFamily?.isNotEmpty == true) {
        try {
          _fonts = await FormFontCatalog.load();
          if (form!.definition.data?['design']?['background_mode'] != null)
            await _fonts!.ensureFamily(form!.definition.fontFamily!);
        } catch (error) {
          AppLogger.error('Form font catalog loading failed: $error');
          if (mounted) {
            setState(() {
              _fontLoadFailed = true;
              _isLoading = false;
            });
          }
          return;
        }
      }
      if (!mounted) return;

      formHolder = FormHolder.fromDefinition(form!.definition);
      if (_offerBundle != null) {
        _selectedTicketIds.clear();
        _ticketDrafts.clear();
        for (final slot in _offerBundle!['slots'] as List) {
          if (slot['outcome'] == 'pending')
            _selectedTicketIds.add(slot['ticketId']);
        }
        _populateOfferPeople();
      }

      formSession?.dispose();
      formSession = FormSession(
        form: form!,
        formHolder: formHolder!,
        formKey: _formKey,
      );
      formSession!.addListener(() {
        setState(() {});
      });

      final capabilityStore = form!.demoSimulation
          ? null
          : ReservationCapabilityStore(
              backend: Supabase.instance.client.rest.url,
              formKey: form!.definition.key!);
      final restoredCapability = await capabilityStore?.restore();
      if (!mounted) return;
      formHolder!.controller = FormHolderController(
          secret: restoredCapability?.secret ?? form!.definition.secret,
          blueprintId: form!.definition.blueprint,
          globalKey: _formKey,
          formKey: form!.definition.key!,
          updateTotalPrice: formSession!.recalculateTotals,
          showSeatReservation: _showSeatReservation,
          onCloseSeatReservation: _hideSeatReservation)
        ..capabilityStore = capabilityStore
        ..capability = restoredCapability
        ..reservationExpiresAt = restoredCapability?.expiresAt;
      if (restoredCapability != null &&
          formHolder!.controller!.blueprintId != null) {
        final restoredController = formHolder!.controller!;
        restoredController.reservationPending = true;
        try {
          final source = await DbForms.getBlueprint(restoredController.secret!,
              restoredController.formKey!, restoredController.blueprintId!);
          if (!mounted) return;
          if (source?.layoutSnapshot == null)
            throw StateError('layout_unavailable');
          formSession!.updateSeats(
              BlueprintLayoutAdapter(source!).selectedSeats(source));
          await restoredController.updateReservationSession(
              restoredController.secret!, source.reservationExpiresAt);
          restoredController.reservationPending = false;
        } catch (_) {
          // Keep checkout gated. Opening the picker provides authoritative Retry.
        }
      }

      setState(() {
        _isLoading = false;
      });
    } catch (error, stack) {
      AppLogger.error('Form loading failed: $error\n$stack');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _formLoadFailed = true;
        });
      }
    }
  }
}
