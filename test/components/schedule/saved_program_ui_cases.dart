import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/schedule/saved_program_ui.dart';

void main() {
  test('a stale load cannot overwrite an in-flight optimistic choice', () {
    expect(
      reconcileLoadedSavedProgramState(
        incoming: false,
        visible: true,
        mutationInFlight: true,
        loadRevision: 0,
        currentRevision: 1,
      ),
      isTrue,
    );
    expect(
      reconcileLoadedSavedProgramState(
        incoming: false,
        visible: true,
        mutationInFlight: false,
        loadRevision: 2,
        currentRevision: 2,
      ),
      isFalse,
    );
    expect(
      reconcileLoadedSavedProgramState(
        incoming: false,
        visible: true,
        mutationInFlight: false,
        loadRevision: 0,
        currentRevision: 2,
      ),
      isTrue,
      reason: 'a load started before a completed mutation is still stale',
    );
  });

  testWidgets('saved-program icon changes atomically without an old icon frame',
      (tester) async {
    const primary = Color(0xff0000f4);
    final canSave = ValueNotifier(true);
    addTearDown(canSave.dispose);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(
        colorScheme: const ColorScheme.light(
          primary: primary,
          onPrimary: Colors.white,
        ),
      ),
      home: IconButton(
        style: savedProgramActionButtonStyle,
        onPressed: () {},
        icon: SavedProgramActionIcon(
          canSave: canSave,
          color: Colors.blue,
          addIcon: Icons.add,
          savedIcon: Icons.check,
          size: 30,
          diameter: 48,
        ),
      ),
    ));

    final buttonBefore = tester.element(find.byType(IconButton));
    final buttonRectBefore = tester.getRect(find.byType(IconButton));
    expect(find.byIcon(Icons.add, skipOffstage: false), findsOneWidget);
    expect(find.byIcon(Icons.check, skipOffstage: false), findsOneWidget,
        reason: 'both glyphs must stay mounted to avoid a replacement flash');
    canSave.value = false;
    await tester.pump();

    expect(tester.element(find.byType(IconButton)), same(buttonBefore),
        reason: 'save must not rebuild or disable the surrounding button');
    expect(tester.getRect(find.byType(IconButton)), buttonRectBefore,
        reason: 'the action must keep exactly the same geometry');
    expect(find.byIcon(Icons.add, skipOffstage: false), findsOneWidget);
    expect(find.byIcon(Icons.check, skipOffstage: false), findsOneWidget);
    expect(find.byIcon(Icons.add), findsNothing);
    expect(find.byIcon(Icons.check), findsOneWidget);

    final savedCircle = tester.widget<Container>(find.byType(Container));
    final decoration = savedCircle.decoration! as BoxDecoration;
    expect(
        savedCircle.constraints,
        const BoxConstraints.tightFor(
          width: 48,
          height: 48,
        ));
    expect(decoration.shape, BoxShape.circle);
    expect(decoration.color, primary);
    final savedGlyph = tester.widget<Icon>(find.byIcon(Icons.check));
    expect(savedGlyph.color, Colors.white);
    expect(savedGlyph.weight, 700);
    expect(savedGlyph.fontWeight, FontWeight.w700);
  });

  testWidgets('collapsed saved-program action keeps the compact legacy icon',
      (tester) async {
    final canSave = ValueNotifier(false);
    addTearDown(canSave.dispose);
    await tester.pumpWidget(MaterialApp(
      home: SavedProgramActionIcon(
        canSave: canSave,
        color: Colors.black,
        addIcon: Icons.add_circle_outline,
        savedIcon: Icons.check_circle,
        size: 30,
        diameter: 30,
        highlightSaved: false,
      ),
    ));

    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(find.byType(Container), findsNothing,
        reason: 'the collapsed bar must not wrap the check in a larger circle');
    expect(tester.widget<Icon>(find.byIcon(Icons.check_circle)).color,
        Colors.black);
  });

  test('saved-program button has no transient material overlay', () {
    expect(savedProgramActionButtonStyle.splashFactory,
        same(NoSplash.splashFactory));
    expect(
      savedProgramActionButtonStyle.overlayColor!
          .resolve({WidgetState.pressed}),
      Colors.transparent,
    );
    expect(
      savedProgramActionButtonStyle.overlayColor!
          .resolve({WidgetState.focused}),
      Colors.transparent,
    );
  });
}
