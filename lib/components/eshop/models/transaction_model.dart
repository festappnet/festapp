import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/single_data_grid/pluto_abstract.dart';
import 'package:fstapp/components/eshop/models/tb_eshop.dart';
import 'package:fstapp/services/time_helper.dart';
import 'package:fstapp/services/utilities_all.dart';
import 'package:trina_grid/trina_grid.dart';
import 'package:intl/intl.dart';
import 'package:fstapp/components/eshop/orders_strings.dart';
import 'package:fstapp/components/users/user_info_model.dart';

class TransactionModel extends ITrinaRowModel {
  @override
  int? id;
  int? transactionId;
  DateTime? date;
  double? amount;
  String? currency;
  String? counterAccount;
  String? bankCode;
  String? bankName;
  String? ks;
  String? vs;
  String? ss;
  String? userIdentification;
  String? transactionType;
  String? performedBy;
  String? comment;
  int? commandId;
  int? bankAccountId;
  int? paymentInfo;
  DateTime? createdAt;
  String? messageForRecipient;
  String? counterAccountName;
  String? payerReference;
  String? ingestSource;
  String? createdById;
  String? createdByName;
  UserInfoModel? createdBy;

  // Relationships (if any)
  // For example, you might have related BankAccountModel or PaymentInfoModel
  // Uncomment and define these if applicable
  // BankAccountModel? relatedBankAccount;
  // PaymentInfoModel? relatedPaymentInfo;

  static const String metaRelatedBankAccount = "related_bank_account";
  static const String metaRelatedPaymentInfo = "related_payment_info";

  TransactionModel({
    this.id,
    this.transactionId,
    this.date,
    this.amount,
    this.currency,
    this.counterAccount,
    this.bankCode,
    this.bankName,
    this.ks,
    this.vs,
    this.ss,
    this.userIdentification,
    this.transactionType,
    this.performedBy,
    this.comment,
    this.commandId,
    this.bankAccountId,
    this.paymentInfo,
    this.createdAt,
    this.messageForRecipient,
    this.counterAccountName,
    this.payerReference,
    this.ingestSource,
    this.createdById,
    this.createdByName,
    this.createdBy,
    // this.relatedBankAccount,
    // this.relatedPaymentInfo,
  });

  /// Factory constructor to create a TransactionModel from JSON.
  factory TransactionModel.fromJson(Map<String, dynamic> json) {
    return TransactionModel(
      id: json[TbEshop.transactions.id],
      transactionId: json[TbEshop.transactions.transaction_id],
      date: json[TbEshop.transactions.date] != null
          ? DateTime.parse(json[TbEshop.transactions.date])
          : null,
      amount: json[TbEshop.transactions.amount]?.toDouble(),
      currency: json[TbEshop.transactions.currency],
      counterAccount: json[TbEshop.transactions.counter_account],
      bankCode: json[TbEshop.transactions.bank_code],
      bankName: json[TbEshop.transactions.bank_name],
      ks: json[TbEshop.transactions.ks],
      vs: json[TbEshop.transactions.vs],
      ss: json[TbEshop.transactions.ss],
      userIdentification: json[TbEshop.transactions.user_identification],
      transactionType: json[TbEshop.transactions.transaction_type],
      performedBy: json[TbEshop.transactions.performed_by],
      comment: json[TbEshop.transactions.comment],
      commandId: json[TbEshop.transactions.command_id],
      bankAccountId: json[TbEshop.transactions.bank_account_id],
      paymentInfo: json[TbEshop.transactions.payment_info],
      createdAt: json[TbEshop.transactions.created_at] != null
          ? DateTime.parse(
              json[TbEshop.transactions.created_at],
            ).toOccasionTime()
          : null,
      messageForRecipient: json[TbEshop.transactions.message_for_recipient],
      counterAccountName: json[TbEshop.transactions.counter_account_name],
      payerReference: json[TbEshop.transactions.payer_reference],
      ingestSource: json[TbEshop.transactions.ingest_source],
      createdById: json['created_by'],
      createdByName: json['createdByName'],
      // relatedBankAccount: json[TbEshop.transactions.bank_account_id] != null
      //     ? BankAccountModel.fromJson(jsonRelatedBankAccount)
      //     : null,
      // relatedPaymentInfo: json[TbEshop.transactions.payment_info] != null
      //     ? PaymentInfoModel.fromJson(jsonRelatedPaymentInfo)
      //     : null,
    );
  }

  /// Converts the TransactionModel instance to a TrinaRow for the data grid.
  @override
  TrinaRow toTrinaRow(BuildContext context) {
    return TrinaRow(
      cells: {
        TbEshop.transactions.id: TrinaCell(value: id ?? 0),
        TbEshop.transactions.transaction_id: TrinaCell(
          value: transactionId ?? 0,
        ),
        TbEshop.transactions.date: TrinaCell(
          value: date != null
              ? DateFormat('yyyy-MM-dd HH:mm:ss').format(date!)
              : "",
        ),
        TbEshop.transactions.amount: TrinaCell(
          value: amount != null ? Utilities.formatPrice(context, amount!) : "",
        ),
        TbEshop.transactions.currency: TrinaCell(value: currency ?? ""),
        TbEshop.transactions.counter_account: TrinaCell(
          value: counterAccount ?? "",
        ),
        TbEshop.transactions.bank_code: TrinaCell(value: bankCode ?? ""),
        TbEshop.transactions.bank_name: TrinaCell(value: bankName ?? ""),
        TbEshop.transactions.ks: TrinaCell(value: ks ?? ""),
        TbEshop.transactions.vs: TrinaCell(value: vs ?? ""),
        TbEshop.transactions.ss: TrinaCell(value: ss ?? ""),
        TbEshop.transactions.user_identification: TrinaCell(
          value: userIdentification ?? "",
        ),
        TbEshop.transactions.transaction_type: TrinaCell(
          value: transactionType == 'manual'
              ? OrdersStrings.transactionTypeCash
              : (transactionType ?? ""),
        ),
        TbEshop.transactions.performed_by: TrinaCell(value: performedBy ?? ""),
        TbEshop.transactions.comment: TrinaCell(value: comment ?? ""),
        TbEshop.transactions.command_id: TrinaCell(value: commandId ?? 0),
        TbEshop.transactions.bank_account_id: TrinaCell(
          value: bankAccountId ?? 0,
        ),
        TbEshop.transactions.payment_info: TrinaCell(value: paymentInfo ?? 0),
        TbEshop.transactions.created_at: TrinaCell(
          value: createdAt != null
              ? DateFormat('yyyy-MM-dd HH:mm:ss').format(createdAt!)
              : "",
        ),
        TbEshop.transactions.message_for_recipient: TrinaCell(
          value: messageForRecipient ?? "",
        ),
        TbEshop.transactions.counter_account_name: TrinaCell(
          value: counterAccountName ?? "",
        ),
        TbEshop.transactions.payer_reference: TrinaCell(
          value: payerReference ?? "",
        ),
        TbEshop.transactions.ingest_source: TrinaCell(
          value: ingestSource ?? "",
        ),
        // Add related entities if necessary
        // metaRelatedBankAccount: TrinaCell(
        //     value: relatedBankAccount != null
        //         ? relatedBankAccount!.toBasicString()
        //         : ""),
        // metaRelatedPaymentInfo: TrinaCell(
        //     value: relatedPaymentInfo != null
        //         ? relatedPaymentInfo!.toBasicString()
        //         : ""),
      },
    );
  }

  /// Factory method to create a TransactionModel from a TrinaRow JSON.
  static TransactionModel fromPlutoJson(Map<String, dynamic> json) {
    return TransactionModel(
      id: json[TbEshop.transactions.id] == -1
          ? null
          : json[TbEshop.transactions.id],
      transactionId: json[TbEshop.transactions.transaction_id],
      amount: (json[TbEshop.transactions.amount] ?? 0).toDouble(),
      currency: json[TbEshop.transactions.currency],
      counterAccount: json[TbEshop.transactions.counter_account],
      bankCode: json[TbEshop.transactions.bank_code],
      bankName: json[TbEshop.transactions.bank_name],
      ks: json[TbEshop.transactions.ks],
      vs: json[TbEshop.transactions.vs],
      ss: json[TbEshop.transactions.ss],
      userIdentification: json[TbEshop.transactions.user_identification],
      transactionType: json[TbEshop.transactions.transaction_type],
      performedBy: json[TbEshop.transactions.performed_by],
      comment: json[TbEshop.transactions.comment],
      commandId: json[TbEshop.transactions.command_id],
      bankAccountId: json[TbEshop.transactions.bank_account_id],
      paymentInfo: json[TbEshop.transactions.payment_info],
      messageForRecipient: json[TbEshop.transactions.message_for_recipient],
      counterAccountName: json[TbEshop.transactions.counter_account_name],
      payerReference: json[TbEshop.transactions.payer_reference],
      ingestSource: json[TbEshop.transactions.ingest_source],
      // relatedBankAccount: json[TbEshop.transactions.bank_account_id] != null
      //     ? BankAccountModel.fromJson(jsonRelatedBankAccount)
      //     : null,
      // relatedPaymentInfo: json[TbEshop.transactions.payment_info] != null
      //     ? PaymentInfoModel.fromJson(jsonRelatedPaymentInfo)
      //     : null,
    );
  }

  /// Deletes the transaction using the DbEshop service.
  @override
  Future<void> deleteMethod(BuildContext context) async {
    throw Exception("Not implemented.");
  }

  /// Updates the transaction using the DbEshop service.
  @override
  Future<void> updateMethod(BuildContext context) async {
    throw Exception("Not implemented.");
  }

  /// Returns a basic string representation of the transaction.
  @override
  String toBasicString() => "Transaction #$transactionId";

  String get formattedBankAccount {
    String accountPart = "";
    if (counterAccount != null && counterAccount!.isNotEmpty) {
      accountPart = counterAccount!;
      if (bankCode != null && bankCode!.isNotEmpty) {
        accountPart += "/$bankCode";
      }
    } else if (bankCode != null && bankCode!.isNotEmpty) {
      accountPart = bankCode!;
    }

    if (bankName != null && bankName!.isNotEmpty) {
      if (accountPart.isNotEmpty) {
        return "$accountPart ($bankName)";
      }
      return bankName!;
    }

    return accountPart;
  }
}
