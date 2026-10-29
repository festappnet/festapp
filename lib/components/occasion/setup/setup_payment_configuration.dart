import 'package:festapp_core/forms.dart';

/// Projects wizard payment controls onto its sole persisted form settings.
/// Payment method/account are separate wizard intent consumed by SQL finalize.
/// No VS default or allocation is manufactured here, including for copies.
class SetupPaymentConfiguration {
  static Object? policy(Map<String, dynamic> draft) =>
      ((draft['formDraft'] as Map?)?['data'] as Map?)?['variable_symbol'];

  static bool validPolicy(Map<String, dynamic> draft) =>
      formVariableSymbolPolicyValid(policy(draft));

  static Map<String, dynamic> projectForm(Map<String, dynamic> draft) {
    final form = Map<String, dynamic>.from(draft['formDraft'] as Map);
    final days = int.tryParse(draft['deadline'] as String? ?? '');
    form['deadline_duration_seconds'] = days == null ? null : days * 86400;
    return form;
  }

  static void repairPolicy(
    Map<String, dynamic> draft,
    Map<String, dynamic> policy,
  ) {
    final form = Map<String, dynamic>.from(draft['formDraft'] as Map);
    form['data'] = {
      ...Map<String, dynamic>.from(form['data'] as Map? ?? {}),
      'variable_symbol': Map<String, dynamic>.from(policy),
    };
    draft['formDraft'] = form;
  }
}
