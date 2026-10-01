// ticket_feature.dart
import 'package:flutter/material.dart';
import 'package:collection/collection.dart';
import 'package:fstapp/components/ticket_layout/models/ticket_layout.dart';
import 'feature.dart';
import 'feature_constants.dart';

/// Ticket settings and the saved layout draft.
class TicketFeature extends Feature {
  String? ticketLightColor;
  String? ticketDarkColor;
  String? ticketBackground;
  String? ticketType;
  bool? canScanManually;
  bool? showHiddenNote;

  TicketFeature({
    required super.code,
    super.isEnabled,
    super.title,
    super.description,
    this.ticketLightColor,
    this.ticketDarkColor,
    this.ticketBackground,
    this.ticketType,
    this.canScanManually,
    this.showHiddenNote,
  });

  factory TicketFeature.fromJson(Map<String, dynamic> json) {
    return TicketFeature(
      code: json[FeatureConstants.metaCode],
      isEnabled: json[FeatureConstants.metaIsEnabled] ?? false,
      ticketLightColor: json[FeatureConstants.ticketLightColor],
      ticketDarkColor: json[FeatureConstants.ticketDarkColor],
      ticketBackground: json[FeatureConstants.ticketBackground],
      ticketType: json[FeatureConstants.ticketType],
      canScanManually: json[FeatureConstants.ticketCanScanManually] ?? false,
      showHiddenNote: json[FeatureConstants.ticketShowHiddenNote] ?? false,
    )
      ..layout = json[FeatureConstants.ticketLayout] == null
          ? null
          : copyTicketJson(json[FeatureConstants.ticketLayout])
      .._savedLayout = json[FeatureConstants.ticketLayout] == null
          ? null
          : copyTicketJson(json[FeatureConstants.ticketLayout]);
  }

  @override
  Map<String, dynamic> toJson() {
    final data = {
      FeatureConstants.metaCode: code,
      FeatureConstants.metaIsEnabled: isEnabled,
    };
    if (ticketLightColor != null) {
      data[FeatureConstants.ticketLightColor] = ticketLightColor!;
    }
    if (ticketDarkColor != null) {
      data[FeatureConstants.ticketDarkColor] = ticketDarkColor!;
    }
    if (ticketBackground != null) {
      data[FeatureConstants.ticketBackground] = ticketBackground!;
    }
    if (ticketType != null) data[FeatureConstants.ticketType] = ticketType!;
    if (canScanManually != null) {
      data[FeatureConstants.ticketCanScanManually] = canScanManually!;
    }
    if (showHiddenNote != null) {
      data[FeatureConstants.ticketShowHiddenNote] = showHiddenNote!;
    }
    if (layout != null) data[FeatureConstants.ticketLayout] = layout!;
    return data;
  }

  @override
  Widget buildFormField(BuildContext context) => const SizedBox.shrink();

  Map<String, dynamic>? layout;
  Map<String, dynamic>? _savedLayout;
  Map<String, dynamic>? conflictDraft;
  void loadSavedLayout(Map<String, dynamic>? saved) {
    conflictDraft = layout == null ? null : copyTicketJson(layout!);
    layout = saved == null ? null : copyTicketJson(saved);
    markLayoutSaved();
  }

  void restoreConflictDraft() {
    if (conflictDraft != null) layout = copyTicketJson(conflictDraft!);
    conflictDraft = null;
  }

  Map<String, dynamic>? get layoutChange =>
      const DeepCollectionEquality().equals(layout, _savedLayout)
          ? null
          : {'expected': _savedLayout, 'next': layout};
  void markLayoutSaved() {
    _savedLayout = layout == null ? null : copyTicketJson(layout!);
  }
}
