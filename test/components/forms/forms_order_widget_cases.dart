import 'package:flutter_test/flutter_test.dart';

import 'customer_order_overview_cases.dart' as customer_order_overview;
import 'order_finish_screen_cases.dart' as order_finish_screen;
import 'payment_qr_card_cases.dart' as payment_qr_card;
import 'waitlist_models_cases.dart' as waitlist_models;
import 'waitlist_runtime_cases.dart' as waitlist_runtime;

// Scoped groups share one engine; process-global fixtures stay isolated.
void main() {
  group('customer_order_overview', customer_order_overview.main);
  group('order_finish_screen', order_finish_screen.main);
  group('payment_qr_card', payment_qr_card.main);
  group('waitlist_models', waitlist_models.main);
  group('waitlist_runtime', waitlist_runtime.main);
}
