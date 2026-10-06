import 'package:fstapp/components/eshop/eshop_columns.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:trina_grid/trina_grid.dart';
import 'package:fstapp/components/single_data_grid/pluto_abstract.dart';
import 'package:fstapp/services/time_helper.dart';
import 'email_delivery_strings.dart';

/// Redacted reporting metadata. Delivery history has no write operations.
class EmailDeliveryModel implements ITrinaRowModel {
  static const reference = 'email_model';
  @override
  final int id;
  final String messageId;
  final int? orderId;
  final String? orderSymbol;
  final DateTime? createdAt;
  final String kind;
  final String state;

  EmailDeliveryModel.fromJson(Map<String, dynamic> json)
      : id = (json['id'] as num).toInt(),
        messageId = json['message_id'] as String,
        orderId = (json['order_id'] as num?)?.toInt(),
        orderSymbol = json['order_symbol'] as String?,
        createdAt = json['created_at'] == null
            ? null
            : DateTime.parse(json['created_at'] as String),
        kind = json['message_kind'] as String,
        state = json['state'] as String;

  static EmailDeliveryModel fromPlutoJson(Map<String, dynamic> json) =>
      json[reference] as EmailDeliveryModel;

  /// Drain the authorized keyset pages before applying the standard grid's
  /// local sorting/filtering, so a filter never silently covers only one page.
  static Future<List<EmailDeliveryModel>> loadHistory(
      Future<dynamic> Function(String, Map<String, dynamic>) read,
      Map<String, dynamic> scope) async {
    final rows = <EmailDeliveryModel>[];
    int? before;
    while (true) {
      final result = await read('get_email_delivery_page', {
        ...scope,
        'p_limit': 100,
        if (before != null) 'p_before': before,
      });
      if (result is! List) throw const FormatException('Invalid email history');
      final page = result
          .map((row) => EmailDeliveryModel.fromJson(
              Map<String, dynamic>.from(row as Map)))
          .toList();
      int? previous = before;
      for (final row in page) {
        if (previous != null && row.id >= previous) {
          throw const FormatException('Email history cursor did not advance');
        }
        previous = row.id;
      }
      rows.addAll(page);
      if (page.length < 100) return rows;
      before = page.last.id;
    }
  }

  @override
  TrinaRow toTrinaRow(BuildContext context) => TrinaRow(cells: {
        'id': TrinaCell(value: id),
        EshopColumns.ORDER_SYMBOL: TrinaCell(value: orderSymbol ?? ''),
        'created_at': TrinaCell(
            value: createdAt == null
                ? ''
                : DateFormat('yyyy-MM-dd HH:mm')
                    .format(createdAt!.toOccasionTime())),
        'kind': TrinaCell(value: EmailDeliveryStrings.kind(kind)),
        'state': TrinaCell(value: EmailDeliveryStrings.state(state)),
        'detail': TrinaCell(value: ''),
        reference: TrinaCell(value: this),
      });

  @override
  Future<void> deleteMethod(BuildContext context) async =>
      throw UnsupportedError('Email history is read-only');
  @override
  Future<void> updateMethod(BuildContext context) async =>
      throw UnsupportedError('Email history is read-only');
  @override
  String toBasicString() => '$id';
}
