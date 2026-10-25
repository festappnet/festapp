import 'package:material_ui/material_ui.dart';
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
    final accent = dark ? Colors.orange.shade300 : Colors.orange.shade900;
    final enlarged = MediaQuery.textScalerOf(context).scale(14) > 18;
    return Card(
      elevation: 0,
      color: Color.alphaBlend(accent.withValues(alpha: dark ? 0.08 : 0.04),
          dark ? Colors.grey[850]! : theme.cardColor),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(StylesConfig.commonRoundness),
          side: BorderSide(color: accent.withValues(alpha: 0.4))),
      child: InkWell(
        onTap: _deleting ? null : widget.onResume,
        child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 16, 4),
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
                    Text(
                        _deleting
                            ? OccasionSetupStrings.cancellingDraft
                            : enlarged
                                ? '${OccasionSetupStrings.draft} · ${widget.draft.progress} %'
                                : OccasionSetupStrings.draft,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium
                            ?.copyWith(color: accent)),
                    const SizedBox(height: 2),
                    Text(_title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    ExcludeSemantics(
                      child: LinearProgressIndicator(
                          value: widget.draft.progress / 100,
                          color: accent,
                          backgroundColor: accent.withValues(alpha: 0.15),
                          minHeight: 3,
                          borderRadius: BorderRadius.circular(4)),
                    ),
                    if (!enlarged) ...[
                      const SizedBox(height: 4),
                      Text(OccasionSetupStrings.progress(widget.draft.progress),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall),
                    ],
                  ])),
              const SizedBox(width: 12),
              if (_deleting)
                const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
              else
                Icon(Icons.chevron_right,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.55)),
            ])),
      ),
    );
  }
}
