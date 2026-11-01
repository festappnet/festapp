import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:yaml/yaml.dart';

/// Parse SDK-compatible Dart ASTs, including every conditional branch.
Iterable<String> directiveUris(CompilationUnit unit) sync* {
  for (final directive in unit.directives) {
    if (directive is UriBasedDirective) {
      if (directive.uri.stringValue case final value?) yield value;
      if (directive is NamespaceDirective) {
        for (final configuration in directive.configurations) {
          if (configuration.uri.stringValue case final value?) yield value;
        }
      }
    }
  }
}

class ArchitectureGuard {
  ArchitectureGuard(this.root);
  final Directory root;
  final errors = <String>[];
  final _visited = <String>{};
  late final Directory core = Directory('${root.path}/packages/festapp_core');
  late final Map<String, Uri> packages = _packages();
  static const modules = {'sync', 'forms', 'eshop', 'program', 'map', 'time'};
  static const edges = {
    'forms': {'eshop', 'json_values'},
    'program': {'map', 'json_values', 'time'},
    'eshop': {'json_values', 'time', 'formatting'},
    'email_templates': {'formatting'},
    'map': {'json_values'},
  };

  Map<String, Uri> _packages() {
    final config = File('${core.path}/.dart_tool/package_config.json');
    final json = jsonDecode(config.readAsStringSync()) as Map;
    return {
      for (final p in json['packages'] as List)
        p['name'] as String: config.uri.resolve(
          '${(p['rootUri'] as String).replaceFirst(RegExp(r'/$'), '')}/',
        ),
    };
  }

  Uri? resolve(Uri file, String value) {
    final uri = Uri.parse(value);
    if (uri.scheme == 'dart') return null;
    if (uri.scheme != 'package') return file.resolveUri(uri);
    final package = uri.pathSegments.first;
    final base = packages[package];
    if (base == null) {
      errors.add('Unresolved dependency: $value in $file');
      return null;
    }
    return base.resolve('lib/${uri.pathSegments.skip(1).join('/')}');
  }

  String? module(Uri uri) {
    final prefix = '${core.uri}lib/';
    if (!uri.toString().startsWith(prefix)) return null;
    final segments = uri.toString().substring(prefix.length).split('/');
    return segments.first == 'src'
        ? segments.elementAtOrNull(1)
        : segments.first.replaceAll('.dart', '');
  }

  void visit(Uri uri) {
    if (!_visited.add(uri.toString())) return;
    final file = File.fromUri(uri);
    if (!file.existsSync()) {
      errors.add('Missing source: $uri');
      return;
    }
    final parsed = parseString(
      content: file.readAsStringSync(),
      path: file.path,
      throwIfDiagnostics: false,
    );
    // intl retains a legacy final parameter modifier accepted by the SDK.
    // It cannot affect import directives; still traverse its complete AST.
    final parseErrors = parsed.errors.where(
      (error) =>
          module(uri) != null ||
          error.diagnosticCode.lowerCaseName != 'extraneous_modifier',
    );
    if (parseErrors.isNotEmpty) {
      errors.add(
        "Parse diagnostics in ${file.path}: ${parseErrors.join(", ")}",
      );
    }
    for (final value in directiveUris(parsed.unit)) {
      if (value == 'dart:ui' ||
          module(uri) != null && value == 'dart:io' ||
          value.startsWith('package:flutter/') ||
          value.startsWith('package:fstapp/')) {
        errors.add('Forbidden production dependency $value in $uri');
        continue;
      }
      final target = resolve(uri, value);
      if (target == null) continue;
      final from = module(uri), to = module(target);
      if (from != null && to != null && from != to) {
        if (!(edges[from]?.contains(to) ?? false)) {
          errors.add('Forbidden module dependency: $from -> $to in $uri');
        }
        if (target.toString().contains('/lib/src/')) {
          errors.add('Cross-module internal import: $value in $uri');
        }
      }
      visit(target);
    }
  }

  void dependencies(String name, Set<String> seen) {
    if (!seen.add(name)) return;
    final base = packages[name];
    if (base == null) {
      errors.add('Missing package $name');
      return;
    }
    final spec =
        loadYaml(File.fromUri(base.resolve('pubspec.yaml')).readAsStringSync())
            as YamlMap;
    final deps = spec['dependencies'] as YamlMap?;
    for (final entry in deps?.entries ?? <MapEntry<dynamic, dynamic>>[]) {
      final dependency = entry.key as String;
      if (dependency == 'fstapp' ||
          dependency.contains('flutter') ||
          entry.value is Map && entry.value['sdk'] == 'flutter') {
        errors.add('Forbidden package dependency $name -> $dependency');
      } else {
        dependencies(dependency, seen);
      }
    }
  }

  void check() {
    dependencies('festapp_core', {});
    for (final file in Directory(
      '${core.path}/lib',
    ).listSync(recursive: true).whereType<File>()) {
      if (file.path.endsWith('.dart')) visit(file.uri);
    }
  }
}

/// Catch resource/global setup in registration code without entering the
/// callbacks that the test framework owns. Standard binding setup is idempotent.
List<String> checkRegistrationEffects(File file, CompilationUnit unit) {
  final errors = <String>[];
  const setupMethods = {
    'createTemp',
    'createTempSync',
    'setMockInitialValues',
    'setMockMethodCallHandler',
    'initializeTimeZones',
    'setLocalLocation',
    'initializeDateFormatting',
  };
  void inspect(AstNode node) {
    if (node is FunctionExpression) return;
    if (node is MethodInvocation &&
        (setupMethods.contains(node.methodName.name) ||
            node.methodName.name == 'initialize' &&
                node.target.toString() == 'Supabase' ||
            node.methodName.name == 'ensureInitialized' &&
                node.target.toString() == 'EasyLocalization')) {
      errors.add(
        'Registration effect ${node.methodName.name} in ${file.path}; move it into scoped setup',
      );
    }
    for (final child in node.childEntities.whereType<AstNode>()) {
      inspect(child);
    }
  }

  for (final declaration
      in unit.declarations.whereType<FunctionDeclaration>()) {
    if (declaration.name.lexeme == 'main')
      inspect(declaration.functionExpression.body);
  }
  return errors;
}

/// A cases file is executable coverage only through one registered entrypoint.
List<String> checkCaseRegistration(Directory root, {Directory? testRoot}) {
  final errors = <String>[];
  final test = testRoot ?? Directory('${root.path}/test');
  final files = test
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();
  final counts = <String, int>{};
  void walk(File file, Set<String> ancestors) {
    if (!ancestors.add(file.path)) {
      errors.add('Cyclic test registration: ${file.path}');
      return;
    }
    final unit = parseString(
      content: file.readAsStringSync(),
      path: file.path,
    ).unit;
    errors.addAll(checkRegistrationEffects(file, unit));
    for (final directive in unit.directives.whereType<ImportDirective>()) {
      final value = directive.uri.stringValue;
      if (value != null &&
          !value.startsWith('package:') &&
          value.endsWith('_test.dart') &&
          !directive.combinators.any(
            (combinator) =>
                combinator is ShowCombinator &&
                    !combinator.shownNames.any((name) => name.name == 'main') ||
                combinator is HideCombinator &&
                    combinator.hiddenNames.any((name) => name.name == 'main'),
          )) {
        errors.add(
          'A discoverable test must not also be imported: $value in ${file.path}',
        );
      }
      if (value == null || !value.endsWith('_cases.dart')) continue;
      // A helper-only import is not an executable registration. The global
      // cases inventory still requires its actual main to be registered once.
      if (directive.combinators.any(
        (combinator) =>
            combinator is ShowCombinator &&
                !combinator.shownNames.any((name) => name.name == 'main') ||
            combinator is HideCombinator &&
                combinator.hiddenNames.any((name) => name.name == 'main'),
      ))
        continue;
      final target = File.fromUri(file.uri.resolve(value));
      final prefix = directive.prefix?.name;
      var registrations = 0;
      void inspect(AstNode node) {
        if (node is PrefixedIdentifier &&
                node.prefix.name == prefix &&
                node.identifier.name == 'main' ||
            node is PropertyAccess &&
                node.target.toString() == prefix &&
                node.propertyName.name == 'main' ||
            node is MethodInvocation &&
                node.target.toString() == prefix &&
                node.methodName.name == 'main') {
          registrations++;
        }
        for (final child in node.childEntities.whereType<AstNode>()) {
          inspect(child);
        }
      }

      inspect(unit);
      if (registrations != 1)
        errors.add(
          'Expected one ${prefix ?? ''}.main registration in ${file.path}, found $registrations',
        );
      counts.update(
        target.path,
        (n) => n + registrations,
        ifAbsent: () => registrations,
      );
      walk(target, {...ancestors});
    }
  }

  for (final file in files.where((f) => f.path.endsWith('_test.dart'))) {
    walk(file, {});
  }
  for (final file in files.where((f) => f.path.endsWith('_cases.dart'))) {
    if (counts[file.path] != 1)
      errors.add(
        'Case must be registered exactly once: ${file.path} (${counts[file.path] ?? 0})',
      );
  }
  return errors;
}

List<String> checkPublicFixtureImports(Directory root) {
  final errors = <String>[];
  for (final name in ['test', 'test_dart', 'packages/festapp_core/test']) {
    final directory = Directory('${root.path}/$name');
    if (!directory.existsSync()) continue;
    for (final file in directory.listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      final unit = parseString(
        content: file.readAsStringSync(),
        path: file.path,
      ).unit;
      for (final uri in directiveUris(unit)) {
        if (uri.startsWith('package:') && uri.contains('/src/')) {
          errors.add(
            'Private SDK fixture import $uri in ${file.path}; use public APIs',
          );
        }
      }
    }
  }
  return errors;
}

List<String> checkTestClassification(Directory root) {
  final file = File('${root.path}/automation/client_test_classification.json');
  if (!file.existsSync()) return ['Missing Flutter test classification'];
  final entries =
      (jsonDecode(file.readAsStringSync()) as Map)['flutter_roots'] as Map;
  final actual = Directory('${root.path}/test')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('_test.dart'))
      .map((f) => f.path.substring(root.path.length + 1))
      .toSet();
  final errors = <String>[];
  for (final path in actual.difference(entries.keys.cast<String>().toSet())) {
    errors.add('Unclassified Flutter root: $path');
  }
  for (final path in entries.keys.cast<String>().toSet().difference(actual)) {
    errors.add('Stale Flutter classification: $path');
  }
  for (final entry in entries.entries) {
    final value = entry.value as Map;
    if (!{'widget', 'adapter', 'environment'}.contains(value['kind']) ||
        (value['reason'] as String? ?? '').trim().isEmpty) {
      errors.add('Missing concrete environment reason: ${entry.key}');
    }
    for (final source in value['sources'] as List) {
      if (!File('${root.path}/$source').existsSync()) {
        errors.add('Missing classified source: $source');
      }
    }
  }
  return errors;
}

/// Generic visual themes must not depend on application context or routing.
List<String> checkVisualThemeBoundary(Directory root) {
  final start = File('${root.path}/lib/theme_config.dart');
  if (!start.existsSync()) return [];
  final seen = <String>{};
  final errors = <String>[];
  void visit(File file) {
    if (!seen.add(file.path)) return;
    final relative = file.path.substring(root.path.length + 1);
    if (relative.startsWith('lib/data_services/') ||
        relative.startsWith('lib/components/features/') ||
        relative == 'lib/router_service.dart' ||
        relative.startsWith('lib/app_router.')) {
      errors.add('Visual theme reaches application context: $relative');
      return;
    }
    final unit = parseString(
      content: file.readAsStringSync(),
      path: file.path,
    ).unit;
    for (final value in directiveUris(unit)) {
      final target = value.startsWith('package:fstapp/')
          ? File(
              '${root.path}/lib/${value.substring('package:fstapp/'.length)}',
            )
          : !value.contains(':')
          ? File.fromUri(file.uri.resolve(value))
          : null;
      if (target != null && target.existsSync()) visit(target);
    }
  }

  visit(start);
  return errors;
}

/// Grid contracts and ordinary labels must stay independent of app context.
List<String> checkGridContractBoundaries(Directory root) {
  final seen = <String>{};
  final errors = <String>[];
  void visit(File file) {
    if (!file.existsSync() || !seen.add(file.path)) return;
    final relative = file.path.substring(root.path.length + 1);
    if (relative.startsWith('lib/data_services/') ||
        relative.startsWith('lib/components/features/') ||
        relative == 'lib/router_service.dart' ||
        relative.startsWith('lib/app_router.') ||
        relative == 'lib/components/eshop/eshop_columns.dart' ||
        RegExp(r'/supabase_.*_commands\.dart$').hasMatch(relative)) {
      errors.add('Grid contract reaches application composition: $relative');
      return;
    }
    final unit = parseString(
      content: file.readAsStringSync(),
      path: file.path,
    ).unit;
    for (final value in directiveUris(unit)) {
      final target = value.startsWith('package:fstapp/')
          ? File(
              '${root.path}/lib/${value.substring('package:fstapp/'.length)}',
            )
          : !value.contains(':')
          ? File.fromUri(file.uri.resolve(value))
          : null;
      if (target != null) visit(target);
    }
  }

  for (final path in [
    'components/eshop/eshop_column_ids.dart',
    'components/eshop/eshop_commands.dart',
    'components/eshop/orders_strings.dart',
    'components/eshop/product_grid_record.dart',
    'components/forms/form_commands.dart',
    'components/schedule/event_commands.dart',
  ]) {
    visit(File('${root.path}/lib/$path'));
  }
  return errors;
}

/// Models own codecs/defaults; the entire closure, including AppConfig, must
/// stay independent of editors, application context and concrete routing.
List<String> checkFeatureModelBoundaries(Directory root) {
  final errors = <String>[];
  final seen = <String>{};
  void visit(File file) {
    if (!file.existsSync() || !seen.add(file.path)) return;
    final relative = file.path.substring(root.path.length + 1);
    if (relative.contains('/features/editors/') ||
        relative.startsWith('lib/app_router.') ||
        relative == 'lib/router_service.dart' ||
        relative.endsWith('/feature_form.dart') ||
        relative.endsWith('/feature_settings_editor.dart') ||
        relative.endsWith('/ticket_settings.dart') ||
        relative.endsWith('/editor_draft_scope.dart') ||
        relative.endsWith('/rights_service.dart')) {
      errors.add('Feature model reaches editor/context: $relative');
      return;
    }
    final unit = parseString(
      content: file.readAsStringSync(),
      path: file.path,
    ).unit;
    for (final value in directiveUris(unit)) {
      final target = value.startsWith('package:fstapp/')
          ? File(
              '${root.path}/lib/${value.substring('package:fstapp/'.length)}',
            )
          : !value.contains(':')
          ? File.fromUri(file.uri.resolve(value))
          : null;
      if (target != null) visit(target);
    }
  }

  visit(File('${root.path}/lib/components/features/feature.dart'));
  return errors;
}

void main(List<String> args) {
  final root = Directory(args.single).absolute;
  final guard = ArchitectureGuard(root)..check();
  final errors = [
    ...guard.errors,
    ...checkVisualThemeBoundary(root),
    ...checkFeatureModelBoundaries(root),
    ...checkGridContractBoundaries(root),
    ...checkPublicFixtureImports(root),
    ...checkTestClassification(root),
    for (final testRoot in [
      Directory('${root.path}/test'),
      Directory('${root.path}/packages/festapp_core/test'),
      Directory('${root.path}/test_dart'),
    ])
      if (testRoot.existsSync())
        ...checkCaseRegistration(root, testRoot: testRoot),
  ];
  if (errors.isNotEmpty) {
    stderr.writeln(errors.join('\n'));
    exitCode = 1;
  } else {
    stdout.writeln('Core dependency closure and test registrations: PASS');
  }
}
