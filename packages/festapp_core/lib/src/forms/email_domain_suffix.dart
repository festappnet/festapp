import 'email_tlds.g.dart';
import 'email_address.dart';

enum EmailDomainSuffixStatus { knownSuffix, unrecognizedSuffix }

/// Syntax and requiredness belong to the caller. Does not check deliverability.
class EmailDomainSuffix {
  final String suffix;
  final EmailDomainSuffixStatus status;
  const EmailDomainSuffix(this.suffix, this.status);

  factory EmailDomainSuffix.classify(String email) {
    final suffix = email.trim().split('@').last.split('.').last.toLowerCase();
    return EmailDomainSuffix(
      suffix,
      emailTlds.contains(suffix)
          ? EmailDomainSuffixStatus.knownSuffix
          : EmailDomainSuffixStatus.unrecognizedSuffix,
    );
  }
}

/// In-memory state for one field in one form session. Never serialize this state.
class EmailSuffixConfirmation {
  String _value = '';
  bool visible = false;
  bool confirmed = false;
  String get value => _value;

  void update(String value) {
    if (_value == value) return;
    _value = value;
    confirmed = false;
  }

  bool get needsConfirmation =>
      EmailAddress.isValid(_value) &&
      !confirmed &&
      EmailDomainSuffix.classify(_value).status ==
          EmailDomainSuffixStatus.unrecognizedSuffix;

  void confirm() => confirmed = true;
}
