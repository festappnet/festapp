import '../support/register_client_suites.dart';
import '../components/information/information_save_legacy_reader_cases.dart'
    as suite0;
import '../components/schedule/event_commands_cases.dart' as suite1;

void main() {
  registerClientSuites({
    'information_save_legacy_reader': suite0.main,
    'event_commands': suite1.main,
  });
}
