import 'package:flutter_test/flutter_test.dart';

import 'default_product_price_cases.dart' as default_product_price;
import 'form_payment_defaults_cases.dart' as form_payment_defaults;
import 'ticket_seat_toggle_cases.dart' as ticket_seat_toggle;
import 'product_price_grouping_cases.dart' as product_price_grouping;
import 'form_editor_actions_cases.dart' as form_editor_actions;
import 'form_field_mobile_layout_cases.dart' as form_field_mobile_layout;

// Scoped groups share one engine; process-global fixtures stay isolated.
void main() {
  group('default_product_price', default_product_price.main);
  group('form_payment_defaults', form_payment_defaults.main);
  group('ticket_seat_toggle', ticket_seat_toggle.main);
  group('product_price_grouping', product_price_grouping.main);
  group('form_editor_actions', form_editor_actions.main);
  group('form_field_mobile_layout', form_field_mobile_layout.main);
}
