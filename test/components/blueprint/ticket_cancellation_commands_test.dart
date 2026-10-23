import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fstapp/components/eshop/ticket_commands.dart';
import 'package:fstapp/components/blueprint/blueprint_command_rejection.dart';
import '../../support/fixtures/local_app_storage_fixture.dart';
import '../../support/fixtures/client_command_response_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final expired in [false, true]) {
    test(
        'actual SDK cancellation journal keeps exact approval and UUID after lost response; expired=$expired',
        () async {
      final storage = await LocalAppStorageFixture.open();
      addTearDown(storage.dispose);
      final writes = <Map<String, dynamic>>[];
      final client = SupabaseClient('http://127.0.0.1:9999', 'local-test-key',
          httpClient: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (request.url.path.endsWith('/preview_blueprint_ticket_cancellation'))
          return http.Response(
              jsonEncode({
                'occasionId': 1,
                'blueprintId': 2,
                'requestedSpotIds': [11],
                'affectedSpotIds': [11],
                'ticketIds': [51],
                'seats': [],
                'orders': [],
                'confirmationHash': List.filled(64, 'a').join()
              }),
              200,
              headers: {'content-type': 'application/json'},
              request: request);
        expect(request.url.path, '/rest/v1/rpc/cancel_blueprint_tickets');
        writes.add(body);
        if (writes.length <= 2) throw http.ClientException('lost response');
        return http.Response(
            jsonEncode(commandResponseFixture(body['p_command_id'] as String,
                status: expired ? 'expired' : 'applied',
                code: expired ? 410 : 200,
                data: {
                  'cancelledOrderIds': [61]
                })),
            200,
            headers: {'content-type': 'application/json'},
            request: request);
      }));
      addTearDown(client.dispose);
      final port = SupabaseTicketCommands(client),
          preview = await port.previewCancellation(
              occasionId: 1, organizationId: 3, blueprintId: 2, spotIds: [11]);
      await expectLater(
          port.cancelSelection(preview), throwsA(isA<http.ClientException>()));
      final recovered = port.recoverCancellation(
          occasionId: 1, organizationId: 3, blueprintId: 2);
      if (expired) {
        await expectLater(recovered, throwsA(isA<BlueprintCommandRejection>()));
      } else {
        expect((await recovered)!.cancelledOrderIds, [61]);
      }
      expect(writes.length, 3);
      expect(writes.map((e) => e['p_command_id']).toSet().length, 1);
      expect(writes[0], writes[2]);
    });
  }
}
