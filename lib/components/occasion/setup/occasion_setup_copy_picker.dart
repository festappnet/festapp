import 'package:material_ui/material_ui.dart';
import 'package:fstapp/widgets/app_dialog.dart';
import 'occasion_setup_strings.dart';

/// Lists only light authorized summaries; fetches the canonical projection on selection.
class OccasionSetupCopyPicker extends StatefulWidget {
  final Future<List<Map<String, dynamic>>> Function() load;
  final String kind;
  const OccasionSetupCopyPicker(
      {super.key, required this.load, required this.kind});
  @override
  State<OccasionSetupCopyPicker> createState() =>
      _OccasionSetupCopyPickerState();
}

class _OccasionSetupCopyPickerState extends State<OccasionSetupCopyPicker> {
  List<Map<String, dynamic>>? _rows;
  bool _error = false;
  String _query = '';
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _rows = null;
      _error = false;
    });
    try {
      final rows = await widget.load();
      if (mounted) setState(() => _rows = rows);
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows
        ?.where((r) => '${r['title']} ${r['occasionTitle']}'
            .toLowerCase()
            .contains(_query.toLowerCase()))
        .toList();
    return AppAlertDialog(
      title: Text(OccasionSetupStrings.story(
          widget.kind == 'forms' ? 'copyForm' : 'copyBlueprint')),
      content: SizedBox(
          width: 520,
          height: 420,
          child: Column(children: [
            TextField(
                decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    labelText: OccasionSetupStrings.story('searchCopies')),
                onChanged: (v) => setState(() => _query = v)),
            const SizedBox(height: 12),
            if (_error) ...[
              Text(OccasionSetupStrings.story('copiesFailed')),
              TextButton(
                  onPressed: _load, child: Text(OccasionSetupStrings.retry)),
            ] else if (rows == null)
              const LinearProgressIndicator()
            else if (rows.isEmpty)
              Text(OccasionSetupStrings.story(
                  _rows!.isEmpty ? 'copiesEmpty' : 'copiesSearchEmpty'))
            else
              Expanded(
                  child: ListView(children: [
                for (final row in rows)
                  ListTile(
                    title: Text(row['title'] as String? ?? ''),
                    subtitle: Text(row['occasionTitle'] as String? ?? ''),
                    onTap: () => Navigator.pop(context, row),
                  )
              ])),
          ])),
    );
  }
}
