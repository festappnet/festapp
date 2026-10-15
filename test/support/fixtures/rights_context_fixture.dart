import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/data_services/synchro_service.dart';
import 'package:fstapp/data_services/update_service.dart';
import 'package:fstapp/router_service.dart';
import 'package:fstapp/services/time_helper.dart';
import 'package:timezone/timezone.dart' as tz;

/// The public application context owned by one root-adapter test. This does not
/// reset private service/plugin internals or replace authorization logic.
class RightsContextFixture {
  final _rights = RightsService.occasionLinkModel;
  final _link = RightsService.currentLink;
  final _routerLink = RouterService.currentOccasionLink;
  final _settings = SynchroService.globalSettingsModel;
  final _time = TimeHelper.currentTime;
  final _zone = tz.local;
  RightsContextFixture() {
    RightsService.currentLink = null;
    RightsService.occasionLinkModelNotifier.value = null;
    RouterService.currentOccasionLink = '';
    SynchroService.globalSettingsModel = null;
    TimeHelper.currentTime = null;
  }
  void dispose() {
    RightsService.occasionLinkModelNotifier.value = _rights;
    RightsService.currentLink = _link;
    RouterService.currentOccasionLink = _routerLink;
    SynchroService.globalSettingsModel = _settings;
    TimeHelper.currentTime = _time;
    tz.setLocalLocation(_zone);
    UpdateService.configurePlatforms(_rights?.organization?.platforms);
  }
}
