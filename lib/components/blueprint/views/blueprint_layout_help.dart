import 'package:flutter/material.dart';
import '../blueprint_strings.dart';

/// Only controls supported in the current plan mode belong in this list.
class BlueprintLayoutHelp extends StatelessWidget {
  const BlueprintLayoutHelp(
      {super.key,
      required this.editing,
      required this.canEnterEdit,
      required this.legend});
  final bool editing, canEnterEdit;
  final Widget legend;

  Widget _entry(String keys, String action) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
              flex: 2,
              child: Text(keys,
                  style: const TextStyle(fontWeight: FontWeight.w600))),
          const SizedBox(width: 20),
          Expanded(flex: 3, child: Text(action)),
        ]),
      );

  @override
  Widget build(BuildContext context) => SizedBox(
      width: 580,
      child: SingleChildScrollView(
          child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _entry(BlueprintStrings.helpClick, BlueprintStrings.helpSelect),
          _entry(BlueprintStrings.helpShiftClick,
              BlueprintStrings.helpAddSelection),
          if (!editing)
            _entry(BlueprintStrings.helpDrag, BlueprintStrings.helpPan),
          _entry(BlueprintStrings.helpWheel, BlueprintStrings.helpZoom),
          if (canEnterEdit)
            _entry(BlueprintStrings.helpEnterEditKeys,
                BlueprintStrings.helpEnterEdit),
          if (editing) ...[
            _entry(
                BlueprintStrings.helpAltClick, BlueprintStrings.helpIndividual),
            _entry(BlueprintStrings.helpArrows, BlueprintStrings.helpMove),
            _entry('Ctrl / ⌘ + Z', BlueprintStrings.helpUndo),
            _entry('Ctrl / ⌘ + Shift + Z', BlueprintStrings.helpRedo),
            _entry('Ctrl / ⌘ + D', BlueprintStrings.helpDuplicate),
            _entry('Ctrl / ⌘ + C / V', BlueprintStrings.helpCopyPaste),
            _entry('Delete / Backspace', BlueprintStrings.helpDelete),
            _entry('G', BlueprintStrings.helpGrid),
          ],
          _entry(
              'Escape',
              editing
                  ? BlueprintStrings.helpEscapeEdit
                  : BlueprintStrings.helpEscapeView),
          ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(BlueprintStrings.helpSeatStates),
              children: [legend]),
        ],
      )));
}
