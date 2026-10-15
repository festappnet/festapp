import 'package:festapp_core/forms.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:festapp_core/eshop.dart';

class FormBundle {
  FormBundle(
      {required this.definition,
      this.occasion,
      this.bankAccount,
      List<BankAccountModel>? availableBankAccounts})
      : availableBankAccounts = availableBankAccounts == null
            ? null
            : List.unmodifiable(availableBankAccounts);
  final FormDefinition definition;
  bool get demoSimulation => definition.demoSimulation;
  final OccasionModel? occasion;
  final BankAccountModel? bankAccount;
  final List<BankAccountModel>? availableBankAccounts;
  Map<String, dynamic> toJson() =>
      definition.copyWith(bankAccountId: bankAccount?.id).toJson();
  FormBundle withDefinition(FormDefinition value) => FormBundle(
      definition: value,
      occasion: occasion,
      bankAccount: bankAccount,
      availableBankAccounts: availableBankAccounts);
  factory FormBundle.fromJson(Map<String, dynamic> json) => FormBundle(
      definition: FormDefinition.fromJson(json),
      occasion: json['occasion'] is Map<String, dynamic>
          ? OccasionModel.fromJson(json['occasion'])
          : null,
      availableBankAccounts: (json['available_bank_accounts'] as List?)
          ?.map((value) => BankAccountModel.fromJson(value))
          .toList());
}
