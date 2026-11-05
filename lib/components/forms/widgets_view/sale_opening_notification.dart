import '../email_validation.dart';

import 'package:supabase_flutter/supabase_flutter.dart' show FunctionException;
import 'package:material_ui/material_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:festapp_core/forms.dart';

import '../sale_opening_commands.dart';
import '../sale_opening_strings.dart';
import '../form_strings.dart';

class SaleOpeningNotification extends StatefulWidget {
  const SaleOpeningNotification({
    super.key,
    required this.formLink,
    this.preview = false,
    this.operation,
    this.token,
    this.hasTickets = true,
    this.informal = false,
  });
  final String formLink;
  final bool preview;
  final bool hasTickets, informal;
  final String? operation, token;
  @override
  State<SaleOpeningNotification> createState() =>
      _SaleOpeningNotificationState();
}

class _SaleOpeningNotificationState extends State<SaleOpeningNotification> {
  final email = TextEditingController();
  final confirmation = EmailSuffixConfirmation();
  bool busy = false;
  String? message;
  String? emailError;
  bool done = false, suffix = false;
  @override
  void dispose() {
    email.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (widget.preview || busy) return;
    if (widget.operation == null) {
      if (!EmailAddress.isValid(email.text)) {
        setState(() => emailError = EmailValidation.validator()(email.text));
        return;
      }
      confirmation.update(email.text);
      if (confirmation.needsConfirmation) {
        setState(() => suffix = true);
        return;
      }
    }
    final submittedEmail = email.text.trim().toLowerCase();
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await SaleOpeningCommands.execute(
        widget.operation ?? 'subscribe',
        widget.operation == null
            ? {
                'formLink': widget.formLink,
                'email': submittedEmail,
                'lang': context.locale.languageCode,
              }
            : {'token': widget.token},
      );
      if (mounted)
        setState(() {
          done = true;
          message = widget.operation == 'unsubscribe'
              ? SaleOpeningStrings.unsubscribed
              : SaleOpeningStrings.subscribed(submittedEmail);
        });
    } catch (error) {
      final invalid =
          error is FunctionException &&
          error.details is Map &&
          error.details['error'] == 'invalid_link';
      if (mounted)
        setState(
          () => message = invalid
              ? SaleOpeningStrings.invalid
              : SaleOpeningStrings.failed,
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final action = FilledButton(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 16),
      ),
      onPressed: widget.preview || busy ? null : submit,
      child: Text(
        widget.operation == 'unsubscribe'
            ? SaleOpeningStrings.unsubscribe
            : SaleOpeningStrings.notifyShort,
      ),
    );
    return Align(
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!done && widget.operation == null)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: Semantics(
                        label: SaleOpeningStrings.email,
                        child: TextField(
                          controller: email,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email],
                          enabled: !widget.preview && !busy,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontSize: 16),
                          decoration: InputDecoration(
                            hintText: SaleOpeningStrings.email,
                            errorText: emailError,
                            isDense: true,
                            border: const OutlineInputBorder(),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 14,
                            ),
                          ),
                          onChanged: (value) {
                            confirmation.update(value);
                            setState(() {
                              suffix = false;
                              emailError = null;
                            });
                          },
                          onSubmitted: (_) => submit(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(flex: 3, child: action),
                  ],
                ),
              if (suffix) ...[
                Text(
                  FormStrings.emailSuffixWarning(
                    EmailDomainSuffix.classify(email.text).suffix,
                  ),
                ),
                TextButton(
                  onPressed: () {
                    confirmation.confirm();
                    setState(() => suffix = false);
                  },
                  child: Text(FormStrings.emailSuffixConfirm),
                ),
              ],
              if (!done && widget.operation != null) action,
              if (message != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      message!,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
