enum ReceptionCommandError {
  emailAlreadyExists,
  commandConflict,
  rateLimited,
  receptionUnavailable,
  registrationUnavailable,
  invalidInput,
  unexpected,
}

class ReceptionCommandException implements Exception {
  ReceptionCommandException(this.response);
  final Map<String, dynamic> response;

  ReceptionCommandError get kind => switch (response['message']) {
    'email_already_exists' => ReceptionCommandError.emailAlreadyExists,
    'command_conflict' ||
    'email_or_command_conflict' => ReceptionCommandError.commandConflict,
    'rate_limited' => ReceptionCommandError.rateLimited,
    'reception_unavailable' => ReceptionCommandError.receptionUnavailable,
    'registration_unavailable' => ReceptionCommandError.registrationUnavailable,
    'invalid_profile_fields' ||
    'required_profile_fields' ||
    'invalid_group' ||
    'invalid_accommodation' => ReceptionCommandError.invalidInput,
    _ => ReceptionCommandError.unexpected,
  };

  @override
  String toString() => response['message']?.toString() ?? 'reception_error';
}
