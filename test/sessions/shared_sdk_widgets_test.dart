import '../support/register_client_suites.dart';
import '../components/bank_accounts/bank_adapter_fixture_cases.dart' as suite0;
import '../components/bank_accounts/unit_bank_accounts_add_cases.dart'
    as suite1;
import '../components/html/html_media_upload_contract_cases.dart' as suite2;
import '../components/news/news_page_render_cases.dart' as suite3;

void main() {
  registerClientSuites({
    'bank_adapter_fixture': suite0.main,
    'unit_bank_accounts_add': suite1.main,
    'html_media_upload_contract': suite2.main,
    'news_page_render': suite3.main,
  });
}
