import 'package:flutter_test/flutter_test.dart';
import 'package:festapp_core/time.dart' as tz;
import 'package:fstapp/components/occasion/occasion_link_model.dart';
import 'package:fstapp/components/single_data_grid/admin_page_helper.dart';
import 'package:fstapp/data_services/rights_service.dart';

import '../../support/fixtures/rights_context_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(tz.OccasionTimeContext.initializeTimeZones);

  for (final role in ['editor', 'read_only']) {
    test('$role invitation enters Forms without exposing order tabs', () {
      final state = RightsContextFixture(
        context: OccasionLinkModel(
          capabilities: {
            'forms.catalog.read': true,
            'forms.write': role == 'editor',
            'navigation.administration': true,
            'email_templates.occasion.read': true,
          },
        ),
      );
      addTearDown(state.dispose);
      expect(RightsService.canAccessReservationsWorkspace(), isTrue);
      expect(RightsService.canSeeReservations(), isFalse);
      final tabs = AdministrationTabs.reservations.map((t) => t.slug).toList();
      expect(tabs.first, 'forms');
      expect(tabs, isNot(contains('orders')));
      expect(tabs, isNot(contains('tickets')));
      expect(tabs, isNot(contains('products')));
      expect(tabs, isNot(contains('report')));
      expect(tabs, isNot(contains('inventory-pools')));
      expect(RightsService.hasCapability('forms.write'), role == 'editor');
    });
  }

  test('order reader retains the existing default and sales sections', () {
    final state = RightsContextFixture(
      context: OccasionLinkModel(
        capabilities: {'orders.read': true, 'forms.catalog.read': true},
      ),
    );
    addTearDown(state.dispose);
    final tabs = AdministrationTabs.reservations.map((t) => t.slug).toList();
    expect(tabs.first, 'orders');
    expect(tabs, containsAll(['tickets', 'forms', 'products', 'report']));
  });

  test('missing or revoked capabilities deny workspace entry', () {
    final state = RightsContextFixture(context: OccasionLinkModel());
    addTearDown(state.dispose);
    expect(RightsService.canAccessReservationsWorkspace(), isFalse);
    expect(RightsService.canSeeReservations(), isFalse);
  });
}
