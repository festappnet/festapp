import 'dart:async';

import 'package:fstapp/services/exception_handler.dart';

import '../member_access_batch.dart';
import '../../single_data_grid/single_data_grid_controller.dart';

import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/data_services/client_sync/client_sync_runtime.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fstapp/widgets/app_dialog.dart';
import 'package:fstapp/components/users/member_access_commands.dart';
import 'package:fstapp/components/users/member_access_strings.dart';

class MemberAccessDialog extends StatefulWidget {
  const MemberAccessDialog({
    super.key,
    required this.scope,
    required this.scopeId,
    this.recipients = const [],
    this.selectionUnavailable = false,
  });
  final List<MemberAccessRecipient> recipients;
  final bool selectionUnavailable;
  final String scope;
  final int scopeId;
  static Future<void> show(
    BuildContext context,
    String scope,
    int id, {
    SingleDataGridController? grid,
  }) async {
    final openingContext = ClientSyncRuntime.mutationContextToken;
    final openingActor = Supabase.instance.client.auth.currentUser?.id;
    final selected =
        grid?.visibleCheckedRows
            .map((row) => grid.fromPlutoJson(row.toJson()).id)
            .toSet() ??
        {};
    // Reload saved values: grid cells may contain uncommitted role edits.
    final selection = await ExceptionHandler.guard(
      context,
      defaultErrorMessage: MemberAccessStrings.text('loadFailed'),
      futureFunction: () async => MemberAccessSelection(
        selected.cast<Object?>(),
        selected.isEmpty ? [] : (await grid!.loadData()).cast<Object>(),
      ),
    );
    if (selection == null) return;
    if (!context.mounted ||
        !ClientSyncRuntime.isCurrentMutationContext(openingContext) ||
        openingActor != Supabase.instance.client.auth.currentUser?.id)
      return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => MemberAccessDialog(
        scope: scope,
        scopeId: id,
        recipients: selection.recipients,
        selectionUnavailable: selection.unavailable,
      ),
    );
  }

  @override
  State<MemberAccessDialog> createState() => _MemberAccessDialogState();
}

class _MemberAccessDialogState extends State<MemberAccessDialog> {
  final email = TextEditingController();
  late final commands = MemberAccessCommands(Supabase.instance.client);
  String mode = 'invite_to_accept';
  final roles = <String, bool>{
    'is_editor': true,
    'is_editor_view': true,
    'is_manager': false,
  };
  MemberAccessBatch? batch;
  bool get selected => widget.recipients.isNotEmpty;
  bool get intentLocked => batch != null;
  Map<String, dynamic>? status;
  bool busy = false;
  bool invalidated = false;
  late final String? actor;
  late final StreamSubscription<AuthState> authChanges;
  final contextToken = ClientSyncRuntime.mutationContextToken;
  String? outcome;
  String t(String key) => MemberAccessStrings.text(key);
  @override
  void initState() {
    super.initState();
    if (selected) {
      mode = 'notify_existing_access';
      roles.updateAll((_, value) => false);
    }
    actor = Supabase.instance.client.auth.currentUser?.id;
    authChanges = Supabase.instance.client.auth.onAuthStateChange.listen(
      (_) => contextChanged(),
    );
    RightsService.occasionLinkModelNotifier.addListener(contextChanged);
    if (widget.scope == 'occasion')
      roles.addAll({
        'is_editor_order': false,
        'is_editor_order_view': false,
        'is_receptionist': false,
        'is_approver': false,
        'is_cleaning_crew': false,
      });
    load();
  }

  @override
  void dispose() {
    authChanges.cancel();
    RightsService.occasionLinkModelNotifier.removeListener(contextChanged);
    email.dispose();
    super.dispose();
  }

  void contextChanged() {
    if (!mounted || invalidated) return;
    if (actor == Supabase.instance.client.auth.currentUser?.id &&
        ClientSyncRuntime.isCurrentMutationContext(contextToken) &&
        (widget.scope == 'unit'
            ? RightsService.canUpdateUnitUsers()
            : RightsService.canUpdateUsers()))
      return;
    setState(() {
      invalidated = true;
      status = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  Future<void> load() async {
    try {
      final value = await commands.status(widget.scope, widget.scopeId);
      if (mounted)
        setState(() {
          status = value;
        });
    } catch (_) {
      if (mounted)
        setState(() {
          outcome = t('loadFailed');
        });
    }
  }

  Future<void> run(Future<void> Function() action, {String? success}) async {
    if (busy) return;
    setState(() {
      busy = true;
      outcome = null;
    });
    try {
      await action();
      if (mounted)
        setState(() {
          outcome =
              success ??
              t(batch != null && !batch!.complete ? 'batchPartial' : 'queued');
        });
      await load();
    } on MemberAccessFailure catch (error) {
      if (mounted)
        setState(() {
          outcome = failureText(error.reasonCode);
        });
    } catch (_) {
      if (mounted)
        setState(() {
          outcome = t('failed');
        });
    } finally {
      if (mounted)
        setState(() {
          busy = false;
        });
    }
  }

  Future<void> send() => run(() async {
    if (widget.selectionUnavailable) return;
    if (selected) {
      batch ??= MemberAccessBatch(
        scope: widget.scope,
        scopeId: widget.scopeId,
        recipients: widget.recipients,
        communication: mode,
        offeredRoles: roles,
      );
      await batch!.send(
        commands.send,
        isCurrent: () =>
            mounted &&
            !invalidated &&
            actor == Supabase.instance.client.auth.currentUser?.id &&
            ClientSyncRuntime.isCurrentMutationContext(contextToken),
        onProgress: () {
          if (mounted) setState(() {});
        },
      );
      return;
    }
    final address = email.text.trim().toLowerCase();
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(address))
      throw const MemberAccessFailure('invalid_email');
    final saving = mode == 'save_and_notify';
    await commands.send({
      'scope': {'type': widget.scope, 'id': widget.scopeId},
      'operation': saving ? 'save_member_and_invite' : 'send_invitation',
      'communication': saving ? 'notify_existing_access' : mode,
      'email': address,
      if (mode == 'invite_to_accept') 'roles': roles,
      if (saving)
        'changes': {
          if (widget.scope == 'unit') 'kind': 'editor',
          ...roles,
          'data': {'email': address},
        },
    });
  });
  String failureText(String reason) {
    const reasons = {
      'invalid_email',
      'scope_denied',
      'credential_operation_denied',
      'version_conflict',
      'command_payload_conflict',
      'preparation_deferred',
      'invitation_expired',
      'invitation_revoked',
      'wrong_identity',
      'upgrade_required',
      'dispatch_unresolved',
      'invitation_pending',
      'membership_required',
    };
    return t(reasons.contains(reason) ? reason : 'failed');
  }

  String recipientDescription(MemberAccessRecipient recipient) {
    final granted = recipient.roles.entries
        .where((entry) => entry.value)
        .map((entry) => t(entry.key))
        .join(', ');
    final lines = [
      '${t('currentPermissions')}: ${granted.isEmpty ? t('noPermissions') : granted}',
    ];
    final receipt = batch?.confirmed[recipient.userId];
    if (receipt != null) {
      final communication = receipt['communication'] as Map?;
      final messageId = communication?['messageId'];
      final messages = status?['messages'] as List? ?? [];
      final matching = messages.where(
        (message) => message['messageId'] == messageId,
      );
      lines.add(
        t(
          matching.isEmpty
              ? (communication?['state'] as String? ?? 'queued')
              : matching.first['state'] as String,
        ),
      );
    } else if (batch?.failures[recipient.userId] != null) {
      lines.add(failureText(batch!.failures[recipient.userId]!));
    }
    return lines.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    if (invalidated) return const SizedBox.shrink();
    final invitations = (status?['invitations'] as List? ?? []).cast<Map>();
    final messages = (status?['messages'] as List? ?? []).cast<Map>();
    void close() {
      if (!busy) Navigator.of(context).pop();
    }

    return PopScope(
      canPop: !busy,
      child: AppAlertDialog(
        title: Text(t('title')),
        onClose: close,
        dismissible: !busy,
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(t('explanation')),
                const SizedBox(height: 16),
                if (widget.selectionUnavailable)
                  Text(t('selectionUnavailable')),
                if (selected) ...[
                  Text(
                    '${t('selectedRecipients')} (${widget.recipients.length})',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(t('preservePermissions')),
                  for (final recipient in widget.recipients)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        recipient.name.isEmpty
                            ? recipient.email
                            : '${recipient.name}\n${recipient.email}',
                      ),
                      subtitle: Text(recipientDescription(recipient)),
                    ),
                ] else
                  TextField(
                    controller: email,
                    enabled: !busy,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(labelText: t('email')),
                  ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: mode,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: t('intent')),
                  items: [
                    for (final value in [
                      'invite_to_accept',
                      'notify_existing_access',
                      if (!selected) 'save_and_notify',
                      if (widget.scope == 'occasion') 'participant_credentials',
                    ])
                      DropdownMenuItem(value: value, child: Text(t(value))),
                  ],
                  onChanged: busy || intentLocked
                      ? null
                      : (value) => setState(() {
                          mode = value!;
                        }),
                ),
                if (selected && mode == 'invite_to_accept')
                  Text(t('additionalPermissions')),
                if (mode == 'invite_to_accept' || mode == 'save_and_notify')
                  for (final entry in roles.entries.toList())
                    CheckboxListTile(
                      title: Text(t(entry.key)),
                      value: entry.value,
                      contentPadding: EdgeInsets.zero,
                      onChanged: busy || intentLocked
                          ? null
                          : (value) => setState(() {
                              roles[entry.key] = value!;
                            }),
                    ),
                if (outcome != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(outcome!, semanticsLabel: outcome),
                  ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        t('history'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: t('refresh'),
                      onPressed: busy ? null : load,
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
                if (status == null) const LinearProgressIndicator(),
                if (status != null && invitations.isEmpty && messages.isEmpty)
                  Text(t('not_requested')),
                for (final invitation in invitations)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(invitation['email'] as String),
                    subtitle: Text(
                      t(
                        invitation['revokedAt'] != null
                            ? 'invitation_revoked'
                            : invitation['acceptedAt'] != null
                            ? 'accepted'
                            : DateTime.tryParse(
                                    invitation['expiresAt'] as String? ?? '',
                                  )?.isBefore(DateTime.now()) ==
                                  true
                            ? 'expired'
                            : 'pending',
                      ),
                    ),
                    trailing: Wrap(
                      children: [
                        if (invitation['acceptedAt'] == null &&
                            invitation['revokedAt'] == null)
                          IconButton(
                            tooltip: t('revoke'),
                            icon: const Icon(Icons.cancel_outlined),
                            onPressed: busy
                                ? null
                                : () => run(
                                    () => commands.revoke(
                                      invitation['id'] as String,
                                    ),
                                    success: t('invitation_revoked'),
                                  ),
                          ),
                        IconButton(
                          tooltip: t('resend'),
                          icon: const Icon(Icons.refresh),
                          onPressed: busy
                              ? null
                              : () => run(
                                  () => commands.resend(
                                    invitation['id'] as String,
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                for (final message in messages)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(t(message['state'] as String)),
                    subtitle: Text(
                      '${message['recipient'] ?? ''} - ${t(message['code'] == 'TEAM_INVITATION'
                          ? 'invite_to_accept'
                          : message['code'] == 'SIGN_IN_CODE'
                          ? 'participant_credentials'
                          : 'notify_existing_access')}',
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: busy ? null : close, child: Text(t('close'))),
          FilledButton(
            onPressed:
                busy ||
                    widget.selectionUnavailable ||
                    batch?.complete == true ||
                    (mode == 'invite_to_accept' &&
                        !roles.values.any((value) => value))
                ? null
                : send,
            child: Text(
              busy
                  ? t('working')
                  : batch != null && !batch!.complete
                  ? t('retryFailed')
                  : selected
                  ? t('sendSelected')
                  : t('send'),
            ),
          ),
        ],
      ),
    );
  }
}
