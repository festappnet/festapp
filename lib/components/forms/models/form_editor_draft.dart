import 'package:festapp_core/forms.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:festapp_core/eshop.dart';
import 'form_field_draft.dart';
import 'form_bundle.dart';

/// Owned by one editor/session. Child drafts are detached from definition;
/// freeze is the sole boundary that assembles a complete immutable definition.
class FormEditorDraft {
  FormDefinition definition;
  OccasionModel? occasionModel;
  BankAccountModel? bankAccount;
  List<BankAccountModel>? availableBankAccounts;
  List<FormFieldDraft> relatedFields;
  final Set<int> deletedFieldIds = {};
  final Set<int> deletedProductIds = {};
  FormEditorDraft({
    int? participantCapacity,
    bool waitlistEnabled = false,
    bool showRemainingCapacity = true,
    int? waitlistOfferDurationSeconds,
    FormCapacityModel? capacity,
    String? registrationMode,
    int? id,
    DateTime? createdAt,
    String? title,
    Map<String, dynamic>? data,
    String? key,
    int? occasionId,
    this.occasionModel,
    int? blueprint,
    String? type,
    this.bankAccount,
    int? bankAccountId,
    int? deadlineDurationSeconds,
    bool? isOpen,
    String? accountNumber,
    String? secret,
    String? header,
    String? headerOff,
    String? link,
    List<FormFieldDraft>? relatedFields,
    this.availableBankAccounts,
    FormStatsModel? stats,
    bool? isReminderEnabled,
    bool? canDelete,
  })  : definition = FormDefinition(
            participantCapacity: participantCapacity,
            waitlistEnabled: waitlistEnabled,
            showRemainingCapacity: showRemainingCapacity,
            waitlistOfferDurationSeconds: waitlistOfferDurationSeconds,
            capacity: capacity,
            registrationMode: registrationMode,
            id: id,
            createdAt: createdAt,
            title: title,
            data: data,
            key: key,
            occasionId: occasionId,
            blueprint: blueprint,
            type: type,
            bankAccountId: bankAccountId,
            deadlineDurationSeconds: deadlineDurationSeconds,
            isOpen: isOpen,
            accountNumber: accountNumber,
            secret: secret,
            header: header,
            headerOff: headerOff,
            link: link,
            stats: stats,
            isReminderEnabled: isReminderEnabled,
            canDelete: canDelete),
        relatedFields = List.of(relatedFields ?? const []);

  FormEditorDraft.fromBundle(FormBundle bundle)
      : definition = bundle.definition
            .copyWith(relatedFields: const <FormFieldDefinition>[]),
        relatedFields = bundle.definition.relatedFields
            .map(FormFieldDraft.fromDefinition)
            .toList(),
        occasionModel = bundle.occasion,
        bankAccount = bundle.bankAccount,
        availableBankAccounts = bundle.availableBankAccounts == null
            ? null
            : List.of(bundle.availableBankAccounts!);
  factory FormEditorDraft.fromJson(Map<String, dynamic> json) =>
      FormEditorDraft.fromBundle(FormBundle.fromJson(json));
  bool get usesSeatSelection => FormDefinition.usesSeatSelectionIn(
      relatedFields.map((field) => field.definition));
  FormDefinition freeze() => definition.copyWith(
      relatedFields: relatedFields.map((field) => field.freeze()).toList());
  FormBundle toBundle() => FormBundle(
      definition: freeze(),
      occasion: occasionModel,
      bankAccount: bankAccount,
      availableBankAccounts: availableBankAccounts);
  Map<String, dynamic> toJson() =>
      freeze().copyWith(bankAccountId: bankAccount?.id).toJson();
  Map<String, dynamic> toEditedJson() {
    final result = toJson()
      ..remove('account_number')
      ..remove('secret');
    result['form_fields'] = result.remove('fields');
    result['deleted_field_ids'] = deletedFieldIds.toList();
    result['deleted_product_ids'] = deletedProductIds.toList();
    return result;
  }

  void removeField(FormFieldDraft field) {
    final removed = [
      field,
      if (field.definition.type == 'ticket')
        ...relatedFields.where((f) => f.definition.isTicketField == true)
    ];
    for (final item in removed) {
      if (item.definition.id != null) deletedFieldIds.add(item.definition.id!);
      relatedFields.remove(item);
    }
  }

  /// Returns a list of available supported currencies.
  List<String> getSupportedCurrencies() {
    if (bankAccount != null && bankAccount!.supportedCurrencies.isNotEmpty) {
      return bankAccount!.supportedCurrencies;
    } else if (availableBankAccounts != null) {
      final currencySet = <String>{};
      for (var account in availableBankAccounts!) {
        currencySet.addAll(account.supportedCurrencies);
      }
      return currencySet.toList();
    } else {
      return [];
    }
  }

  @override
  String toString() => definition.toString();
}
