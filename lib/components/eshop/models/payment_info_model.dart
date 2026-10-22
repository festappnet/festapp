import 'package:festapp_core/eshop.dart';
export 'package:festapp_core/eshop.dart' show BankSyncWarning, BankSyncContact;
import 'package:fstapp/components/eshop/models/tb_eshop.dart';

class PaymentInfoModel {
  int? id;
  DateTime? createdAt;
  int? bankAccount;
  int? variableSymbol;
  String? creditorReference;
  double? amount;
  double? depositAmount;
  DateTime? depositDeadline;
  double? paid;
  double? returned;
  DateTime? deadline;
  String? currencyCode;
  String? paymentMethod;
  bool get isStripe => paymentMethod == 'stripe';
  Map<String, dynamic>? data;
  bool? isReminderSent;
  BankSyncWarning? bankSyncWarning;

  factory PaymentInfoModel.fromJson(Map<String, dynamic> json) {
    final data = json[TbEshop.payment_info.data] as Map<String, dynamic>?;
    return PaymentInfoModel(
      bankSyncWarning: json['bank_sync_warning'] is Map<String, dynamic>
          ? BankSyncWarning.fromJson(json['bank_sync_warning'])
          : null,
      id: json[TbEshop.payment_info.id],
      createdAt: json[TbEshop.payment_info.created_at] != null
          ? DateTime.parse(json[TbEshop.payment_info.created_at])
          : null,
      bankAccount: json[TbEshop.payment_info.bank_account],
      variableSymbol: json[TbEshop.payment_info.variable_symbol],
      creditorReference: json[TbEshop.payment_info.creditor_reference],
      amount: json[TbEshop.payment_info.amount] != null
          ? double.tryParse(json[TbEshop.payment_info.amount].toString())
          : null,
      depositAmount: json[TbEshop.payment_info.deposit_amount] != null
          ? double.tryParse(
              json[TbEshop.payment_info.deposit_amount].toString(),
            )
          : null,
      depositDeadline: json[TbEshop.payment_info.deposit_deadline] != null
          ? DateTime.parse(json[TbEshop.payment_info.deposit_deadline])
          : null,
      paid: json[TbEshop.payment_info.paid] != null
          ? double.tryParse(json[TbEshop.payment_info.paid].toString())
          : null,
      returned: json[TbEshop.payment_info.returned] != null
          ? double.tryParse(json[TbEshop.payment_info.returned].toString())
          : null,
      deadline: json[TbEshop.payment_info.deadline] != null
          ? DateTime.parse(json[TbEshop.payment_info.deadline])
          : null,
      currencyCode: json[TbEshop.payment_info.currency_code],
      paymentMethod: json['payment_method'] as String?,
      data: data,
      isReminderSent: data?['current_version_reminded'] == true,
    );
  }

  String toBasicString() => id != null ? "Payment Info #$id" : "Payment Info";

  PaymentInfoModel({
    this.bankSyncWarning,
    this.id,
    this.createdAt,
    this.bankAccount,
    this.variableSymbol,
    this.creditorReference,
    this.amount,
    this.depositAmount,
    this.depositDeadline,
    this.paid,
    this.returned,
    this.deadline,
    this.currencyCode,
    this.paymentMethod,
    this.data,
    this.isReminderSent = false,
  });
}
