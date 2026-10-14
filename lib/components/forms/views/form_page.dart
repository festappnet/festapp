import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:intl/intl.dart';
import 'package:fstapp/services/time_helper.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fstapp/components/forms/waitlist_commands.dart';
import 'package:fstapp/components/forms/waitlist_strings.dart';
import 'package:fstapp/components/forms/models/holder_models/form_ticket_model.dart';
import 'package:fstapp/services/dialog_helper.dart';
import 'dart:async';
import 'package:fstapp/components/forms/widgets_view/countdown_widget.dart';
import 'package:fstapp/components/fonts/form_font_catalog.dart';

import 'package:auto_route/auto_route.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:fstapp/components/blueprint/blueprint_seat.dart';
import 'package:fstapp/components/blueprint/seat_reservation/widgets/seat_reservation_widget.dart';
import 'package:fstapp/components/forms/views/reservation_page.dart';
import 'package:fstapp/router_service.dart';
import 'package:fstapp/services/app_logger.dart';
import 'package:fstapp/components/forms/models/form_model.dart';
import 'package:fstapp/components/forms/models/form_option_model.dart';
import 'package:fstapp/components/forms/form_session.dart';
import 'package:fstapp/components/eshop/models/product_type_model.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/components/forms/db_forms.dart';
import 'package:fstapp/components/eshop/db_orders.dart';
import 'package:fstapp/components/forms/views/order_preview_screen.dart';
import 'package:fstapp/components/forms/widgets_view/form_helper.dart';
import 'package:fstapp/components/forms/widgets_view/option_field_helper.dart';
import '../../features/feature_constants.dart';
import '../../features/feature_service.dart';
import 'package:fstapp/services/utilities_all.dart';
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
  String? _offerId;
  int? _waitlistOrderId;
  String? _waitlistToken;
  final Set<int> _selectedTicketIds = {};
  final Map<int, FormTicketModel> _ticketDrafts = {};
  String? _waitlistMessage;
  bool _demoCompleted = false;
  FormModel? _changedCapacityForm;
  bool _isLoading = false;
  bool _formNotAvailable = false;
  FormFontCatalog? _fonts;
  bool _fontLoadFailed = false;

  Map<String, dynamic>? formResult;
  FormHolder? formHolder;
  FormModel? form;
  FormSession? formSession;

  final _formKey = GlobalKey<FormBuilderState>();
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
    if (!_isSeatReservationVisible) return;

    if (seats != null) {
      _isClosingProgrammatically = true;
      RouterService.goBackProgrammatically();
    }

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
          color: form?.primaryColor != null
              ? Color(form!.primaryColor!)
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
                Text(
                  Utilities.formatPrice(context, formSession?.totalPrice ?? 0,
                      currencyCode: formHolder!.controller!.currencyCode),
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
    TextInput.finishAutofillContext();
    final ticket = formHolder?.getTicket();
    if (ticket != null &&
        (ticket.tickets.isEmpty || ticket.tickets.length > ticket.maxTickets)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(WaitlistStrings.text('FORM_CAPACITY_EXCEEDED'))));
      return;
    }
    var valid = await FormHelper.saveValidateAndScroll(formHolder!);
    setState(() {});
    if (valid &&
        !form!.demoSimulation &&
        form!.isWaitlist &&
        _offerBundle == null) {
      final confirmed = await DialogHelper.showConfirmationDialog(
          context, WaitlistStrings.title, WaitlistStrings.explanation);
      if (!confirmed || !mounted) return;
      setState(() => _isLoading = true);
      try {
        final data = FormHelper.getDataFromForm(formHolder!);
        final payload = <String, dynamic>{
          'form': form!.key,
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
              formHolder: formHolder!,
              totalPrice: formSession?.totalPrice ?? 0,
              metaSurchargeSums: formSession?.metaSurchargeSums ?? const {},
              onSendPressed: _sendOrder,
              // When user clicks Close in UI, we just pop the sheet.
              // verification of _isOrderPreviewVisible in whenComplete will handle history sync.

              // verification of _isOrderPreviewVisible in whenComplete will handle history sync.
              onClose: () => Navigator.of(context).pop(),
              tone: form!.data?[FormHelper.metaCommunicationTone],
              hasTickets: FeatureService.isFeatureEnabled(
                  FeatureConstants.ticket,
                  features: form!.occasionModel?.features),
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
    _scrollController.jumpTo(0.0);
  }

  Future<void> _sendOrder() async {
    if (formHolder == null || form == null) return;
    if (form!.demoSimulation) {
      _hideOrderPreview();
      setState(() => _demoCompleted = true);
      return;
    }

    setState(() {
      _isLoading = true;
    });

    var data = FormHelper.getDataFromForm(formHolder!);
    data = FormHelper.replaceSpotWithId(data);
    data[FormHelper.metaSecret] = form!.secret;
    data[FormHelper.metaForm] = form!.key;
    if (formHolder!.paymentType != null) {
      data['payment_type'] = formHolder!.paymentType;
    }
    formResult = data;

    showGeneralDialog(
      context: context,
      barrierDismissible: false, // Disable dismissing by tapping outside
      barrierLabel: "FinishOrderDialog",
      pageBuilder: (context, anim1, anim2) => FinishOrderScreen(
        occasionTitle: form!.occasionModel?.title ?? form!.title,
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
              response.data['errorCode'] == 'FORM_CAPACITY_EXCEEDED' &&
              widget.formLink != null) {
            final latest = await DbForms.getFormFromLink(widget.formLink!);
            if (mounted) setState(() => _changedCapacityForm = latest);
          }
          return response;
        },
        onOrderConfirmed: () async {
          // Reset session tickets?
          // `_formKey.currentState?.reset()` resets the form fields.
          // TicketHolder might need manual reset or re-loadData will handle it.
          // formSession updateSeats([]) is effectively clearing it.
          // But since we use TicketHolder, we should reload data.
          await loadData();
          formSession!.recalculateTotals();
        },
        onSuccess: () async {
          Navigator.of(context).pop(); // Close the OrderPreview BottomSheet
          _scrollToTop();
        },
        tone: form!.data?[FormHelper.metaCommunicationTone],
        hasTickets: FeatureService.isFeatureEnabled(FeatureConstants.ticket,
            features: form!.occasionModel?.features),
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

    setState(() {
      _isLoading = false;
    });
  }

// ... (imports)

  ThemeData _buildFormTheme(BuildContext context) {
    var theme = Theme.of(context);
    var form = this.form; // Use class member

    if (form != null) {
      if (form.fontFamily != null && _fonts != null) {
        try {
          theme = theme.copyWith(
            textTheme: _fonts!.getTextTheme(form.fontFamily!, theme.textTheme),
          );
        } catch (e) {
          AppLogger.error(e.toString());
        }
      }

      int? primaryInt = form.primaryColor;
      int? secondaryInt = form.secondaryColor;

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

  @override
  Widget build(BuildContext context) {
    // Check time limits
    bool isClosed = false;
    bool isBeforeStart = false;

    if (form != null && _offerBundle == null) {
      final now = DateTime.now();
      if (form!.startTime != null && now.isBefore(form!.startTime!)) {
        isClosed = true;
        isBeforeStart = true;
      } else if (form!.endTime != null && now.isAfter(form!.endTime!)) {
        isClosed = true;
      } else if (form!.isOpen == false) {
        isClosed = true;
      }
    }

    dynamic previewParam = context.routeData.queryParams.get('preview', false);
    bool isPreviewParam = previewParam.toString().toLowerCase() == 'true';
    bool canPreview = RightsService.isEditorOrderView();
    // Only allow preview if specifically requested AND user is editor
    bool showPreview = canPreview && isPreviewParam;
    bool showCountdown =
        isBeforeStart && (form?.enableCountdown ?? false) && !showPreview;

    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
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
                  child: Text(_waitlistMessage!))));
    if (_offerBundle != null &&
        (_offerId == null ||
            (_offerBundle!['pendingCount'] as num? ?? 0) == 0)) {
      return Scaffold(
          body: SingleChildScrollView(
              child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: _buildWaitlistPeople(manage: true))));
    }
    if (form?.registrationMode == 'full') {
      return Scaffold(
          body: Center(
              child: SingleChildScrollView(
                  child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: StylesConfig.formMaxWidth),
        child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              if (form?.header != null)
                HtmlView(html: form!.header!, isSelectable: true),
              Text(WaitlistStrings.full),
            ])),
      ))));
    }
    if (_formNotAvailable || (isClosed && !showPreview && !showCountdown)) {
      return Scaffold(body: _buildFormNotAvailableMessage());
    }

    ThemeData theme = _buildFormTheme(context);

    Widget bodyContent;

    if (showCountdown) {
      bodyContent = CountdownWidget(
        targetTime: form!.startTime!,
        title: form!.countdownTitle ?? FormStrings.registrationStart,
        onFinished: () {
          setState(() {
            // Re-evaluate state to show form
          });
        },
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
                                        if (form!.header != null)
                                          Column(
                                            children: [
                                              HtmlView(
                                                  html: form!.header!,
                                                  isSelectable: true),
                                              const SizedBox(height: 16),
                                            ],
                                          ),
                                        if (_changedCapacityForm != null)
                                          Column(children: [
                                            Text(WaitlistStrings.text(
                                                'FORM_CAPACITY_EXCEEDED')),
                                            TextButton(
                                                onPressed:
                                                    _applyChangedCapacity,
                                                child: Text(
                                                    _changedCapacityForm!
                                                            .isWaitlist
                                                        ? WaitlistStrings.text(
                                                            'regularToWaitlist')
                                                        : WaitlistStrings
                                                            .refresh)),
                                          ]),
                                        if (_offerBundle == null &&
                                            form!.isWaitlist)
                                          Text(
                                              '${WaitlistStrings.title}. ${WaitlistStrings.explanation}'),
                                        if (_offerBundle != null)
                                          _buildWaitlistPeople(),
                                        if (_offerBundle == null &&
                                            !form!.isWaitlist &&
                                            form!.capacity?.showRemaining ==
                                                true &&
                                            form!.capacity?.remainingPublic !=
                                                null)
                                          Text(
                                              '${WaitlistStrings.remaining}: ${form!.capacity!.remainingPublic}'),
                                        ...FormHelper.getAllFormFields(
                                            context, _formKey, formHolder!),
                                        const SizedBox(height: 32),
                                        ButtonsHelper.primaryButton(
                                          context: context,
                                          onPressed: (_isLoading ||
                                                  (!form!.isWaitlist &&
                                                      (formSession?.totalProducts ??
                                                              0) ==
                                                          0))
                                              ? null
                                              : () => _showOrderPreview(
                                                  scrollContext),
                                          label: form!.isWaitlist
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
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            _buildSeatReservationOverlay(),
            if (form?.isWaitlist != true) _buildPriceAndTicketInfo(),
          ],
        ),
      );
    }

    return Theme(
      data: theme,
      child: Scaffold(
        body: bodyContent,
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
    String notAvailableText = (form?.headerOff?.isNotEmpty ?? false)
        ? form!.headerOff!
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
        FormOptionModel.metaOptionsName: item.title.toString(),
        FormOptionModel.metaOptionsId: item.id.toString(),
        FormOptionModel.metaOptionsPrice:
            item.price ?? 0.0, // Include price in the options
      });
    }

    return {
      FormHelper.metaType: FormHelper.fieldTypeSelectOne,
      FormHelper.metaOptions: options,
      FormHelper.metaLabel: itemTypeModel.title,
      FormHelper.metaOptionsType: itemType,
    };
  }

  Future<void> _applyChangedCapacity() async {
    final latest = _changedCapacityForm;
    if (latest == null || formHolder == null) return;
    if (latest.isWaitlist &&
        !await DialogHelper.showConfirmationDialog(
            context, WaitlistStrings.title, WaitlistStrings.explanation))
      return;
    if (!mounted) return;
    final previous = FormHelper.getDataFromForm(formHolder!);
    final oldController = formHolder!.controller;
    final holder = FormHolder.fromFormFieldModel(latest)
      ..controller = oldController;
    for (final field in holder.fields) {
      for (final answer in previous['fields'] ?? []) {
        if ((answer as Map).containsKey('${field.id}'))
          field.defaultValue = answer['${field.id}'];
      }
    }
    final people = previous['ticket'] as List? ?? [];
    holder.getTicket()?.tickets = people.map((p) {
      final fields = FormHolder.fromFormFieldModel(latest).getTicket()!.fields;
      for (final field in fields) {
        for (final answer in p['fields'] ?? []) {
          if ((answer as Map).containsKey('${field.id}'))
            field.defaultValue = answer['${field.id}'];
        }
      }
      return FormTicketModel(
          ticketValues: fields, ticketKey: GlobalKey<FormBuilderState>());
    }).toList();
    formSession?.dispose();
    setState(() {
      form = latest;
      formHolder = holder;
      _changedCapacityForm = null;
      formSession =
          FormSession(form: latest, formHolder: holder, formKey: _formKey);
      formSession!.addListener(() {
        if (mounted) setState(() {});
      });
      holder.controller!.updateTotalPrice = formSession!.recalculateTotals;
    });
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
    final fields = FormHolder.fromFormFieldModel(form!).getTicket()!.fields;
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

  Widget _buildWaitlistPeople({bool manage = false}) {
    final bundle = _offerBundle!;
    final expires = DateTime.tryParse(bundle['expiresAt'] ?? '');
    final expiryLabel = expires == null
        ? ''
        : DateFormat('d. M. yyyy HH:mm')
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

  Future<void> loadData() async {
    setState(() {
      _isLoading = true;
      _fontLoadFailed = false;
      _formNotAvailable = false; // Reset the message flag
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
      final fragment = context.routeData.fragment;
      if (fragment.startsWith('waitlist?')) {
        final params = Uri.splitQueryString(fragment.substring(9));
        _waitlistToken ??= params['token'];
        _offerId ??= params['offer_id'];
        _waitlistOrderId ??= int.tryParse(params['order_id'] ?? '');
      }
      if (_offerId != null || _waitlistOrderId != null) {
        _offerBundle = await _waitlist.read(
            token: _waitlistToken,
            offerId: _offerId,
            orderId: _waitlistOrderId);
        if (_offerBundle!['form'] == null) {
          if (mounted)
            setState(() {
              _waitlistMessage = WaitlistStrings.text(
                  _offerBundle!['offerStatus'] ?? 'invalid');
              _isLoading = false;
            });
          return;
        }
        form = FormModel.fromJson(
            Map<String, dynamic>.from(_offerBundle!['form']));
      } else
        form = await DbForms.getFormFromLink(widget.formLink!);
      if (form == null) {
        setState(() {
          _isLoading = false;
          _formNotAvailable = true; // Show message if form is not found
        });
        return;
      }

      if (widget.formLink != null)
        await RightsService.updateAppData(formLink: widget.formLink);

      _fonts = null;
      if (form!.fontFamily?.isNotEmpty == true) {
        try {
          _fonts = await FormFontCatalog.load();
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

      formHolder = FormHolder.fromFormFieldModel(form!);
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

      formHolder!.controller = FormHolderController(
          demoSimulation: form!.demoSimulation,
          secret: form!.secret,
          blueprintId: form!.blueprint,
          globalKey: _formKey,
          formKey: form!.key!,
          updateTotalPrice: formSession!.recalculateTotals,
          showSeatReservation: _showSeatReservation,
          onCloseSeatReservation: _hideSeatReservation);

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _formNotAvailable = true;
      });
    }
  }
}
