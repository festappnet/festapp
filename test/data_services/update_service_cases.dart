import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/organization/organization_model.dart';
import 'package:fstapp/data_services/update_service.dart';

void main() {
  final platforms = [
    PlatformModel(
      platform: 'web',
      prompt: '99.0.0',
      link: 'https://example.test/web',
    ),
    PlatformModel(
      platform: 'ios',
      prompt: '2.0.0',
      link: 'https://apps.apple.com/app/example',
    ),
    PlatformModel(
      platform: 'droid',
      prompt: '3.0.0',
      link: 'https://play.google.com/store/apps/details?id=example',
    ),
  ];

  test('web and PWA never resolve a native app update target', () {
    expect(UpdateService.resolveNativeTarget(platforms, 'web'), isNull);
    expect(UpdateService.resolveNativeTarget(platforms, 'pwa'), isNull);
    expect(UpdateService.resolveNativeTarget(platforms, null), isNull);
  });

  test('iOS and Android resolve only their own store target', () {
    expect(
      UpdateService.resolveNativeTarget(platforms, 'ios')?.link,
      'https://apps.apple.com/app/example',
    );
    expect(
      UpdateService.resolveNativeTarget(platforms, 'droid')?.link,
      'https://play.google.com/store/apps/details?id=example',
    );
  });

  test('incomplete native target is ignored instead of falling back to web',
      () {
    expect(
      UpdateService.resolveNativeTarget([
        platforms.first,
        PlatformModel(platform: 'ios', prompt: '2.0.0'),
      ], 'ios'),
      isNull,
    );
  });

  test('semantic version comparison tolerates different segment counts', () {
    expect(UpdateService.isVersionOutdated('1.2.3', '1.2.4'), isTrue);
    expect(UpdateService.isVersionOutdated('1.2', '1.2.0'), isFalse);
    expect(UpdateService.isVersionOutdated('2.0.0', '1.9.9'), isFalse);
    expect(UpdateService.isVersionOutdated('1.2.3+42', '1.2.3'), isFalse);
    expect(UpdateService.isVersionOutdated('invalid', '2.0.0'), isFalse);
  });
}
