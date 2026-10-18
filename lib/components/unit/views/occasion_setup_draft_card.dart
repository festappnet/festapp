import 'package:flutter/material.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/occasion/setup/occasion_setup_draft.dart';
import 'package:fstapp/components/occasion/setup/occasion_setup_strings.dart';
import 'package:fstapp/services/dialog_helper.dart';
import 'package:fstapp/services/exception_handler.dart';
import 'package:fstapp/styles/styles_config.dart';

class OccasionSetupDraftCard extends StatefulWidget {
  const OccasionSetupDraftCard(
      {super.key,
      required this.draft,
      required this.onResume,
      required this.onDelete});
  final OccasionSetupDraft draft;
  final VoidCallback onResume;
  final Future<void> Function() onDelete;

  @override
  State<OccasionSetupDraftCard> createState() => _OccasionSetupDraftCardState();
}

class _OccasionSetupDraftCardState extends State<OccasionSetupDraftCard> {
  bool _deleting = false;

  Future<void> _delete() async {
    if (_deleting) return;
    final delete = widget.onDelete;
    final confirmed = await DialogHelper.showConfirmationDialog(
        context,
        OccasionSetupStrings.cancelDraft,
        OccasionSetupStrings.cancelDraftConfirm(_title),
        confirmButtonMessage: OccasionSetupStrings.cancelDraft,
        cancelButtonMessage: CommonStrings.back);
    if (!confirmed || !mounted) return;
    setState(() => _deleting = true);
    await ExceptionHandler.guard(context, futureFunction: () async {
      await delete();
      return true;
    });
    if (mounted) setState(() => _deleting = false);
  }

  String get _title => widget.draft.title.trim().isEmpty
      ? OccasionSetupStrings.untitled
      : widget.draft.title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Card(
      elevation: 0,
      color: dark ? Colors.grey[850] : theme.cardColor,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(StylesConfig.commonRoundness),
          side:
              BorderSide(color: dark ? Colors.grey[700]! : theme.dividerColor)),
      child: InkWell(
        onTap: _deleting ? null : widget.onResume,
        child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
            child: Row(children: [
              PopupMenuButton<String>(
                  tooltip: '${CommonStrings.moreOptions}: $_title',
                  enabled: !_deleting,
                  icon: const Icon(Icons.more_vert),
                  onSelected: (_) => _delete(),
                  itemBuilder: (_) => [
                        PopupMenuItem(
                            value: 'delete',
                            child: Row(children: [
                              Icon(Icons.delete_outline,
                                  color: theme.colorScheme.error),
                              const SizedBox(width: 8),
                              Text(OccasionSetupStrings.cancelDraft,
                                  style: TextStyle(
                                      color: theme.colorScheme.error)),
                            ]))
                      ]),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                    Text(OccasionSetupStrings.draft,
                        style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 4),
                    Text(_title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    ExcludeSemantics(
                      child: LinearProgressIndicator(
                          value: widget.draft.progress / 100,
                          minHeight: 4,
                          borderRadius: BorderRadius.circular(4)),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        children: [
                          Text(
                              _deleting
                                  ? OccasionSetupStrings.cancellingDraft
                                  : OccasionSetupStrings.progress(
                                      widget.draft.progress),
                              style: theme.textTheme.bodySmall),
                          if (_deleting)
                            const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2)))
                          else
                            TextButton(
                                onPressed: widget.onResume,
                                child: Text(OccasionSetupStrings.resume)),
                        ]),
                  ])),
            ])),
      ),
    );
  }
}
