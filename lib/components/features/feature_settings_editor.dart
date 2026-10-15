import 'package:flutter/material.dart';
import 'package:fstapp/components/ticket_layout/views/ticket_settings.dart';
import 'feature.dart';
import 'ticket_feature.dart';
import 'editors/companion_feature_editor.dart';
import 'companion_feature.dart';
import 'editors/contract_feature_editor.dart';
import 'contract_feature.dart';
import 'editors/counseling_feature_editor.dart';
import 'counseling_feature.dart';
import 'editors/deposit_feature_editor.dart';
import 'deposit_feature.dart';
import 'editors/form_feature_editor.dart';
import 'form_feature.dart';
import 'editors/import_feature_editor.dart';
import 'import_feature.dart';
import 'editors/map_feature_editor.dart';
import 'map_feature.dart';
import 'editors/schedule_feature_editor.dart';
import 'schedule_feature.dart';
import 'editors/services_feature_editor.dart';
import 'services_feature.dart';
import 'editors/workshop_feature_editor.dart';
import 'workshop_feature.dart';

Widget buildFeatureSettingsEditor(BuildContext context, Feature feature,
    {required int occasionId,
    Future<void> Function(TicketFeature)? onSaveTicket,
    bool readOnly = false}) {
  if (feature is TicketFeature) {
    return TicketSettings(
        key: ValueKey(feature.layout),
        feature: feature,
        occasionId: occasionId,
        readOnly: readOnly,
        onSave: onSaveTicket);
  }
  if (feature is CompanionsFeature) return feature.buildSettingsEditor(context);
  if (feature is ContractFeature) return feature.buildSettingsEditor(context);
  if (feature is CounselingFeature) return feature.buildSettingsEditor(context);
  if (feature is DepositFeature) return feature.buildSettingsEditor(context);
  if (feature is FormFeature) return feature.buildSettingsEditor(context);
  if (feature is ImportFeature) return feature.buildSettingsEditor(context);
  if (feature is MapFeature) return feature.buildSettingsEditor(context);
  if (feature is ScheduleFeature) return feature.buildSettingsEditor(context);
  if (feature is ServicesFeature) return feature.buildSettingsEditor(context);
  if (feature is WorkshopsFeature) return feature.buildSettingsEditor(context);
  return const SizedBox.shrink();
}
