import 'package:flutter_test/flutter_test.dart';

import 'eshop_commands_cases.dart' as suite0;
import 'order_commands_cases.dart' as suite1;
import 'order_grid_permissions_cases.dart' as suite2;
import 'password_reset_result_cases.dart' as suite3;
import 'ticket_commands_cases.dart' as suite5;
import 'product_schedule_commands_cases.dart' as suite6;

import 'models/transaction_model_cases.dart' as transaction_model;

// Scoped groups share one engine; process-global fixtures stay isolated.
void main() {
  group('eshop_commands', suite0.main);
  group('order_commands', suite1.main);
  group('order_grid_permissions', suite2.main);
  group('password_reset_result', suite3.main);
  group('ticket_commands', suite5.main);
  group('product_schedule_commands', suite6.main);
  group('transaction_model', transaction_model.main);
}
