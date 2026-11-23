import 'verified_organization_identity.dart';
import 'package:festapp_core/forms.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:festapp_core/eshop.dart';

class FormBundle {
  FormBundle(
      {required this.definition,
      this.aggregateVersion = 0,
      this.customerCancellationAvailable = false,
      this.occasion,
      this.bankAccount,
      this.organizationIdentity,
      List<BankAccountModel>? availableBankAccounts})
      : availableBankAccounts = availableBankAccounts == null
            ? null
            : List.unmodifiable(availableBankAccounts);
  final FormDefinition definition;
  bool get demoSimulation => definition.demoSimulation;
  final int aggregateVersion;
  final bool customerCancellationAvailable;
  final VerifiedOrganizationIdentity? organizationIdentity;
  final OccasionModel? occasion;
  final BankAccountModel? bankAccount;
  final List<BankAccountModel>? availableBankAccounts;
  Map<String, dynamic> toJson() => {
        ...definition.copyWith(bankAccountId: bankAccount?.id).toJson(),
        'aggregate_version': aggregateVersion
      };
  FormBundle withDefinition(FormDefinition value) => FormBundle(
      definition: value,
      aggregateVersion: aggregateVersion,
      customerCancellationAvailable: customerCancellationAvailable,
      organizationIdentity: organizationIdentity,
      occasion: occasion,
      bankAccount: bankAccount,
      availableBankAccounts: availableBankAccounts);
  factory FormBundle.fromJson(Map<String, dynamic> json) => FormBundle(
      definition: FormDefinition.fromJson(json),
      customerCancellationAvailable: json['customer_cancellation_available'] == true,
      aggregateVersion: (json['aggregate_version'] as num?)?.toInt() ?? 0,
      organizationIdentity:
          VerifiedOrganizationIdentity.tryParse(json['organizationIdentity']),
      occasion: json['occasion'] is Map<String, dynamic>
          ? OccasionModel.fromJson(json['occasion'])
          : null,
      availableBankAccounts: (json['available_bank_accounts'] as List?)
          ?.map((value) => BankAccountModel.fromJson(value))
          .toList());
}
