import 'package:flutter/material.dart';
import 'package:fstapp/components/cleaning/cleaning_status.dart';
import 'package:fstapp/components/cleaning/cleaning_strings.dart';
import 'package:fstapp/components/cleaning/models/cleaning_report.dart';
import 'package:fstapp/theme_config.dart';
import 'package:intl/intl.dart';

/// One compact text line in the crew History tab: date · WC · type · reporter ·
/// state, with any notes indented beneath.
class CleaningHistoryRow extends StatelessWidget {
  final CleaningReport report;
  const CleaningHistoryRow({super.key, required this.report});

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat.Md().add_jm();
    final resolved = report.resolvedAt != null;
    final typeColor = CleaningStatusHelper.colorForType(report.problemType);
    final notes = <String>[
      if (report.note != null && report.note!.isNotEmpty) report.note!,
      ...report.extraNotes,
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 4, right: 8),
                child: Container(
                  width: 10,
                  height: 10,
                  decoration:
                      BoxDecoration(color: typeColor, shape: BoxShape.circle),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${dateFmt.format(report.createdAt)} · ${report.placeTitle} · ${CleaningStrings.problemLabel(report.problemType)}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '${report.createdByName ?? CleaningStrings.anonymous} · ${resolved ? CleaningStrings.historyCleanedAt(dateFmt.format(report.resolvedAt!)) : CleaningStrings.historyOpen}',
                      style: TextStyle(
                          fontSize: 12, color: ThemeConfig.grey600(context)),
                    ),
                    for (final note in notes)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text('„$note"',
                            style:
                                const TextStyle(fontStyle: FontStyle.italic)),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 14),
        ],
      ),
    );
  }
}
