import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

const ButtonStyle savedProgramActionButtonStyle = ButtonStyle(
  overlayColor: WidgetStatePropertyAll(Colors.transparent),
  splashFactory: NoSplash.splashFactory,
);

bool reconcileLoadedSavedProgramState({
  required bool incoming,
  required bool? visible,
  required bool mutationInFlight,
  required int loadRevision,
  required int currentRevision,
}) =>
    visible != null && (mutationInFlight || loadRevision != currentRevision)
        ? visible
        : incoming;

class SavedProgramActionIcon extends StatelessWidget {
  const SavedProgramActionIcon({
    required this.canSave,
    required this.color,
    required this.addIcon,
    required this.savedIcon,
    required this.size,
    required this.diameter,
    this.highlightSaved = true,
    super.key,
  });

  final ValueListenable<bool> canSave;
  final Color color;
  final IconData addIcon;
  final IconData savedIcon;
  final double size;
  final double diameter;
  final bool highlightSaved;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ValueListenableBuilder(
      valueListenable: canSave,
      builder: (context, canSave, _) => IndexedStack(
        index: canSave ? 0 : 1,
        alignment: Alignment.center,
        children: [
          Icon(addIcon, color: color, size: size),
          if (highlightSaved)
            Container(
              width: diameter,
              height: diameter,
              decoration: BoxDecoration(
                color: colors.primary,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(
                savedIcon,
                color: colors.onPrimary,
                size: size,
                weight: 700,
                grade: 100,
                fontWeight: FontWeight.w700,
              ),
            )
          else
            Icon(savedIcon, color: color, size: size),
        ],
      ),
    );
  }
}
