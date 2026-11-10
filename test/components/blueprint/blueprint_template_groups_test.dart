import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/blueprint/blueprint_group_binding.dart';
import 'package:fstapp/components/blueprint/blueprint_layout_controller.dart';
import 'package:fstapp/components/blueprint/blueprint_model.dart';
import 'package:fstapp/components/blueprint/blueprint_layout_saver.dart';
import 'package:fstapp/components/forms/form_commands.dart';
import 'package:fstapp/components/occasion/setup/blueprint_setup_layout_draft.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';

class _UnusedCommands implements FormCommands {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Template insertion must not save');
}

void main() {
  for (final template in VenueLayoutTemplates.all) {
    test(
      '${template.id} keeps each physical table separate in both editors',
      () {
        final document = template.create();
        final empty = VenueLayoutDocument(nodes: const []);
        final setup = BlueprintSetupLayoutDraft.empty(
          document: empty,
          resources: const {},
        ).reconcile(document, defaultProductId: 42);
        final controller = BlueprintLayoutController(
          saver: BlueprintLayoutSaver(_UnusedCommands()),
          source: BlueprintModel.fromJson({
            'id': 1,
            'occasion': 1,
            'layout': empty.toJson(),
          }),
        );
        addTearDown(controller.dispose);
        expect(controller.layout.apply(document), isTrue);
        final nodes = {for (final node in document.nodes) node.id: node};
        final tableIds = <String>{};
        for (final seat in document.nodes.where((n) => n.kind == 'seat')) {
          var ancestor = nodes[seat.parentId];
          while (ancestor != null &&
              ancestor.kind != 'table' &&
              ancestor.kind != 'furniture') {
            ancestor = nodes[ancestor.parentId];
          }
          if (ancestor == null) continue;
          tableIds.add(ancestor.id);
          expect(
            setup.seatBindings[seat.id]!.groupNodeId,
            ancestor.id,
            reason: 'setup: ${template.id}, table ${ancestor.label}',
          );
          expect(
            controller.snapshot.seatBindings[seat.id]!.groupNodeId,
            ancestor.id,
            reason: 'editor: ${template.id}, table ${ancestor.label}',
          );
        }
        expect(setup.groupProducts.keys.toSet().containsAll(tableIds), isTrue);
        expect(setup.seatBindings, hasLength(template.seatCount));
        expect(controller.snapshot.seatBindings, hasLength(template.seatCount));
      },
    );
  }

  test('explicit business groups survive nested physical tables', () {
    final document = VenueLayoutDocument(
      nodes: [
        LayoutNode(id: 'hall', kind: 'group'),
        LayoutNode(id: 'table', kind: 'table', parentId: 'hall'),
        LayoutNode(id: 'seat', kind: 'seat', parentId: 'table'),
      ],
    );
    final seat = document.nodes.last;
    expect(
      blueprintCommercialGroupFor(
        seat,
        document,
        groupProducts: const {'hall': 42},
      ),
      'hall',
    );
    expect(
      blueprintCommercialGroupFor(
        seat,
        document,
        groupProducts: const {},
        currentGroupId: 'hall',
      ),
      'hall',
    );
  });
}
