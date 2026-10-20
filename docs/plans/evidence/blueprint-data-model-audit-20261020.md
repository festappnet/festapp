# Reprodukce vybraných vlastností modelu plánku

Datum: 2026-10-20. Package ref `0b881853bd9071784fd66102a03a1606a81afa79`.
Pouze izolovaný pure-Dart model; bez databáze, sítě, uložení nebo změny aplikace.

Spuštěno z package worktree příkazem:

```sh
fvm dart --packages=.dart_tool/package_config.json /tmp/festapp-blueprint-release-private-20261019/architecture-audit-20261020/model_probe.dart
```

Zdroj:

```dart
import 'dart:convert';
import 'package:venue_layout_core/venue_layout_core.dart';
void main() {
  final n = LayoutNode(id:newLayoutId(),kind:'table',x:400,y:300,width:300,height:160,label:'A',properties:{'size':40});
  final base = VenueLayoutDocument(nodes:[n]);
  final scoped = setLayoutAppearance(base,'table',{'size':36});
  final reset = scoped.copyWith(appearance:{'table':{}});
  final locked = base.copyWith(nodes:[n.copyWith(locked:true)]);
  final lockedStyled = setLayoutAppearance(locked,'table',{'fill':'#123456FF','size':36});
  final frozen = lockedStyled.nodes.single;
  final t = tableLayout(shape:'rect',count:2,width:300,height:160);
  final styled = setNodeAppearanceOverride(t,t.nodes.where((n)=>n.kind=='seat').map((n)=>n.id),['fill']);
  final seatsStyled = styled.copyWith(nodes:[for(final s in styled.nodes) s.kind=='seat'?s.copyWith(properties:{...s.properties,'fill':'#123456FF'}):s]);
  final oldIds=t.nodes.map((n)=>n.id).toSet();
  final grown=reflowTable(seatsStyled,t.nodes.firstWhere((n)=>n.kind=='table').id,3);
  final added=grown.nodes.singleWhere((n)=>n.kind=='seat'&&!oldIds.contains(n.id));
  final polygon=n.copyWith(properties:{'shape':'polygon','points':[[-150,-80],[150,-80],[60,80],[-150,80]]});
  final polyDoc=base.copyWith(nodes:[polygon]);
  String grid;
  try { GridSurfaceBrush.fromNode(polygon); grid='accepted'; } catch(e) {grid=e.toString();}
  print(jsonEncode({
    'latent_style':{'global':effectiveNodeProperties(scoped,n)['size'],'after_global_reset':effectiveNodeProperties(reset,n)['size'],'document_default':base.defaultTextStyle['size']},
    'locked_global_style':{'fill':effectiveNodeProperties(lockedStyled,frozen)['fill'],'size':effectiveNodeProperties(lockedStyled,frozen)['size'],'written_overrides':frozen.properties['appearanceOverrides']},
    'new_chair_style':{'existing':grown.nodes.where((n)=>n.kind=='seat'&&oldIds.contains(n.id)).map((n)=>effectiveNodeProperties(grown,n)['fill']).toList(),'added':effectiveNodeProperties(grown,added)['fill']},
    'custom_polygon':{'document_valid':validateDocument(polyDoc).isEmpty,'grid_editor':grid},
  }));
}
```

Výstup:

```json
{"latent_style":{"global":36,"after_global_reset":40,"document_default":24},"locked_global_style":{"fill":"#123456FF","size":40,"written_overrides":["size"]},"new_chair_style":{"existing":["#123456FF","#123456FF"],"added":null},"custom_polygon":{"document_valid":true,"grid_editor":"Bad state: Choose a grid-aligned custom outline first."}}
```

Interpretace a omezení jsou v [auditním plánu](../blueprint-data-model-audit-plan-2026-10-20.md).

## Host history probe: nová live ochrana před redo

Festapp ref `a3a0637d8eeec1b0d5d3a5292e6db62fdcb4f5d1`.
Spuštěn dočasný test přes `fvm flutter test --concurrency=1` proti paměťové
fixture `test/components/blueprint/blueprint_layout_host_cases.dart`; saver
vyhazuje chybu, kdyby někdo zkusil zápis. Žádný backend nebyl osloven.

První kompilace diagnostiky měla typovou chybu int/double v ceně fixture;
po jedné opravě na double proběhl test úspěšně. Passing zde znamená reprodukci
**současné chyby**, nikoliv splnění cílového chování.

Reprodukční tělo (v host test root s existující fixture a model imports):

```dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:festapp_core/eshop.dart';
import 'package:fstapp/components/blueprint/blueprint_layout_controller.dart';
import 'package:fstapp/components/blueprint/blueprint_layout_saver.dart';
import 'package:fstapp/components/blueprint/blueprint_model.dart';
import 'package:fstapp/components/blueprint/blueprint_object_model.dart';
import 'components/blueprint/blueprint_layout_host_cases.dart' as fixture;
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('audit diagnostic: redo after a new live hold', () {
    final products = [for (final id in [1,2]) ProductModel(id:id,title:'P$id',price:100.0*id,productTypeString:ProductModel.spotType)];
    BlueprintModel source(String state) => BlueprintModel(layoutSnapshot:fixture.snapshot(),products:products,spots:[BlueprintObjectModel(id:11,type:'spot',state:state)]);
    final c=BlueprintLayoutController(source:source('available'),saver:BlueprintLayoutSaver(fixture.Commands((_) async=>throw StateError('No writes authorized'))));
    addTearDown(c.dispose);
    c.assignSeatProduct(fixture.node,2);
    c.layout.undo();
    expect(c.snapshot.seatBindings[fixture.node]!.productId,1);
    c.refreshLive(source('selected'));
    expect(c.isProtected(fixture.node),isTrue);
    c.layout.redo();
    final product=c.snapshot.seatBindings[fixture.node]!.productId;
    print(jsonEncode({'newLiveHold':c.isProtected(fixture.node),'authoritativeProduct':1,'draftProductAfterRedo':product,'spotId':c.snapshot.seatBindings[fixture.node]!.spotId}));
    expect(product,2,reason:'Diagnostic confirms current unguarded host checkpoint restore; not the desired target behavior');
  });
}
```

Výstup:

```json
{"newLiveHold":true,"authoritativeProduct":1,"draftProductAfterRedo":2,"spotId":11}
```

Výsledek: `1 test passed` s diagnostickým očekáváním produktu 2. Cílová
regrese TX2 musí naopak prokázat odmítnutí nepovoleného redo. Serverovou
ochranu ukládání tento probe nezkouší a nedokazuje její prolomení.
