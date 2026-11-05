import '../email_validation.dart';
import '../../_shared/common_strings.dart';

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
    this.command = SaleOpeningCommands.execute,
  });
  final String formLink;
  final Future<Map<String, dynamic>> Function(String, Map<String, dynamic>)
  command;
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
    if (widget.preview || busy || done) return;
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
      await widget.command(
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
        minimumSize: const Size(double.infinity, 52),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      onPressed: busy || done ? null : submit,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (busy) ...[
            SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(width: 10),
          ],
          Flexible(
            child: Text(
              busy
                  ? CommonStrings.processing
                  : widget.operation == 'unsubscribe'
                  ? SaleOpeningStrings.unsubscribe
                  : SaleOpeningStrings.notifyShort,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
    );
    return Semantics(
      container: widget.preview,
      label: widget.preview
          ? '${SaleOpeningStrings.email}. ${SaleOpeningStrings.notifyShort}'
          : null,
      child: ExcludeSemantics(
        excluding: widget.preview,
        child: ExcludeFocus(
          excluding: widget.preview,
          child: IgnorePointer(
            ignoring: widget.preview,
            child: Align(
              alignment: Alignment.center,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!done && widget.operation == null)
                        Semantics(
                          label: SaleOpeningStrings.email,
                          child: TextField(
                            controller: email,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.done,
                            autofillHints: const [AutofillHints.email],
                            enabled: !busy,
                            readOnly: widget.preview,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(fontSize: 16),
                            decoration: InputDecoration(
                              hintText: SaleOpeningStrings.email,
                              errorText: emailError,
                              isDense: true,
                              border: const OutlineInputBorder(),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 16,
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
                      if (!done) ...[
                        if (widget.operation == null)
                          const SizedBox(height: 12),
                        action,
                      ],
                      if (message != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Semantics(
                            liveRegion: true,
                            child: Text(
                              message!,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
