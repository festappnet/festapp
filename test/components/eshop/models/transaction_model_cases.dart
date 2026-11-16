import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/eshop/models/transaction_model.dart';
import 'package:fstapp/components/eshop/models/tb_eshop.dart';

void main() {
  group('TransactionModel', () {
    test('provider dispute is a status fact without a signed cash amount', () {
      final dispute = TransactionModel.fromJson({
        'source': 'provider',
        'sourceId': 'account:dispute:dp_1',
        'provider': 'stripe',
        'transaction_type': 'dispute',
        'status': 'under_review',
        'heldAmount': 200,
        'amount': null,
      });
      expect(dispute.amount, isNull);
      expect(dispute.heldAmount, 200);
      expect(dispute.status, 'under_review');
      expect(dispute.sourceId, 'account:dispute:dp_1');
      expect(dispute.isRefund, isFalse);
    });
    test('fromJson correctly parses comment field', () {
      final json = {
        TbEshop.transactions.id: 1,
        TbEshop.transactions.transaction_id: 12345,
        TbEshop.transactions.amount: 200.0,
        TbEshop.transactions.currency: 'CZK',
        TbEshop.transactions.transaction_type: 'manual',
        TbEshop.transactions.comment: 'Test Note Content',
        TbEshop.transactions.vs: null,
      };

      final transaction = TransactionModel.fromJson(json);

      expect(transaction.amount, 200.0);
      expect(transaction.transactionType, 'manual');
      expect(transaction.comment, 'Test Note Content'); // Verifies mapping
      expect(transaction.vs, isNull);
    });

    test('fromJson correctly parses legacy message_for_recipient if comment is missing', () {
      final json = {
        TbEshop.transactions.id: 2,
        TbEshop.transactions.transaction_id: 67890,
        TbEshop.transactions.amount: 100.0,
        TbEshop.transactions.message_for_recipient: 'Legacy Message',
      };

      final transaction = TransactionModel.fromJson(json);

      expect(transaction.messageForRecipient, 'Legacy Message');
      expect(transaction.comment, isNull);
    });
  });
}
