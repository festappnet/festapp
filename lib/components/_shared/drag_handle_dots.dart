import 'package:material_ui/material_ui.dart';

class DragHandleDots extends StatelessWidget {
  const DragHandleDots({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
        4,
        (_) => Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: List.generate(
            2,
            (_) => Container(
              width: 3.5,
              height: 3.5,
              margin: const EdgeInsets.all(1),
              decoration: BoxDecoration(
                color: Theme.of(context).disabledColor,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
