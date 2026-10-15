import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import '../tool/check_architecture.dart';

void main() {
  late Directory root;
  late Directory core;
  setUp(() {
    root = Directory.systemTemp.createTempSync('festapp-purity-');
    core = Directory('${root.path}/packages/festapp_core')
      ..createSync(recursive: true);
    File('${core.path}/pubspec.yaml').writeAsStringSync('name: festapp_core\n');
    Directory('${core.path}/.dart_tool').createSync();
    File('${core.path}/.dart_tool/package_config.json').writeAsStringSync(
      jsonEncode({
        'packages': [
          {'name': 'festapp_core', 'rootUri': '../', 'packageUri': 'lib/'},
        ],
      }),
    );
    Directory('${core.path}/lib/src/sync').createSync(recursive: true);
  });
  tearDown(() => root.deleteSync(recursive: true));
  void source(String path, String content) {
    final file = File('${core.path}/lib/$path');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  test(
    'feature model rejects transitive conditional editor and context imports',
    () {
      final directory = Directory('${root.path}/lib/components/features')
        ..createSync(recursive: true);
      File('${directory.path}/feature.dart').writeAsStringSync(
        "export 'safe.dart' if (dart.library.io) 'indirect.dart';",
      );
      File('${directory.path}/safe.dart').writeAsStringSync('const value = 1;');
      final indirect = File('${directory.path}/indirect.dart');
      Directory('${directory.path}/editors').createSync();
      File(
        '${directory.path}/editors/settings.dart',
      ).writeAsStringSync('const editor = 1;');
      indirect.writeAsStringSync("export 'editors/settings.dart';");
      expect(
        checkFeatureModelBoundaries(root),
        contains(contains('editors/settings.dart')),
      );
      Directory('${root.path}/lib/data_services').createSync();
      File(
        '${root.path}/lib/data_services/rights_service.dart',
      ).writeAsStringSync('class RightsService {}');
      indirect.writeAsStringSync(
        "import '../../data_services/rights_service.dart';",
      );
      expect(
        checkFeatureModelBoundaries(root),
        contains(contains('rights_service.dart')),
      );
      indirect.writeAsStringSync('const value = 2;');
      expect(checkFeatureModelBoundaries(root), isEmpty);
    },
  );
  test('feature models cannot reach routing through AppConfig', () {
    final lib = Directory('${root.path}/lib')..createSync();
    final features = Directory('${lib.path}/components/features')
      ..createSync(recursive: true);
    File(
      '${features.path}/feature.dart',
    ).writeAsStringSync("import '../../app_config.dart';");
    final config = File('${lib.path}/app_config.dart');
    File('${lib.path}/paths.dart').writeAsStringSync("const admin = 'admin';");
    config.writeAsStringSync("import 'paths.dart';");
    expect(checkFeatureModelBoundaries(root), isEmpty);
    final page = File('${lib.path}/components/admin_page.dart');
    page.writeAsStringSync("export '../app_router.dart';");
    File('${lib.path}/app_router.dart').writeAsStringSync('class AppRouter {}');
    config.writeAsStringSync(
      "import 'paths.dart' if (dart.library.io) 'components/admin_page.dart';",
    );
    expect(
      checkFeatureModelBoundaries(root),
      contains(contains('lib/app_router.dart')),
    );
    config.writeAsStringSync("import 'paths.dart';");
    expect(checkFeatureModelBoundaries(root), isEmpty);
  });
  test('command parser owner cannot reach application or Flutter', () {
    source('sync.dart', "export 'src/sync/client_command_response.dart';");
    source(
      'src/sync/client_command_response.dart',
      "import 'package:flutter/widgets.dart';",
    );
    final guard = ArchitectureGuard(root)..check();
    expect(guard.errors, isNotEmpty);
    source(
      'src/sync/client_command_response.dart',
      'class ClientCommandResponse {}',
    );
    expect((ArchitectureGuard(root)..check()).errors, isEmpty);
  });
  test(
    'grid contracts reject conditional renderers and command composition',
    () {
      final directory = Directory('${root.path}/lib/components/eshop')
        ..createSync(recursive: true);
      File('${directory.path}/eshop_column_ids.dart').writeAsStringSync(
        "export 'safe.dart' if (dart.library.io) 'eshop_columns.dart';",
      );
      File('${directory.path}/safe.dart').writeAsStringSync('const id = 1;');
      File(
        '${directory.path}/eshop_columns.dart',
      ).writeAsStringSync('class Columns {}');
      expect(
        checkGridContractBoundaries(root),
        contains(contains('eshop_columns.dart')),
      );
      File(
        '${directory.path}/eshop_column_ids.dart',
      ).writeAsStringSync("export 'safe.dart';");
      File(
        '${directory.path}/safe.dart',
      ).writeAsStringSync("import 'supabase_eshop_commands.dart';");
      File(
        '${directory.path}/supabase_eshop_commands.dart',
      ).writeAsStringSync('class Commands {}');
      expect(
        checkGridContractBoundaries(root),
        contains(contains('supabase_eshop_commands.dart')),
      );
      File('${directory.path}/safe.dart').writeAsStringSync('const id = 1;');
      expect(checkGridContractBoundaries(root), isEmpty);
    },
  );
  test(
    'generic visual themes reject transitive conditional application context',
    () {
      final lib = Directory('${root.path}/lib')..createSync();
      File(
        '${lib.path}/theme_config.dart',
      ).writeAsStringSync("import 'palette.dart';");
      File('${lib.path}/palette.dart').writeAsStringSync(
        "import 'safe.dart' if (dart.library.io) 'router_service.dart';",
      );
      File('${lib.path}/safe.dart').writeAsStringSync('const color = 1;');
      File(
        '${lib.path}/router_service.dart',
      ).writeAsStringSync('class RouterService {}');
      expect(
        checkVisualThemeBoundary(root),
        contains(contains('router_service.dart')),
      );
      File('${lib.path}/palette.dart').writeAsStringSync("import 'safe.dart';");
      expect(checkVisualThemeBoundary(root), isEmpty);
    },
  );
  test('transitive and conditional platform imports are rejected', () {
    source('sync.dart', "export 'src/sync/first.dart';");
    source(
      'src/sync/first.dart',
      "import 'safe.dart' if (dart.library.html) 'ui.dart';",
    );
    source('src/sync/safe.dart', 'const value = 1;');
    source('src/sync/ui.dart', "import 'dart:ui';");
    final guard = ArchitectureGuard(root)..check();
    expect(guard.errors, contains(contains('dart:ui')));
  });
  test('module cycles and foreign internals are rejected', () {
    source('src/forms/form.dart', "import '../eshop/product.dart';");
    source('src/eshop/product.dart', "import '../forms/form.dart';");
    final guard = ArchitectureGuard(root)..check();
    expect(guard.errors, contains(contains('eshop -> forms')));
    expect(guard.errors, contains(contains('Cross-module internal')));
  });
  test('registration detects missing, unused and duplicate cases', () {
    final tests = Directory('${root.path}/test')..createSync();
    File(
      '${tests.path}/example_cases.dart',
    ).writeAsStringSync('void main() {}');
    final entry = File('${tests.path}/area_test.dart');
    entry.writeAsStringSync(
      "import 'example_cases.dart' as cases; void main() {}",
    );
    expect(checkCaseRegistration(root), isNotEmpty);
    entry.writeAsStringSync(
      "import 'example_cases.dart' as cases; void main() { cases.main(); }",
    );
    expect(checkCaseRegistration(root), isEmpty);
    File(
      '${tests.path}/duplicate_test.dart',
    ).writeAsStringSync(entry.readAsStringSync());
    expect(checkCaseRegistration(root), contains(contains('exactly once')));
  });
  test('helper-only cases imports do not register or duplicate main', () {
    final tests = Directory('${root.path}/test')..createSync();
    File(
      '${tests.path}/example_cases.dart',
    ).writeAsStringSync('void main() {} void mount() {}');
    final entry = File('${tests.path}/area_test.dart');
    entry.writeAsStringSync(
      "import 'example_cases.dart' show mount; void main() { mount(); }",
    );
    expect(checkCaseRegistration(root), contains(contains('exactly once')));
    File('${tests.path}/actual_test.dart').writeAsStringSync(
      "import 'example_cases.dart' as cases; void main() { cases.main(); }",
    );
    expect(checkCaseRegistration(root), isEmpty);
    entry.writeAsStringSync(
      "import 'example_cases.dart' hide main; void main() { mount(); }",
    );
    expect(checkCaseRegistration(root), isEmpty);
  });
  test(
    'registration-time resource setup fails while scoped setup is allowed',
    () {
      final testRoot = Directory('${root.path}/test')..createSync();
      final file = File('${testRoot.path}/fixture_test.dart');
      file.writeAsStringSync(
        'void main() { SharedPreferences.setMockInitialValues({}); }',
      );
      expect(
        checkCaseRegistration(root),
        contains(contains('Registration effect')),
      );
      file.writeAsStringSync(
        'void main() { setUp(() { SharedPreferences.setMockInitialValues({}); }); }',
      );
      expect(checkCaseRegistration(root), isEmpty);
    },
  );
  test(
    'fixtures reject private SDK imports and allow the public package API',
    () {
      final directory = Directory('${root.path}/test')..createSync();
      final file = File('${directory.path}/fixture_test.dart');
      file.writeAsStringSync(
        "import 'package:easy_localization/src/localization.dart';",
      );
      expect(
        checkPublicFixtureImports(root),
        contains(contains('Private SDK fixture import')),
      );
      file.writeAsStringSync(
        "import 'package:easy_localization/easy_localization.dart';",
      );
      expect(checkPublicFixtureImports(root), isEmpty);
    },
  );
}
