import '../support/register_client_suites.dart';
import '../data_services/form_editor_rpc_test.dart' as suite;

import '../components/forms/form_bank_account_picker_test.dart' as picker;

void main() => registerClientSuites({
  'form_editor_rpc_test': suite.main,
  'form_bank_account_picker': picker.main,
});
