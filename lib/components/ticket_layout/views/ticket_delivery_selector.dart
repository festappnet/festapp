import 'package:material_ui/material_ui.dart';
import '../../features/ticket_feature.dart';
import '../ticket_delivery_strings.dart';

/// One event-wide setting. Choosing a format never enables ticket issuance.
class TicketDeliverySelector extends StatelessWidget {
  const TicketDeliverySelector(
      {super.key,
      required this.value,
      required this.enabled,
      required this.onChanged});
  final TicketDeliveryMode value;
  final bool enabled;
  final ValueChanged<TicketDeliveryMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final border = OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: colors.outlineVariant));
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(TicketDeliveryStrings.text('title'),
              style: theme.textTheme.labelLarge?.copyWith(height: 1.4)),
          const SizedBox(height: 6),
          Semantics(
            label: TicketDeliveryStrings.text('title'),
            child: DropdownMenu<TicketDeliveryMode>(
              initialSelection: value,
              enabled: enabled,
              expandedInsets: EdgeInsets.zero,
              selectOnly: true,
              enableSearch: false,
              requestFocusOnTap: false,
              textStyle: theme.textTheme.bodyLarge,
              inputDecorationTheme: InputDecorationThemeData(
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  border: border,
                  enabledBorder: border,
                  focusedBorder: border.copyWith(
                      borderSide:
                          BorderSide(color: colors.primary, width: 1.5))),
              menuStyle: MenuStyle(
                backgroundColor: WidgetStatePropertyAll(colors.surface),
                surfaceTintColor:
                    const WidgetStatePropertyAll(Colors.transparent),
                elevation: const WidgetStatePropertyAll(3),
                padding: const WidgetStatePropertyAll(EdgeInsets.all(6)),
                shape: WidgetStatePropertyAll(RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: colors.outlineVariant))),
              ),
              dropdownMenuEntries: [
                for (final mode in TicketDeliveryMode.values)
                  DropdownMenuEntry(
                    value: mode,
                    label: TicketDeliveryStrings.label(mode),
                    trailingIcon: mode == value
                        ? Icon(Icons.check_rounded,
                            size: 18, color: colors.onSecondaryContainer)
                        : null,
                    style: ButtonStyle(
                      minimumSize: const WidgetStatePropertyAll(Size(0, 48)),
                      padding: const WidgetStatePropertyAll(
                          EdgeInsets.symmetric(horizontal: 12)),
                      shape: WidgetStatePropertyAll(RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8))),
                      backgroundColor: mode == value
                          ? WidgetStatePropertyAll(colors.secondaryContainer)
                          : null,
                      foregroundColor: mode == value
                          ? WidgetStatePropertyAll(colors.onSecondaryContainer)
                          : null,
                    ),
                  ),
              ],
              onSelected: enabled
                  ? (next) {
                      if (next != null) onChanged(next);
                    }
                  : null,
            ),
          ),
          const SizedBox(height: 8),
          Text(TicketDeliveryStrings.description(value),
              style: theme.textTheme.bodySmall),
        ]),
      ),
    );
  }
}
