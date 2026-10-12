import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/services/platform_helper.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('backend request identifies the installed build separately from version',
      () async {
    PackageInfo.setMockInitialValues(
      appName: 'Festapp',
      packageName: 'fixture.festapp',
      version: '0.20.135',
      buildNumber: '619',
      buildSignature: '',
    );
    final headers = await PlatformHelper.getBackendRequestHeaders();
    expect(headers['X-Client-Info'], startsWith('festapp/0.20.135+619/'));
    expect(headers.keys, ['X-Client-Info']);
  });
}
