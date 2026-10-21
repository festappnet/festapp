import 'package:test/test.dart';
import 'package:venue_layout_core/venue_layout_core.dart';

// Canonical physical layouts use typed placements. Moving a whole table is a
// rigid operation; changing its chair distribution requires an explicit reflow.
VenueLayoutDocument wideTable() => tableLayout(
  shape: 'rect', count: 14, width: 366, height: 128, x: 500, y: 300,
).copyWith(canvas: {'x':0,'y':0,'width':1000,'height':600,'fill':'#FFFFFFFF'});

void expectRigid(VenueLayoutDocument before, VenueLayoutDocument after) {
  expect(validateDocument(before), isEmpty);
  expect(validateDocument(after), isEmpty);
  expect(layoutCollisions(after), isEmpty);
  expect(after.attachments, before.attachments);
  expect(after.nodes.map((n)=>n.id), before.nodes.map((n)=>n.id));
  expect(after.nodes.where((n)=>n.kind=='seat').map((n)=>n.toJson()),
      before.nodes.where((n)=>n.kind=='seat').map((n)=>n.toJson()));
  final matrices=worldMatrices(after);
  for(final node in after.nodes.where((n)=>n.kind!='group')) {
    for(final point in worldHull(node,matrices[node.id]!)) {
      expect(point[0],inInclusiveRange(-.001,1000.001));
      expect(point[1],inInclusiveRange(-.001,600.001));
    }
  }
}

void main() {
  test('moving a wide table to either wall clamps the entire rigid chair inventory',(){
    for(final delta in [-1000.0,1000.0]) {
      final before=wideTable(),table=before.nodes.firstWhere((n)=>n.kind=='table');
      final moved=moveLayoutWithinCanvas(before,{table.id},dx:delta);
      expect(moved.nodes.firstWhere((n)=>n.id==table.id).x,isNot(table.x));
      expectRigid(before,moved);
      expect(moveLayoutWithinCanvas(moved,{table.id},dx:delta).toJson(),moved.toJson());
    }
  });
  test('a zero translation preserves an already fitting irregular free row',(){
    var before=wideTable();
    final seat=before.nodes.firstWhere((n)=>n.kind=='seat');
    before=transformNodes(before,{seat.id},dx:2,dy:2);
    expect(seatAttachment(before,seat.id)!['placement'],{'mode':'free'});
    final table=before.nodes.firstWhere((n)=>n.kind=='table');
    final moved=moveLayoutWithinCanvas(before,{table.id});
    expectRigid(before,moved);
    expect(moved.toJson(),before.toJson());
  });
  test('free chair pose and independent manual rotation survive table movement',(){
    var before=wideTable();
    final seat=before.nodes.firstWhere((n)=>n.kind=='seat');
    before=transformNodes(before,{seat.id},dx:2,dy:2,rotation:3);
    expect(seatAttachment(before,seat.id)!['placement'],{'mode':'free'});
    expect(seatAttachment(before,seat.id)!['rotationMode'],'manual');
    final table=before.nodes.firstWhere((n)=>n.kind=='table');
    final moved=moveLayoutWithinCanvas(before,{table.id},dx:1000);
    expectRigid(before,moved);
  });
}
