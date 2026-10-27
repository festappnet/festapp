import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/_shared/project_picker_widget.dart';
import 'package:fstapp/widgets/dependency_material_bridge.dart';
import '../../support/fixtures/widget_environment_fixture.dart';

void main() {
  WidgetEnvironmentFixture.register();
  late WidgetEnvironmentFixture environment;
  setUpAll(() {
    environment = WidgetEnvironmentFixture(locale: const Locale('cs'),
      translations: jsonDecode(File('assets/translations/cs.json').readAsStringSync()) as Map<String,dynamic>);
  });
  for (final guided in [true,false]) {
    testWidgets('breadcrumb creation offers both flows and invokes only ${guided ? 'guided' : 'quick'}', (tester) async {
      final actions = <String>[];
      await environment.pumpWidget(tester, MaterialApp(builder: DependencyMaterialBridge.builder,
        home: Scaffold(body: Align(alignment: Alignment.topLeft,
          child: SizedBox(width:350,child:ProjectPicker<String>(
            onDismiss:()=>actions.add('dismiss'),items:const ['Ples'],selectedItem:'Ples',
            itemTitleBuilder:(item)=>item,itemIdBuilder:(item)=>item,onItemSelected:(_){},
            onCreateNew:()=>actions.add('guided'),onCreateNewQuick:()=>actions.add('quick'),
            hintText:'Vyhledat',createNewText:'Nová událost'))))));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nová událost'));
      await tester.pumpAndSettle();
      expect(actions,isEmpty);
      expect(find.text('Krok za krokem'),findsOneWidget);
      expect(find.text('Bez průvodce'),findsOneWidget);
      await tester.tap(find.text(guided?'Krok za krokem':'Bez průvodce'));
      await tester.pumpAndSettle();
      expect(actions,['dismiss',guided?'guided':'quick']);
      expect(tester.takeException(),isNull);
    });
  }
  testWidgets('generic picker without a second flow preserves direct creation', (tester) async {
    final actions = <String>[];
    await environment.pumpWidget(tester,MaterialApp(builder:DependencyMaterialBridge.builder,
      home:Scaffold(body:SizedBox(width:350,child:ProjectPicker<String>(
        onDismiss:()=>actions.add('dismiss'),items:const [],itemTitleBuilder:(item)=>item,
        itemIdBuilder:(item)=>item,onItemSelected:(_){},onCreateNew:()=>actions.add('create'),
        hintText:'Vyhledat',createNewText:'Nová jednotka')))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nová jednotka'));
    await tester.pumpAndSettle();
    expect(actions,['dismiss','create']);
    expect(tester.takeException(),isNull);
  });
}
