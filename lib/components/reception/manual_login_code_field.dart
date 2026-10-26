import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

class ManualLoginCodeEntry extends StatefulWidget {
  const ManualLoginCodeEntry({
    super.key,
    required this.onSubmitted,
    required this.title,
    required this.fieldLabel,
    required this.submitLabel,
  });

  final ValueChanged<String> onSubmitted;
  final String title;
  final String fieldLabel;
  final String submitLabel;

  @override
  State<ManualLoginCodeEntry> createState() => _ManualLoginCodeEntryState();
}

class _ManualLoginCodeEntryState extends State<ManualLoginCodeEntry> {
  final _controller = TextEditingController();
  bool _complete = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.title,
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: ManualLoginCodeField(
                  controller: _controller,
                  label: widget.fieldLabel,
                  autofocus: false,
                  onChanged: (value) => setState(
                    () => _complete = ManualLoginCodeField.isComplete(value),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                tooltip: widget.submitLabel,
                onPressed: _complete
                    ? () => widget.onSubmitted(
                          ManualLoginCodeField.normalized(_controller.text),
                        )
                    : null,
                icon: const Icon(Icons.arrow_forward),
              ),
            ],
          ),
        ],
      );
}

class ManualLoginCodeField extends StatelessWidget {
  const ManualLoginCodeField({
    required this.controller,
    this.label,
    this.onChanged,
    this.autofocus = true,
    super.key,
  });

  final TextEditingController controller;
  final String? label;
  final ValueChanged<String>? onChanged;
  final bool autofocus;

  static String normalized(String value) =>
      value.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');

  static bool isComplete(String value) =>
      RegExp(r'^[A-HJ-NP-Z2-9]{8}$').hasMatch(normalized(value));

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        autofocus: autofocus,
        autocorrect: false,
        enableSuggestions: false,
        textCapitalization: TextCapitalization.characters,
        keyboardType: TextInputType.visiblePassword,
        maxLength: 9,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
            ),
        decoration: InputDecoration(
          labelText: label,
          hintText: 'XXXX XXXX',
          counterText: '',
        ),
        inputFormatters: [
          TextInputFormatter.withFunction((oldValue, newValue) {
            final normalized = ManualLoginCodeField.normalized(newValue.text)
                .replaceAll(RegExp(r'[^A-Z0-9]'), '');
            final limited = normalized.substring(
                0, normalized.length > 8 ? 8 : normalized.length);
            final formatted = limited.length > 4
                ? '${limited.substring(0, 4)} ${limited.substring(4)}'
                : limited;
            return TextEditingValue(
              text: formatted,
              selection: TextSelection.collapsed(offset: formatted.length),
            );
          }),
        ],
        onChanged: onChanged,
      );
}
