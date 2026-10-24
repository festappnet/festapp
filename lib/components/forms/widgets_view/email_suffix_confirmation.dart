import 'package:fstapp/components/forms/email_validation.dart';
import 'package:festapp_core/forms.dart';
import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import '../form_strings.dart';

/// Owned by one FormHolder; keys include the actual main/ticket form identity.
class EmailSuffixSession {
  final _states = <(FormBuilderState, String), EmailSuffixConfirmation>{};
  final _views = <(FormBuilderState, String), _EmailSuffixFieldState>{};

  Future<bool> validate(Iterable<FormBuilderState?> forms) async {
    for (final form in forms) {
      if (form == null) continue;
      for (final entry in form.fields.entries) {
        final view = _views[(form, entry.key)];
        if (view == null ||
            !view.mounted ||
            !entry.value.enabled ||
            !view.widget.eligible) {
          continue;
        }
        view.confirmation.update(entry.value.value?.toString() ?? '');
        if (view.confirmation.needsConfirmation) {
          view.reveal();
          await Scrollable.ensureVisible(view.context);
          return false;
        }
      }
    }
    return true;
  }
}

/// Shared adapter around both text-field designs, leaving format validators intact.
class EmailSuffixField extends StatefulWidget {
  final EmailSuffixSession session;
  final FormFieldState<String?> field;
  final String name;
  final bool eligible;
  final bool informal;
  final Widget child;
  const EmailSuffixField(
      {super.key,
      required this.session,
      required this.field,
      required this.name,
      required this.child,
      this.eligible = true,
      this.informal = false});

  @override
  State<EmailSuffixField> createState() => _EmailSuffixFieldState();
}

class _EmailSuffixFieldState extends State<EmailSuffixField> {
  late (FormBuilderState, String) _key;
  late EmailSuffixConfirmation confirmation;
  final _confirmFocus = FocusNode();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _register();
  }

  void _register() {
    _key = (FormBuilder.of(context)!, widget.name);
    confirmation =
        widget.session._states.putIfAbsent(_key, EmailSuffixConfirmation.new);
    widget.session._views[_key] = this;
  }

  @override
  void didUpdateWidget(covariant EmailSuffixField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session || oldWidget.name != widget.name) {
      oldWidget.session._views.remove(_key);
      _register();
    }
  }

  void reveal() {
    setState(() => confirmation.visible = true);
    _confirmFocus.requestFocus();
  }

  @override
  void dispose() {
    if (widget.session._views[_key] == this) widget.session._views.remove(_key);
    _confirmFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    confirmation.update(widget.field.value ?? '');
    final value = confirmation.value;
    final show = widget.eligible &&
        _key.$1.enabled &&
        widget.field.widget.enabled &&
        confirmation.visible &&
        confirmation.needsConfirmation &&
        EmailValidation.validator(checkNullOrEmpty: false)(value) == null;
    final warning = show
        ? FormStrings.emailSuffixWarning(
            EmailDomainSuffix.classify(value).suffix,
            informal: widget.informal)
        : '';
    return Focus(
      onFocusChange: (focused) {
        if (!focused && mounted && !confirmation.visible) {
          setState(() => confirmation.visible = true);
        }
      },
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Semantics(hint: warning, child: widget.child),
        if (show) ...[
          Semantics(liveRegion: true, child: Text(warning)),
          TextButton(
            focusNode: _confirmFocus,
            onPressed: () => setState(confirmation.confirm),
            child: Text(FormStrings.emailSuffixConfirm),
          ),
        ],
      ]),
    );
  }
}
