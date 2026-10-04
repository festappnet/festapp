import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/bank_accounts/bank_account_model.dart';
import 'package:fstapp/components/bank_accounts/bank_account_strings.dart';
import 'package:fstapp/services/toast_helper.dart';
import 'package:timeago/timeago.dart' as timeago;

class BankAccountConnectionTab extends StatefulWidget {
  final BankAccountModel account;
  final bool isReadOnly;
  final bool isFio;
  final bool isSaving;
  final String? pairingCode;
  final String emailDomain;
  final VoidCallback onRegenerateToken;
  final VoidCallback? onConnectEmail;

  // FIO token fields
  final TextEditingController tokenController;
  final DateTime? expiryDate;
  final ValueChanged<DateTime?> onExpiryDateChanged;
  final VoidCallback onSaveToken;

  const BankAccountConnectionTab({
    super.key,
    required this.account,
    required this.isReadOnly,
    required this.isFio,
    required this.isSaving,
    required this.pairingCode,
    required this.emailDomain,
    required this.onRegenerateToken,
    this.onConnectEmail,
    required this.tokenController,
    required this.expiryDate,
    required this.onExpiryDateChanged,
    required this.onSaveToken,
  });

  @override
  State<BankAccountConnectionTab> createState() =>
      _BankAccountConnectionTabState();
}

class _BankAccountConnectionTabState extends State<BankAccountConnectionTab> {
  bool _isTokenVisible = false;

  @override
  Widget build(BuildContext context) {
    final forwardingEmail = widget.account.bankSync?.receivingAddress ??
        'bank.${widget.pairingCode ?? '**********'}@${widget.emailDomain}';

    return SelectionArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.account.bankSync != null) ...[
              Text(
                  '${BankAccountStrings.connectionState}: ${widget.account.bankSync!.state}'),
              Text(
                  '${BankAccountStrings.bankPull}: ${widget.account.bankSync!.bankPullAt ?? BankAccountStrings.notReceived}'),
              Text(
                  '${BankAccountStrings.receiverCommit}: ${widget.account.bankSync!.receiverCommitAt ?? BankAccountStrings.notReceived}'),
              if (widget.account.bankSync!.lastError != null)
                Text(widget.account.bankSync!.lastError!),
              if (widget.account.bankSync!.mode == 'email')
                Text(BankAccountStrings.emailIdentityNotice),
              const SizedBox(height: 16),
            ],
            if (widget.isFio) ..._buildFioTokenSectionWidgets(),
            if (widget.account.bankSync == null &&
                widget.isFio &&
                !widget.isReadOnly)
              OutlinedButton(
                  onPressed: widget.onConnectEmail,
                  child: Text(BankAccountStrings.connectEmail)),
            if (widget.account.bankSync?.mode == 'email') ...[
              if (widget.isFio) ...[
                const SizedBox(height: 24),
                Row(
                  children: [
                    const Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: Text(CommonStrings.or.toUpperCase(),
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 12)),
                    ),
                    const Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: 24),
              ],
              Text(BankAccountStrings.syncInstruction),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.isFio) ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("💡 ", style: TextStyle(fontSize: 14)),
                          Expanded(
                              child: Text(
                                  BankAccountStrings
                                      .setupGuideExplanationFioNote,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13))),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                    Text(
                      BankAccountStrings.setupGuideExplanationTitle,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("✅ ", style: TextStyle(fontSize: 14)),
                        Expanded(
                            child: Text(
                                BankAccountStrings.setupGuideExplanationSet,
                                style: const TextStyle(fontSize: 13))),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("❌ ", style: TextStyle(fontSize: 14)),
                        Expanded(
                            child: Text(
                                BankAccountStrings.setupGuideExplanationNotSet,
                                style: const TextStyle(fontSize: 13))),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _buildGuideCard(
                context,
                title: BankAccountStrings.setupGuideTitle,
                steps: [
                  BankAccountStrings.setupGuideStep1,
                  BankAccountStrings.setupGuideStep2,
                  BankAccountStrings.setupGuideStep3,
                  BankAccountStrings.setupGuideStep4,
                  BankAccountStrings.setupGuideStep5,
                ],
              ),
              const SizedBox(height: 24),
              InputDecorator(
                decoration: InputDecoration(
                  labelText: BankAccountStrings.forwardingEmailLabel,
                  border: const OutlineInputBorder(),
                  suffixIcon: widget.pairingCode == null
                      ? const Icon(Icons.lock_outline, color: Colors.grey)
                      : IconButton(
                          icon: const Icon(Icons.copy),
                          onPressed: () {
                            Clipboard.setData(
                                ClipboardData(text: forwardingEmail));
                            ToastHelper.Show(
                                context, BankAccountStrings.copyEmail);
                          },
                        ),
                ),
                child: SelectableText(
                  forwardingEmail,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              if (widget.pairingCode == null)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline,
                          size: 16, color: Colors.grey),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          BankAccountStrings.maskedEmailExplanation,
                          style: const TextStyle(
                              color: Colors.grey,
                              fontStyle: FontStyle.italic,
                              fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.security, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      BankAccountStrings.emailSecurityNote,
                      style: TextStyle(
                          color: Theme.of(context).textTheme.bodySmall?.color,
                          fontSize: 13),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (!widget.isReadOnly)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: widget.onRegenerateToken,
                    icon: const Icon(Icons.refresh),
                    label: Text(BankAccountStrings.regenerateToken),
                  ),
                ),
              const SizedBox(height: 24),
              const SizedBox(height: 24),
              if (widget.account.lastFetchTime != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Center(
                    child: Text(
                      "${BankAccountStrings.lastFetchTime}: ${timeago.format(widget.account.lastFetchTime!.toLocal(), locale: context.locale.languageCode)}",
                      style: const TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _buildFioTokenSectionWidgets() {
    return [
      Text(BankAccountStrings.fioTokenInstruction),
      const SizedBox(height: 16),
      _buildGuideCard(
        context,
        title: BankAccountStrings.fioSetupGuideTitle,
        steps: [
          BankAccountStrings.fioSetupGuideStep1,
          BankAccountStrings.fioSetupGuideStep2,
          BankAccountStrings.fioSetupGuideStep3,
        ],
      ),
      const SizedBox(height: 16),
      if (widget.account.tokenMasked != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 16.0),
          child: Text(
            "${BankAccountStrings.tokenMaskedInfo}: ${widget.account.tokenMasked}",
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Text(
          "${BankAccountStrings.lastFioFetchTime}: ${widget.account.lastFioFetchTime == null ? BankAccountStrings.fioFetchNever : timeago.format(widget.account.lastFioFetchTime!.toLocal(), locale: context.locale.languageCode)}",
          style: const TextStyle(color: Colors.grey, fontSize: 13),
        ),
      ),
      TextFormField(
        controller: widget.tokenController,
        readOnly: widget.isReadOnly,
        obscureText: !_isTokenVisible,
        onChanged: (value) {
          if (widget.expiryDate != null) {
            widget.onExpiryDateChanged(null);
          }
        },
        decoration: InputDecoration(
          labelText: BankAccountStrings.fioTokenLabel,
          hintText: BankAccountStrings.fioTokenHint,
          helperText: widget.account.tokenMasked != null
              ? BankAccountStrings.leaveEmptyToKeepToken
              : null,
          suffixIcon: IconButton(
            icon:
                Icon(_isTokenVisible ? Icons.visibility : Icons.visibility_off),
            onPressed: () {
              setState(() {
                _isTokenVisible = !_isTokenVisible;
              });
            },
          ),
        ),
      ),
      const SizedBox(height: 16),
      InkWell(
        onTap: widget.isReadOnly
            ? null
            : () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: widget.expiryDate ?? DateTime.now(),
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                );
                if (picked != null) {
                  widget.onExpiryDateChanged(picked);
                }
              },
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: BankAccountStrings.tokenExpiryDateLabel,
            suffixIcon: const Icon(Icons.calendar_today),
          ),
          child: Text(
            widget.expiryDate != null
                ? DateFormat.yMd(context.locale.toString())
                    .format(widget.expiryDate!)
                : BankAccountStrings.setDate,
          ),
        ),
      ),
      const SizedBox(height: 24),
      if (!widget.isReadOnly)
        Center(
          child: ElevatedButton(
            onPressed: widget.isSaving ? null : widget.onSaveToken,
            child: widget.isSaving
                ? const CircularProgressIndicator()
                : Text(BankAccountStrings.updateToken),
          ),
        ),
    ];
  }

  Widget _buildGuideCard(BuildContext context,
      {required String title, required List<String> steps}) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: Theme.of(context).dividerColor,
        ),
      ),
      child: ExpansionTile(
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          steps.first,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        initiallyExpanded: false,
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: steps
            .asMap()
            .entries
            .map((e) => _buildStep(e.key + 1, e.value))
            .toList(),
      ),
    );
  }

  Widget _buildStep(int number, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 10,
            backgroundColor: Theme.of(context).colorScheme.primary,
            child: Text(
              number.toString(),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onPrimary,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
