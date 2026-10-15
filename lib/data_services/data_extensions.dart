import 'package:collection/collection.dart' as data_extensions;
import 'package:festapp_core/program.dart';
import 'package:fstapp/components/information/information_model.dart';
import 'package:fstapp/components/map/path_group_model.dart';

import 'package:festapp_core/map.dart';

extension DataExtension on int? {
  int safeInt() => this ?? 0;
}

extension PlaceExtensions on List<PlaceModel> {
  void sortPlaces([bool asc = true]) {
    if (asc) {
      sort((a, b) => (a.order.safeInt().compareTo(b.order.safeInt())));
    } else {
      sort((b, a) => (a.order.safeInt().compareTo(b.order.safeInt())));
    }
  }
}

extension PathGroupsExtensions on List<PathGroupsModel> {
  void sortPathGroups([bool asc = true]) {
    if (asc) {
      sort((a, b) => (a.order.safeInt().compareTo(b.order.safeInt())));
    } else {
      sort((b, a) => (a.order.safeInt().compareTo(b.order.safeInt())));
    }
  }
}

extension DataExtensions on List<EventModel> {
  List<EventModel> sortEvents() => sortedBy((element) => element.title ?? "")
      .sortedBy((element) => element.startTime);

  List<EventModel> filterRootEvents() {
    List<EventModel> filtered = [];
    var children = where((element) => element.childEventIds != null)
        .expand((element) => element.childEventIds!)
        .toList();
    for (var e in where((element) => !children.contains(element.id!))) {
      filtered.add(e);
    }
    return filtered;
  }

  List<EventModel> withoutParentEvents() {
    return where((element) =>
            element.childEventIds == null || element.childEventIds!.isEmpty)
        .toList();
  }

  List<EventModel> filterNotHidden() {
    return where((e) => !(e.isHidden ?? false)).toList();
  }

  List<EventModel> timetableEventsFilter(int minimalDurationMinutes) {
    return filterRootEvents()
        .where((e) => e.place?.id != null)
        .where(
            (element) => element.duration().inMinutes >= minimalDurationMinutes)
        .toList();
  }
}

extension InfoExtensions on List<InformationModel> {
  List<InformationModel> filterByType(String? type) {
    if (type?.isEmpty ?? true) {
      return where((element) => element.type?.isEmpty ?? true).toList();
    }
    return where((element) => element.type == type).toList();
  }
}

extension DiacriticsAwareString on String {
  static const diacritics =
      'ÀÁÂÃÄÅàáâãäåÒÓÔÕÕÖØòóôõöøÈÉÊËĚèéêëěðČÇçčÐĎďÌÍÎÏìíîïĽľÙÚÛÜŮùúûüůŇÑñňŘřŠšŤťŸÝÿýŽž';
  static const nonDiacritics =
      'AAAAAAaaaaaaOOOOOOOooooooEEEEEeeeeeeCCccDDdIIIIiiiiLlUUUUUuuuuuNNnnRrSsTtYYyyZz';

  String get withoutDiacriticalMarks => splitMapJoin('',
      onNonMatch: (char) => char.isNotEmpty && diacritics.contains(char)
          ? nonDiacritics[diacritics.indexOf(char)]
          : char);
}
