import 'package:festapp_core/forms.dart';
import 'package:fstapp/services/time_helper.dart';

extension FormSchedulePresentation on FormDefinition {
  DateTime? get startTime => startTimeUtc?.toOccasionTime();
  DateTime? get endTime => endTimeUtc?.toOccasionTime();
}
