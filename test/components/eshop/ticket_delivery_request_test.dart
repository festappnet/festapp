import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/eshop/db_tickets.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final requests = <Map<String, dynamic>>[];
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://fixture.invalid',
      publishableKey: 'fixture',
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        localStorage: EmptyLocalStorage(),
      ),
      httpClient: MockClient((request) async {
        expect(request.url.path, '/functions/v1/send-tickets');
        requests.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response(
          '{"code":200}',
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
  });
  tearDownAll(() => Supabase.instance.dispose());
  test('first delivery joins paid generation; explicit later resend keeps request identity', () async {
    await DbTickets.sendTicketsToEmail(
      orderId: 42,
      email: 'regression@example.invalid',
      requestId: 'first-click',
      firstDelivery: true,
    );
    await DbTickets.sendTicketsToEmail(
      orderId: 42,
      email: 'regression@example.invalid',
      requestId: 'resend-click',
    );
    expect(requests[0]['firstDelivery'], true);
    expect(requests[1].containsKey('firstDelivery'), false);
    expect(requests[1]['requestId'], 'resend-click');
  });
}
