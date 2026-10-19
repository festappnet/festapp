import 'package:flutter/material.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:fstapp/components/users/occasion_team_invitation_strings.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

List<String> occasionSetupInviteEmails(Map<String, dynamic> data) =>
    (data['teamInviteEmails'] as List? ?? const [])
        .whereType<String>()
        .map((email) => email.trim().toLowerCase())
        .where((email) => email.isNotEmpty)
        .toSet()
        .toList();

String occasionSetupInviteRole(Map<String, dynamic> data, String email) =>
    (data['teamInviteRoles'] as Map?)?[email] == 'read_only'
        ? 'read_only'
        : 'editor';

bool validTeamInviteEmail(String value) {
  final email = value.trim();
  return email.isNotEmpty &&
      email.length <= 254 &&
      FormBuilderValidators.email(errorText: 'invalid')(email) == null;
}

/// Collects intent only. No account, membership or email is created here.
class OccasionSetupInvitations extends StatefulWidget {
  final String draftId;
  final Map<String, dynamic> data;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final Future<Map<String, dynamic>> Function(List<String>)? preview;
  const OccasionSetupInvitations(
      {super.key,
      required this.draftId,
      required this.data,
      required this.onChanged,
      this.preview});
  @override
  State<OccasionSetupInvitations> createState() =>
      _OccasionSetupInvitationsState();
}

class _OccasionSetupInvitationsState extends State<OccasionSetupInvitations> {
  final _email = TextEditingController();
  Map<String, Map<String, dynamic>> _recipients = {};
  String? _error;
  bool _loading = true;
  bool _canManage = false;
  int _request = 0;
  String t(String key) => OccasionTeamInvitationStrings.text(key);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _load([List<String>? addresses]) async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final emails = addresses ?? occasionSetupInviteEmails(widget.data);
      final result = widget.preview != null
          ? await widget.preview!(emails)
          : Map<String, dynamic>.from(await Supabase.instance.client.rpc(
              'preview_occasion_setup_invitations',
              params: {'p_id': widget.draftId, 'p_emails': emails}));
      if (!mounted || request != _request) return;
      setState(() {
        _canManage = result['canManage'] == true;
        _loading = false;
        _recipients = {
          for (final row
              in (result['recipients'] as List? ?? const []).whereType<Map>())
            row['email'] as String: Map<String, dynamic>.from(row)
        };
      });
    } catch (_) {
      if (mounted && request == _request)
        setState(() {
          _loading = false;
          _error = t('previewFailed');
        });
    }
  }

  void _add() {
    final email = _email.text.trim().toLowerCase();
    if (!validTeamInviteEmail(email)) {
      setState(() => _error = t('invalidEmail'));
      return;
    }
    final emails = occasionSetupInviteEmails(widget.data);
    if (!emails.contains(email)) {
      if (emails.length >= 20) {
        setState(() => _error = t('limit'));
        return;
      }
      emails.add(email);
    }
    _email.clear();
    widget
        .onChanged({'teamInviteEmails': emails, 'sendTeamInvitations': false});
    _load(emails);
  }

  void _remove(String email) {
    final emails = occasionSetupInviteEmails(widget.data)..remove(email);
    final roles =
        Map<String, dynamic>.from(widget.data['teamInviteRoles'] as Map? ?? {})
          ..remove(email);
    widget.onChanged({
      'teamInviteEmails': emails,
      'teamInviteRoles': roles,
      'sendTeamInvitations': false
    });
    _load(emails);
  }

  void _role(String email, String role) {
    final roles =
        Map<String, dynamic>.from(widget.data['teamInviteRoles'] as Map? ?? {})
          ..[email] = role;
    widget.onChanged({'teamInviteRoles': roles, 'sendTeamInvitations': false});
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final emails = occasionSetupInviteEmails(widget.data);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(t('optionalHint')),
      const SizedBox(height: 12),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.grey[850]
              : Colors.white,
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t('sendTiming'),
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(t('reviewSendHint')),
            const SizedBox(height: 8),
            Text(t('draftOnlyHint')),
          ],
        ),
      ),
      const SizedBox(height: 12),
      Text(t('noPassword')),
      if (_loading)
        const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: LinearProgressIndicator()),
      if (_error != null) ...[
        const SizedBox(height: 12),
        Text(_error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error)),
        TextButton(
            onPressed: _loading ? null : () => _load(),
            child: Text(t('retry'))),
      ],
      if (!_loading && !_canManage && _error == null)
        Text(t('managerRequired')),
      if (_canManage) ...[
        const SizedBox(height: 20),
        TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
                labelText: t('emailLabel'), border: const OutlineInputBorder()),
            onSubmitted: (_) => _add()),
        const SizedBox(height: 8),
        OutlinedButton.icon(
            onPressed: _loading ? null : _add,
            icon: const Icon(Icons.add),
            label: Text(t('add'))),
        const SizedBox(height: 16),
        if (emails.isEmpty) Text(t('empty')),
        for (final email in emails)
          ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(email),
              subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_recipients[email]?['alreadyEditor'] == true &&
                            (_recipients[email]?['role'] ?? 'editor') ==
                                occasionSetupInviteRole(widget.data, email)
                        ? t('alreadyEditor')
                        : _recipients[email]?['kind'] == 'member'
                            ? t('member')
                            : _recipients[email]?['kind'] == 'account'
                                ? t('account')
                                : _recipients[email]?['kind'] == 'new'
                                    ? t('newAccount')
                                    : t('role')),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                        key: ValueKey(
                            'invite-role-$email-${occasionSetupInviteRole(widget.data, email)}'),
                        initialValue:
                            occasionSetupInviteRole(widget.data, email),
                        decoration: InputDecoration(labelText: t('roleLabel')),
                        items: [
                          DropdownMenuItem(
                              value: 'editor', child: Text(t('roleEditor'))),
                          DropdownMenuItem(
                              value: 'read_only',
                              child: Text(t('roleReadOnly')))
                        ],
                        onChanged: _loading
                            ? null
                            : (role) {
                                if (role != null) _role(email, role);
                              }),
                  ]),
              trailing: IconButton(
                  tooltip: t('remove'),
                  onPressed: _loading ? null : () => _remove(email),
                  icon: const Icon(Icons.close))),
      ],
    ]);
  }
}

class OccasionSetupInvitationsSummary extends StatelessWidget {
  final Map<String, dynamic> data;
  final ValueChanged<bool> onSendChanged;
  const OccasionSetupInvitationsSummary(
      {super.key, required this.data, required this.onSendChanged});
  @override
  Widget build(BuildContext context) {
    String t(String key) => OccasionTeamInvitationStrings.text(key);
    final emails = occasionSetupInviteEmails(data);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (emails.isEmpty) Text(t('empty')),
      for (final email in emails)
        Text(
            '$email - ${t(occasionSetupInviteRole(data, email) == 'read_only' ? 'roleReadOnly' : 'roleEditor')}'),
      if (emails.isNotEmpty) ...[
        const SizedBox(height: 8),
        CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: data['sendTeamInvitations'] == true,
            onChanged: (value) => onSendChanged(value == true),
            title: Text(t('sendConfirmation'))),
        Text(t('draftOnlyHint')),
        const SizedBox(height: 8),
        Text(t('noPassword')),
      ],
      if (data['sendTeamInvitations'] != true) Text(t('notSending')),
    ]);
  }
}
