import 'package:fstapp/components/features/features_strings.dart';
import 'package:fstapp/components/inventory/views/inventory_strings.dart';
import 'package:fstapp/components/search/search_strings.dart';
import 'package:fstapp/components/event_feedback/event_feedback_strings.dart';
import 'package:fstapp/components/speakers/speakers_strings.dart';
import 'package:fstapp/components/cleaning/cleaning_strings.dart';
import 'feature_constants.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'schedule_feature.dart';

class FeatureMetadata {
  static Map<String, Map<String, String>> _rawMetadata() => {
        FeatureConstants.ticket: {
          'title': CommonStrings.ticket,
          'description': FeaturesStrings.ticketDescription,
        },
        FeatureConstants.deposit: {
          'title': FeaturesStrings.depositTitle,
          'description': FeaturesStrings.depositDescription,
        },
        FeatureConstants.globalSearch: {
          'title': SearchStrings.featureTitle,
          'description': SearchStrings.featureDescription,
        },
        FeatureConstants.eventFeedback: {
          'title': EventFeedbackStrings.featureTitle,
          'description': EventFeedbackStrings.featureDescription,
        },
        FeatureConstants.programNotifications: {
          'title': FeaturesStrings.programNotificationsTitle,
          'description': FeaturesStrings.programNotificationsDescription,
        },
        FeatureConstants.counseling: {
          'title': SpeakersStrings.counselingFeatureTitle,
          'description': SpeakersStrings.counselingFeatureDescription,
        },
        FeatureConstants.cleaning: {
          'title': CleaningStrings.featureTitle,
          'description': CleaningStrings.featureDescription,
        },
        FeatureConstants.reception: {
          'title': FeaturesStrings.receptionTitle,
          'description': FeaturesStrings.receptionDescription,
        },
        FeatureConstants.form: {
          'title': FeaturesStrings.formTitle,
          'description': FeaturesStrings.formDescription,
        },
        FeatureConstants.companions: {
          'title': CommonStrings.companions,
          'description': FeaturesStrings.companionsDescription,
        },
        FeatureConstants.songbook: {
          'title': CommonStrings.songbook,
          'description': FeaturesStrings.songbookDescription,
        },
        FeatureConstants.game: {
          'title': CommonStrings.game,
          'description': FeaturesStrings.gameDescription,
        },
        FeatureConstants.userGroups: {
          'title': CommonStrings.groups,
          'description': FeaturesStrings.groupsDescription,
        },
        FeatureConstants.mySchedule: {
          'title': CommonStrings.mySchedule,
          'description': FeaturesStrings.myScheduleDescription,
        },
        FeatureConstants.services: {
          'title': InventoryStrings.featureTitle,
          'description': InventoryStrings.featureDescription,
        },
        FeatureConstants.entryCode: {
          'title': FeaturesStrings.entryCodeTitle,
          'description': FeaturesStrings.entryCodeDescription,
        },
        FeatureConstants.blueprint: {
          'title': CommonStrings.blueprint,
          'description': FeaturesStrings.blueprintDescription,
        },
        FeatureConstants.map: {
          'title': CommonStrings.map,
          'description': FeaturesStrings.mapDescription,
        },
        FeatureConstants.timetable: {
          'title': FeaturesStrings.timetableTitle,
          'description': FeaturesStrings.timetableDescription,
        },
        FeatureConstants.workshops: {
          'title': FeaturesStrings.workshopsTitle,
          'description': FeaturesStrings.workshopsDescription,
        },
        ScheduleFeature.metaSchedule: {
          'title': CommonStrings.schedule,
          'description': FeaturesStrings.scheduleDescription,
        },
        FeatureConstants.volunteers: {
          'title': CommonStrings.volunteers,
          'description': FeaturesStrings.volunteersDescription,
        },
        FeatureConstants.import: {
          'title': CommonStrings.import,
          'description': FeaturesStrings.importFeatureDescription,
        },
        FeatureConstants.contract: {
          'title': FeaturesStrings.contractTitle,
          'description': FeaturesStrings.contractDescription,
        },
      };

  /// Returns the translated title for the given feature code.
  static String getTitle(String code) {
    return _rawMetadata()[code]?['title'] ?? '';
  }

  /// Returns the translated description for the given feature code.
  static String getDescription(String code) {
    return _rawMetadata()[code]?['description'] ?? '';
  }
}
