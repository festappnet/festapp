import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/app_router.dart';
import '../../_shared/common_strings.dart';
import '../../forms/db_forms.dart';
import '../blueprint_model.dart';
import '../blueprint_strings.dart';
import 'blueprint_layout_host.dart';

/// The occasion route loads the canonical layout aggregate. Missing or invalid
/// layouts remain repairable load failures; no alternate editor is selected.
class BlueprintTab extends StatefulWidget {
  const BlueprintTab({super.key});

  @override
  State<BlueprintTab> createState() => _BlueprintTabState();
}

class _BlueprintTabState extends State<BlueprintTab> {
  BlueprintModel? _source;
  String? _occasionLink;
  bool _loading = true;
  int _generation = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final params = context.routeData.inheritedPathParams;
    if (params.isEmpty) return;
    final link = params.getString(AppRouter.linkFormatted);
    if (link == _occasionLink) return;
    _occasionLink = link;
    _load();
  }

  Future<void> _load() async {
    final link = _occasionLink;
    if (link == null) return;
    final generation = ++_generation;
    setState(() { _loading = true; _source = null; });
    BlueprintModel? source;
    try {
      source = await DbForms.getBlueprintForEdit(link);
      if (source?.layoutSnapshot == null) source = null;
    } catch (_) {
      // Retry remains available for transport and aggregate-validation errors.
    }
    if (!mounted || generation != _generation) return;
    setState(() { _source = source; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final source = _source;
    if (source != null) {
      return BlueprintLayoutHost(
        key: ValueKey(source.id),
        source: source,
        reload: () => DbForms.getBlueprintForEdit(_occasionLink!),
      );
    }
    return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Text(BlueprintStrings.layoutUnavailable),
      const SizedBox(height: 12),
      TextButton.icon(onPressed: _load, icon: const Icon(Icons.refresh),
          label: Text(CommonStrings.retry)),
    ]));
  }
}
