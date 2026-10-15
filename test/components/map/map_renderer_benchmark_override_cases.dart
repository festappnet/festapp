import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/features/map_feature.dart';
import 'package:fstapp/components/map/map_renderer_benchmark_override.dart';

void main() {
  test('benchmark override can select the retained legacy renderer', () {
    expect(
      MapRendererBenchmarkOverride.resolve(
        OfflineMapRenderer.maplibre,
        value: 'legacy',
        isRelease: false,
      ),
      OfflineMapRenderer.legacy,
    );
  });

  test('release builds always preserve the configured renderer', () {
    expect(
      MapRendererBenchmarkOverride.resolve(
        OfflineMapRenderer.maplibre,
        value: 'legacy',
        isRelease: true,
      ),
      OfflineMapRenderer.maplibre,
    );
  });

  test('unknown benchmark renderer is rejected', () {
    expect(
      () => MapRendererBenchmarkOverride.resolve(
        OfflineMapRenderer.maplibre,
        value: 'unknown',
        isRelease: false,
      ),
      throwsArgumentError,
    );
  });
}
