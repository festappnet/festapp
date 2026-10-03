import 'ticket_feature.dart';
import 'package:fstapp/components/ticket_layout/views/ticket_settings.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/theme_config.dart';

import 'feature.dart';
import 'feature_metadata.dart';

class FeatureForm extends StatefulWidget {
  final Feature feature;
  final int occasion;
  final Future<void> Function(TicketFeature)? onSaveTicket;

  const FeatureForm(
      {super.key,
      required this.feature,
      required this.occasion,
      this.onSaveTicket});

  @override
  _FeatureFormState createState() => _FeatureFormState();
}

class _FeatureFormState extends State<FeatureForm> {
  late bool isEnabled;

  @override
  void initState() {
    super.initState();
    isEnabled = widget.feature.isEnabled;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
      margin: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 0.0),
      elevation: 0,
      child: ExpansionTile(
        key: ValueKey("${widget.feature.code}_$isEnabled"),
        initiallyExpanded: isEnabled,
        shape: const Border(),
        collapsedShape: const Border(),
        title: SelectableText(
          FeatureMetadata.getTitle(widget.feature.code),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        subtitle: SelectableText(
          FeatureMetadata.getDescription(widget.feature.code),
          style: TextStyle(fontSize: 14, color: ThemeConfig.grey700(context)),
        ),
        trailing: Switch(
          value: isEnabled,
          onChanged: widget.feature.canBeDisabled
              ? (value) {
                  setState(() {
                    isEnabled = value;
                    widget.feature.isEnabled = value;
                  });
                }
              : null,
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: isEnabled ? _buildFeatureFields(context) : [],
      ),
    );
  }

  /// Builds additional fields based on the feature type.
  List<Widget> _buildFeatureFields(BuildContext context) {
    return [
      widget.feature is TicketFeature
          ? TicketSettings(
              key: ValueKey((widget.feature as TicketFeature).layout),
              feature: widget.feature as TicketFeature,
              occasionId: widget.occasion,
              onSave: widget.onSaveTicket)
          : widget.feature.buildFormField(context),
    ];
  }
}
