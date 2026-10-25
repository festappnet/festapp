import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/users/user_strings.dart';

class PasswordField extends StatefulWidget {
  final String label;
  final TextEditingController controller;
  final String passwordType;

  const PasswordField({
    super.key,
    required this.label,
    required this.controller,
    required this.passwordType,
  });

  @override
  _PasswordFieldState createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  final textFieldFocusNode = FocusNode();
  bool _obscured = true;

  void _toggleObscured() {
    setState(() {
      _obscured = !_obscured;
      if (textFieldFocusNode.hasPrimaryFocus) return;
      textFieldFocusNode.canRequestFocus = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      keyboardType: TextInputType.visiblePassword,
      obscureText: _obscured,
      controller: widget.controller,
      focusNode: textFieldFocusNode,
      autofillHints: [widget.passwordType],
      validator: (String? value) {
        if (value!.isEmpty) {
          return UserStrings.fillPassword;
        }
        return null;
      },
      decoration: InputDecoration(
        floatingLabelBehavior: FloatingLabelBehavior.never,
        labelText: widget.label,
        //filled: true,
        border: const OutlineInputBorder(),
        //prefixIcon: const Icon(Icons.lock_rounded, size: 24),
        suffixIcon: Padding(
          padding: const EdgeInsets.fromLTRB(0, 0, 4, 0),
          child: GestureDetector(
            onTap: _toggleObscured,
            child: Icon(
              _obscured
                  ? Icons.visibility_rounded
                  : Icons.visibility_off_rounded,
              size: 24,
            ),
          ),
        ),
      ),
    );
  }
}
