// dart format width=80
// GENERATED CODE - DO NOT MODIFY BY HAND

// **************************************************************************
// AutoRouterGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'dart:async' as _i45;

import 'package:auto_route/auto_route.dart' as _i42;
import 'package:flutter/foundation.dart' as _i44;
import 'package:flutter/material.dart' as _i43;
import 'package:fstapp/components/app_management/install_page.dart' as _i12;
import 'package:fstapp/components/app_management/instance_install_page.dart'
    as _i13;
import 'package:fstapp/components/app_management/settings_page.dart' as _i33;
import 'package:fstapp/components/cleaning/cleaning_page.dart' as _i3;
import 'package:fstapp/components/forms/views/form_page.dart' as _i8;
import 'package:fstapp/components/forms/views/forms_tab.dart' as _i9;
import 'package:fstapp/components/forms/views/reservation_page.dart' as _i26;
import 'package:fstapp/components/information/game/game_page.dart' as _i10;
import 'package:fstapp/components/information/info_page.dart' as _i11;
import 'package:fstapp/components/information/song/song_page.dart' as _i35;
import 'package:fstapp/components/inventory/views/inventory_pools_tab.dart'
    as _i14;
import 'package:fstapp/components/inventory/views/user_stay_page.dart' as _i41;
import 'package:fstapp/components/map/map_page.dart' as _i17;
import 'package:fstapp/components/news/news_form_page.dart' as _i19;
import 'package:fstapp/components/news/news_page.dart' as _i20;
import 'package:fstapp/components/occasion/admin_page.dart' as _i1;
import 'package:fstapp/components/occasion/occasion_home_page.dart' as _i21;
import 'package:fstapp/components/organization/views/organization_edit_page.dart'
    as _i22;
import 'package:fstapp/components/organization/views/organization_edit_redirect_page.dart'
    as _i23;
import 'package:fstapp/components/reception/login_qr_scanner_page.dart' as _i16;
import 'package:fstapp/components/reception/reception_page.dart' as _i25;
import 'package:fstapp/components/scan/check_page.dart' as _i2;
import 'package:fstapp/components/scan/scan_page.dart' as _i28;
import 'package:fstapp/components/schedule/event_edit_page.dart' as _i5;
import 'package:fstapp/components/schedule/event_page.dart' as _i6;
import 'package:fstapp/components/schedule/my_schedule_page.dart' as _i18;
import 'package:fstapp/components/schedule/schedule_basic_page.dart' as _i29;
import 'package:fstapp/components/schedule/schedule_light_page.dart' as _i30;
import 'package:fstapp/components/schedule/schedule_navigation_screen.dart'
    as _i31;
import 'package:fstapp/components/schedule/schedule_page.dart' as _i32;
import 'package:fstapp/components/schedule/timetable_page.dart' as _i36;
import 'package:fstapp/components/speakers/counseling_page.dart' as _i4;
import 'package:fstapp/components/unit/views/organization_page.dart' as _i24;
import 'package:fstapp/components/unit/views/unit_admin_page.dart' as _i38;
import 'package:fstapp/components/unit/views/unit_page.dart' as _i39;
import 'package:fstapp/components/users/views/forgot_password_page.dart' as _i7;
import 'package:fstapp/components/users/views/login_page.dart' as _i15;
import 'package:fstapp/components/users/views/reset_password_page.dart' as _i27;
import 'package:fstapp/components/users/views/signup_page.dart' as _i34;
import 'package:fstapp/components/users/views/transfer_page.dart' as _i37;
import 'package:fstapp/components/users/views/user_page.dart' as _i40;

/// generated route for
/// [_i1.AdminPage]
class AdminRoute extends _i42.PageRouteInfo<void> {
  const AdminRoute({List<_i42.PageRouteInfo>? children})
      : super(AdminRoute.name, initialChildren: children);

  static const String name = 'AdminRoute';

  static _i42.PageInfo page = _i42.PageInfo(
    name,
    builder: (data) {
      return const _i1.AdminPage();
    },
  );
}

/// generated route for
/// [_i2.CheckPage]
class CheckRoute extends _i42.PageRouteInfo<CheckRouteArgs> {
  CheckRoute({
    required int id,
    _i43.Key? key,
    List<_i42.PageRouteInfo>? children,
  }) : super(
          CheckRoute.name,
          args: CheckRouteArgs(id: id, key: key),
          rawPathParams: {'id': id},
          initialChildren: children,
        );

  static const String name = 'CheckRoute';

  static _i42.PageInfo page = _i42.PageInfo(
    name,
    builder: (data) {
      final pathParams = data.inheritedPathParams;
      final args = data.argsAs<CheckRouteArgs>(
        orElse: () => CheckRouteArgs(id: pathParams.getInt('id')),
      );
      return _i2.CheckPage(id: args.id, key: args.key);
    },
  );
}

class CheckRouteArgs {
  const CheckRouteArgs({required this.id, this.key});

  final int id;

  final _i43.Key? key;

  @override
  String toString() {
    return 'CheckRouteArgs{id: $id, key: $key}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! CheckRouteArgs) return false;
    return id == other.id && key == other.key;
  }

  @override
  int get hashCode => id.hashCode ^ key.hashCode;
}

/// generated route for
/// [_i3.CleaningPage]
class CleaningRoute extends _i42.PageRouteInfo<CleaningRouteArgs> {
  CleaningRoute({int? id, _i44.Key? key, List<_i42.PageRouteInfo>? children})
      : super(
          CleaningRoute.name,
          args: CleaningRouteArgs(id: id, key: key),
          rawPathParams: {'id': id},
          initialChildren: children,
        );

  static const String name = 'CleaningRoute';

  static _i42.PageInfo page = _i42.PageInfo(
    name,
    builder: (data) {
      final pathParams = data.inheritedPathParams;
      final args = data.argsAs<CleaningRouteArgs>(
        orElse: () => CleaningRouteArgs(id: pathParams.optInt('id')),
      );
      return _i3.CleaningPage(id: args.id, key: args.key);
    },
  );
}

class CleaningRouteArgs {
  const CleaningRouteArgs({this.id, this.key});

  final int? id;

  final _i44.Key? key;

  @override
  String toString() {
    return 'CleaningRouteArgs{id: $id, key: $key}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! CleaningRouteArgs) return false;
    return id == other.id && key == other.key;
  }

  @override
  int get hashCode => id.hashCode ^ key.hashCode;
}

/// generated route for
/// [_i4.CounselingPage]
class CounselingRoute extends _i42.PageRouteInfo<void> {
  const CounselingRoute({List<_i42.PageRouteInfo>? children})
      : super(CounselingRoute.name, initialChildren: children);

  static const String name = 'CounselingRoute';

  static _i42.PageInfo page = _i42.PageInfo(
    name,
    builder: (data) {
      return const _i4.CounselingPage();
    },
  );
}

/// generated route for
/// [_i5.EventEditPage]
class EventEditRoute extends _i42.PageRouteInfo<EventEditRouteArgs> {
  EventEditRoute({_i43.Key? key, int? id, List<_i42.PageRouteInfo>? children})
      : super(
          EventEditRoute.name,
          args: EventEditRouteArgs(key: key, id: id),
          rawPathParams: {'id': id},
          initialChildren: children,
        );

  static const String name = 'EventEditRoute';

  static _i42.PageInfo page = _i42.PageInfo(
    name,
    builder: (data) {
      final pathParams = data.inheritedPathParams;
      final args = data.argsAs<EventEditRouteArgs>(
        orElse: () => EventEditRouteArgs(id: pathParams.optInt('id')),
      );
      return _i5.EventEditPage(key: args.key, id: args.id);
    },
  );
}

class EventEditRouteArgs {
  const EventEditRouteArgs({this.key, this.id});

  final _i43.Key? key;

  final int? id;

  @override
  String toString() {
    return 'EventEditRouteArgs{key: $key, id: $id}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! EventEditRouteArgs) return false;
    return key == other.key && id == other.id;
  }

  @override
  int get hashCode => key.hashCode ^ id.hashCode;
}

/// generated route for
/// [_i6.EventPage]
class EventRoute extends _i42.PageRouteInfo<EventRouteArgs> {
  EventRoute({int? id, _i43.Key? key, List<_i42.PageRouteInfo>? children})
      : super(
          EventRoute.name,
          args: EventRouteArgs(id: id, key: key),
          rawPathParams: {'id': id},
          initialChildren: children,
        );

  static const String name = 'EventRoute';

  static _i42.PageInfo page = _i42.PageInfo(
    name,
    builder: (data) {
      final pathParams = data.inheritedPathParams;
      final args = data.argsAs<EventRouteArgs>(
        orElse: () => EventRouteArgs(id: pathParams.optInt('id')),
      );
      return _i6.EventPage(id: args.id, key: args.key);
    },
  );
}

class EventRouteArgs {
  const EventRouteArgs({this.id, this.key});

  final int? id;

  final _i43.Key? key;

  @override
  String toString() {
    return 'EventRouteArgs{id: $id, key: $key}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! EventRouteArgs) return false;
    return id == other.id && key == other.key;
  }

  @override
  int get hashCode => id.hashCode ^ key.hashCode;
}

/// generated route for
/// [_i7.ForgotPasswordPage]
class ForgotPasswordRoute extends _i42.PageRouteInfo<void> {
  const ForgotPasswordRoute({List<_i42.PageRouteInfo>? children})
      : super(ForgotPasswordRoute.name, initialChildren: children);

  static const String name = 'ForgotPasswordRoute';

  static _i42.PageInfo page = _i42.PageInfo(
    name,
    builder: (data) {
      return const _i7.ForgotPasswordPage();
    },
  );
}

/// generated route for
/// [_i8.FormPage]
class FormRoute extends _i42.PageRouteInfo<FormRouteArgs> {
  FormRoute({
    _i43.Key? key,
    String? formLink,
    List<_i42.PageRouteInfo>? children,
  }) : super(
          FormRoute.name,
          args: FormRouteArgs(key: key, formLink: formLink),
          rawPathParams: {'formLink': formLink},
          initialChildren: children,
        );

  static const String name = 'FormRoute';

  static _i42.PageInfo page = _i42.PageInfo(
    name,
    builder: (data) {
      final pathParams = data.inheritedPathParams;
      final args = data.argsAs<FormRouteArgs>(
        orElse: () => FormRouteArgs(formLink: pathParams.optString('formLink')),
      );
      return _i8.FormPage(key: args.key, formLink: args.formLink);
    },
  );
}

class FormRouteArgs {
  const FormRouteArgs({this.key, this.formLink});

  final _i43.Key? key;

  final String? formLink;

  @override
  String toString() {
    return 'FormRouteArgs{key: $key, formLink: $formLink}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! FormRouteArgs) return false;
    return key == other.key && formLink == other.formLink;
  }

  @override
  int get hashCode => key.hashCode ^ formLink.hashCode;
}

/// generated route for
/// [_i9.FormsTab]
class FormsTab extends _i42.PageRouteInfo<void> {
  const FormsTab({List<_i42.PageRouteInfo>? children})
      : super(FormsTab.name, initialChildren: children);

  static const String name = 'FormsTab';

  static _i42.PageInfo page = _i42.PageInfo(
    name,
    builder: (data) {
      return const _i9.FormsTab();
    },
  );
}

/// generated route for
/// [_i10.GamePage]
class GameRoute extends _i42.PageRouteInfo<void> {
  const GameRoute({List<_i42.PageRouteInfo>? children})
      : super(GameRoute.name, initialChildren: children);

  static const String name = 'GameRoute';

  static _i42.PageInfo page = _i42.PageInfo(
    name,
    builder: (data) {
      return const _i10.GamePage();
    },
  );
}

/// generated route for
/// [_i11.InfoPage]
class InfoRoute extends _i42.PageRouteInfo<InfoRouteArgs> {
  InfoRoute({int? id, _i44.Key? key, List<_i42.PageRouteInfo>? children})
      : super(
          InfoRoute.name,
          args: InfoRouteArgs(id: id, key: key),
          rawPathParams: {'id': id},
          initialChildren: children,
        );

  static const String name = 'InfoRoute';

  static _i42.PageInfo page = _i42.PageInfo(
    name,
    builder: (data) {
      final pathParams = data.inheritedPathParams;
      final args = data.argsAs<InfoRouteArgs>(
        orElse: () => InfoRouteArgs(id: pathParams.optInt('id')),
      );
      return _i11.InfoPage(id: args.id, key: args.key);
    },
  );
}

class InfoRouteArgs {
  const InfoRouteArgs({this.id, this.key});

  final int? id;

  final _i44.Key? key;

  @override
  String toString() {
    return 'InfoRouteArgs{id: $id, key: $key}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! InfoRouteArgs) return false;
    return id == other.id && key == other.key;
  }

  @override
  int get hashCode => id.hashCode ^ key.hashCode;
}

/// generated route for
/// [_i12.InstallPage]
class InstallRoute extends _i42.PageRouteInfo<void> {
  const InstallRoute({List<_i42.PageRouteInfo>? children})
      : super(InstallRoute.name, initialChildren: children);

  static const String name = 'InstallRoute';

  static _i42.PageInfo page = _i42.PageInfo(
    name,
    builder: (data) {
      return const _i12.InstallPage();
    },
  );
}

/// generated route for
/// [_i13.InstanceInstallPage]
class InstanceInstallRoute extends _i42.PageRouteInfo<void> {
  const InstanceInstallRoute({List<_i42.PageRouteInfo>? children})
      : super(InstanceInstallRoute.name, initialChildren: children);

  static const String name = 'InstanceInstallRoute';

  static _i42.PageInfo page = _i42.PageInfo(
    name,
    builder: (data) {
      return const _i13.InstanceInstallPage();
    },
  );
}

/// generated route for
/// [_i14.InventoryPoolsTab]
class InventoryPoolsTab extends _i42.PageRouteInfo<void> {
  const InventoryPoolsTab({List<_i42.PageRouteInfo>? children})
      : super(InventoryPoolsTab.name, initialChildren: children);

  static const String name = 'InventoryPoolsTab';

  static _i42.PageInfo page = _i42.PageInfo(
    name,
    builder: (data) {
      return const _i14.InventoryPoolsTab();
    },
  );
}

/// generated route for
/// [_i15.LoginPage]
class LoginRoute extends _i42.PageRouteInfo<void> {
  const LoginRoute({List<_i42.PageRouteInfo>? children})
      : super(LoginRoute.name, initialChildren: children);

  static const String name = 'LoginRoute';

  static _i42.PageInfo page = _i42.PageInfo(
    name,
    builder: (data) {
      return const _i15.LoginPage();
    },
  );
}

/// generated route for
/// [_i16.LoginQrScannerPage]
class LoginQrScannerRoute extends _i42.PageRouteInfo<void> {
  const LoginQrScannerRoute({List<_i42.PageRouteInfo>? children})
      : super(LoginQrScannerRoute.name, initialChildren: children);

  static const String name = 'LoginQrScannerRoute';

  static _i42.PageInfo page = _i42.PageInfo(
    name,
    builder: (data) {
      return const _i16.LoginQrScannerPage();
    },
  );
}

/// generated route for
/// [_i17.MapEditorPage]
class MapEditorRoute extends _i42.PageRouteInfo<MapEditorRouteArgs> {
  MapEditorRoute({
    required _i17.MapEditorMode mode,
    _i44.Key? key,
    List<_i42.PageRouteInfo>? children,
  }) : super(
          MapEditorRoute.name,
          args: MapEditorRouteArgs(mode: mode, key: key),
          initialChildren: children,
        );

  static const String name = 'MapEditorRoute';

  static _i42.PageInfo page = _i42.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<MapEditorRouteArgs>();
      return _i17.MapEditorPage(mode: args.mode, key: args.key);
    },
  );
}

class MapEditorRouteArgs {
  const MapEditorRouteArgs({required this.mode, this.key});

  final _i17.MapEditorMode mode;

  final _i44.Key? key;

  @override
  String toString() {
    return 'MapEditorRouteArgs{mode: $mode, key: $key}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! MapEditorRouteArgs) return false;
    return mode == other.mode && key == other.key;
  }

  @override
  int get hashCode => mode.hashCode ^ key.hashCode;
}

/// generated route for
/// [_i18.MySchedulePage]
class MyScheduleRoute extends _i42.PageRouteInfo<void> {
  const MyScheduleRoute({List<_i42.PageRouteInfo>? children})
      : super(MyScheduleRoute.name, initialChildren: children);

  static const String name = 'MyScheduleRoute';

  static _i42.PageInfo page = _i42.PageInfo(
    name,
    builder: (data) {
      return const _i18.MySchedulePage();
    },
  );
}

/// generated route for
/// [_i19.NewsFormPage]
class NewsFormRoute extends _i42.PageRouteInfo<NewsFormRouteArgs> {
  NewsFormRoute({
    _i44.Key? key,
    _i43.Widget? editorOverride,
    _i45.Future<void> Function(_i19.NewsSubmission)? onSubmit,
    List<_i42.PageRouteInfo>? children,
  }) : super(
          NewsFormRoute.name,
          args: NewsFormRouteArgs(
            key: key,
            editorOverride: editorOverride,
            onSubmit: onSubmit,
          ),
          initialChildren: children,
        );

  static const String name = 'NewsFormRoute';

  static _i42.PageInfo page = _i42.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<NewsFormRouteArgs>(
        orElse: () => const NewsFormRouteArgs(),
      );
      return _i19.NewsFormPage(
        key: args.key,
        editorOverride: args.editorOverride,
        onSubmit: args.onSubmit,
      );
    },
  );
}

class NewsFormRouteArgs {
  const NewsFormRouteArgs({this.key, this.editorOverride, this.onSubmit});

  final _i44.Key? key;

  final _i43.Widget? editorOverride;

  final _i45.Future<void> Function(_i19.NewsSubmission)? onSubmit;

  @override
  String toString() {
    return 'NewsFormRouteArgs{key: $key, editorOverride: $editorOverride, onSubmit: $onSubmit}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! NewsFormRouteArgs) return false;
    return key == other.key && editorOverride == other.editorOverride;
  }

  @override
  int get hashCode => key.hashCode ^ editorOverride.hashCode;
}

/// generated route for
/// [_i20.NewsPage]
class NewsRoute extends _i42.PageRouteInfo<NewsRouteArgs> {
  NewsRoute({
    _i43.Key? key,
    _i43.VoidCallback? onSetAsRead,
    List<_i42.PageRouteInfo>? children,
  }) : super(
          NewsRoute.name,
          args: NewsRouteArgs(key: key, onSetAsRead: onSetAsRead),
          initialChildren: children,
        );

  static const String name = 'NewsRoute';

  static _i42.PageInfo page = _i42.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<NewsRouteArgs>(
        orElse: () => const NewsRouteArgs(),
      );
      return _i20.NewsPage(key: args.key, onSetAsRead: args.onSetAsRead);
    },
  );
}

class NewsRouteArgs {
  const NewsRouteArgs({this.key, this.onSetAsRead});

  final _i43.Key? key;

  final _i43.VoidCallback? onSetAsRead;

  @override
  String toString() {
    return 'NewsRouteArgs{key: $key, onSetAsRead: $onSetAsRead}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! NewsRouteArgs) return false;
    return key == other.key && onSetAsRead == other.onSetAsRead;
  }

  @override
  int get hashCode => key.hashCode ^ onSetAsRead.hashCode;
}

/// generated route for
/// [_i21.OccasionHomePage]
class OccasionHomeRoute extends _i42.PageRouteInfo<void> {
  const OccasionHomeRoute({List<_i42.PageRouteInfo>? children})
      : super(OccasionHomeRoute.name, initialChildren: children);

  static const String name = 'OccasionHomeRoute';

  static _i42.PageInfo page = _i42.PageInfo(
    name,
    builder: (data) {
      return const _i21.OccasionHomePage();
    },
  );
}

/// generated route for
/// [_i22.OrganizationEditPage]
class OrganizationEditRoute
    extends _i42.PageRouteInfo<OrganizationEditRouteArgs> {
  OrganizationEditRoute({
    _i43.Key? key,
    required int id,
    List<_i42.PageRouteInfo>? children,
  }) : super(
          OrganizationEditRoute.name,
          args: OrganizationEditRouteArgs(key: key, id: id),
          rawPathParams: {'id': id},
          initialChildren: children,
        );

  static const String name = 'OrganizationEditRoute';

  static _i42.PageInfo page = _i42.PageInfo(
    name,
    builder: (data) {
      final pathParams = data.inheritedPathParams;
      final args = data.argsAs<OrganizationEditRouteArgs>(
        orElse: () => OrganizationEditRouteArgs(id: pathParams.getInt('id')),
      );
      return _i22.OrganizationEditPage(key: args.key, id: args.id);
    },
  );
}

class OrganizationEditRouteArgs {
  const OrganizationEditRouteArgs({this.key, required this.id});

  final _i43.Key? key;

  final int id;

  @override
  String toString() {
    return 'OrganizationEditRouteArgs{key: $key, id: $id}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! OrganizationEditRouteArgs) return false;
    return key == other.key && id == other.id;
  }

  @override
  int get hashCode => key.hashCode ^ id.hashCode;
}

/// generated route for
/// [_i23.OrganizationEditRedirectPage]
class OrganizationEditRedirectRoute extends _i42.PageRouteInfo<void> {
  const OrganizationEditRedirectRoute({List<_i42.PageRouteInfo>? children})
      : super(OrganizationEditRedirectRoute.name, initialChildren: children);

  static const String name = 'OrganizationEditRedirectRoute';

  static _i42.PageInfo page = _i42.PageInfo(
    name,
    builder: (data) {
      return const _i23.OrganizationEditRedirectPage();
    },
  );
}

/// generated route for
/// [_i24.OrganizationPage]
class OrganizationRoute extends _i42.PageRouteInfo<OrganizationRouteArgs> {
  OrganizationRoute({
    int? id,
    _i43.Key? key,
    List<_i42.PageRouteInfo>? children,
  }) : super(
          OrganizationRoute.name,
          args: OrganizationRouteArgs(id: id, key: key),
          rawPathParams: {'id': id},
          initialChildren: children,
        );

  static const String name = 'OrganizationRoute';

  static _i42.PageInfo page = _i42.PageInfo(
    name,
    builder: (data) {
      final pathParams = data.inheritedPathParams;
      final args = data.argsAs<OrganizationRouteArgs>(
        orElse: () => OrganizationRouteArgs(id: pathParams.optInt('id')),
      );
      return _i24.OrganizationPage(id: args.id, key: args.key);
    },
  );
}

class OrganizationRouteArgs {
  const OrganizationRouteArgs({this.id, this.key});

  final int? id;

  final _i43.Key? key;

  @override
  String toString() {
    return 'OrganizationRouteArgs{id: $id, key: $key}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! OrganizationRouteArgs) return false;
    return id == other.id && key == other.key;
  }

  @override
  int get hashCode => id.hashCode ^ key.hashCode;
}

/// generated route for
/// [_i17.PublicMapPage]
class PublicMapRoute extends _i42.PageRouteInfo<PublicMapRouteArgs> {
  PublicMapRoute({
    String destination = 'overview',
    String? placeType,
    _i44.Key? key,
    List<_i42.PageRouteInfo>? children,
  }) : super(
          PublicMapRoute.name,
          args: PublicMapRouteArgs(
            destination: destination,
            placeType: placeType,
            key: key,
          ),
          rawPathParams: {'destination': destination},
          rawQueryParams: {'placeType': placeType},
          initialChildren: children,
        );

  static const String name = 'PublicMapRoute';

  static _i42.PageInfo page = _i42.PageInfo(
    name,
    builder: (data) {
      final pathParams = data.inheritedPathParams;
      final queryParams = data.queryParams;
      final args = data.argsAs<PublicMapRouteArgs>(
        orElse: () => PublicMapRouteArgs(
          destination: pathParams.getString('destination', 'overview'),
          placeType: queryParams.optString('placeType'),
        ),
      );
      return _i17.PublicMapPage(
        destination: args.destination,
        placeType: args.placeType,
        key: args.key,
      );
    },
  );
}

class PublicMapRouteArgs {
  const PublicMapRouteArgs({
    this.destination = 'overview',
    this.placeType,
    this.key,
  });

  final String destination;

  final String? placeType;

  final _i44.Key? key;

  @override
  String toString() {
    return 'PublicMapRouteArgs{destination: $destination, placeType: $placeType, key: $key}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! PublicMapRouteArgs) return false;
    return destination == other.destination &&
        placeType == other.placeType &&
        key == other.key;
  }

  @override
  int get hashCode => destination.hashCode ^ placeType.hashCode ^ key.hashCode;
}

/// generated route for
/// [_i25.ReceptionPage]
class ReceptionRoute extends _i42.PageRouteInfo<void> {
  const ReceptionRoute({List<_i42.PageRouteInfo>? children})
      : super(ReceptionRoute.name, initialChildren: children);

  static const String name = 'ReceptionRoute';

  static _i42.PageInfo page = _i42.PageInfo(
    name,
    builder: (data) {
      return const _i25.ReceptionPage();
    },
  );
}

/// generated route for
/// [_i26.ReservationsPage]
class ReservationsRoute extends _i42.PageRouteInfo<void> {
  const ReservationsRoute({List<_i42.PageRouteInfo>? children})
      : super(ReservationsRoute.name, initialChildren: children);

  static const String name = 'ReservationsRoute';

  static _i42.PageInfo page = _i42.PageInfo(
    name,
    builder: (data) {
      return const _i26.ReservationsPage();
    },
  );
}

/// generated route for
/// [_i27.ResetPasswordPage]
class ResetPasswordRoute extends _i42.PageRouteInfo<ResetPasswordRouteArgs> {
  ResetPasswordRoute({
    String? token,
    _i43.Key? key,
    List<_i42.PageRouteInfo>? children,
  }) : super(
          ResetPasswordRoute.name,
          args: ResetPasswordRouteArgs(token: token, key: key),
          rawQueryParams: {'token': token},
          initialChildren: children,
        );

  static const String name = 'ResetPasswordRoute';

  static _i42.PageInfo page = _i42.PageInfo(
    name,
    builder: (data) {
      final queryParams = data.queryParams;
      final args = data.argsAs<ResetPasswordRouteArgs>(
        orElse: () =>
            ResetPasswordRouteArgs(token: queryParams.optString('token')),
      );
      return _i27.ResetPasswordPage(token: args.token, key: args.key);
    },
  );
}

class ResetPasswordRouteArgs {
  const ResetPasswordRouteArgs({this.token, this.key});

  final String? token;

  final _i43.Key? key;

  @override
  String toString() {
    return 'ResetPasswordRouteArgs{token: $token, key: $key}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ResetPasswordRouteArgs) return false;
    return token == other.token && key == other.key;
  }

  @override
  int get hashCode => token.hashCode ^ key.hashCode;
}

/// generated route for
/// [_i28.ScanPage]
class ScanRoute extends _i42.PageRouteInfo<ScanRouteArgs> {
  ScanRoute({
    String? scanCode,
    _i44.Key? key,
    List<_i42.PageRouteInfo>? children,
  }) : super(
          ScanRoute.name,
          args: ScanRouteArgs(scanCode: scanCode, key: key),
          rawPathParams: {'scanCode': scanCode},
          initialChildren: children,
        );

  static const String name = 'ScanRoute';

  static _i42.PageInfo page = _i42.PageInfo(
    name,
    builder: (data) {
      final pathParams = data.inheritedPathParams;
      final args = data.argsAs<ScanRouteArgs>(
        orElse: () => ScanRouteArgs(scanCode: pathParams.optString('scanCode')),
      );
      return _i28.ScanPage(scanCode: args.scanCode, key: args.key);
    },
  );
}

class ScanRouteArgs {
  const ScanRouteArgs({this.scanCode, this.key});

  final String? scanCode;

  final _i44.Key? key;

  @override
  String toString() {
    return 'ScanRouteArgs{scanCode: $scanCode, key: $key}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ScanRouteArgs) return false;
    return scanCode == other.scanCode && key == other.key;
  }

  @override
  int get hashCode => scanCode.hashCode ^ key.hashCode;
}

/// generated route for
/// [_i29.ScheduleBasicPage]
class ScheduleBasicRoute extends _i42.PageRouteInfo<void> {
  const ScheduleBasicRoute({List<_i42.PageRouteInfo>? children})
      : super(ScheduleBasicRoute.name, initialChildren: children);

  static const String name = 'ScheduleBasicRoute';

  static _i42.PageInfo page = _i42.PageInfo(
    name,
    builder: (data) {
      return const _i29.ScheduleBasicPage();
    },
  );
}

/// generated route for
/// [_i30.ScheduleLightPage]
class ScheduleLightRoute extends _i42.PageRouteInfo<void> {
  const ScheduleLightRoute({List<_i42.PageRouteInfo>? children})
      : super(ScheduleLightRoute.name, initialChildren: children);

  static const String name = 'ScheduleLightRoute';

  static _i42.PageInfo page = _i42.PageInfo(
    name,
    builder: (data) {
      return const _i30.ScheduleLightPage();
    },
  );
}

/// generated route for
/// [_i31.ScheduleNavigationPage]
class ScheduleNavigationRoute extends _i42.PageRouteInfo<void> {
  const ScheduleNavigationRoute({List<_i42.PageRouteInfo>? children})
      : super(ScheduleNavigationRoute.name, initialChildren: children);

  static const String name = 'ScheduleNavigationRoute';

  static _i42.PageInfo page = _i42.PageInfo(
    name,
    builder: (data) {
      return const _i31.ScheduleNavigationPage();
    },
  );
}

/// generated route for
/// [_i32.SchedulePage]
class ScheduleRoute extends _i42.PageRouteInfo<void> {
  const ScheduleRoute({List<_i42.PageRouteInfo>? children})
      : super(ScheduleRoute.name, initialChildren: children);

  static const String name = 'ScheduleRoute';

  static _i42.PageInfo page = _i42.PageInfo(
    name,
    builder: (data) {
      return const _i32.SchedulePage();
    },
  );
}

/// generated route for
/// [_i33.SettingsPage]
class SettingsRoute extends _i42.PageRouteInfo<void> {
  const SettingsRoute({List<_i42.PageRouteInfo>? children})
      : super(SettingsRoute.name, initialChildren: children);

  static const String name = 'SettingsRoute';

  static _i42.PageInfo page = _i42.PageInfo(
    name,
    builder: (data) {
      return const _i33.SettingsPage();
    },
  );
}

/// generated route for
/// [_i34.SignupPage]
class SignupRoute extends _i42.PageRouteInfo<void> {
  const SignupRoute({List<_i42.PageRouteInfo>? children})
      : super(SignupRoute.name, initialChildren: children);

  static const String name = 'SignupRoute';

  static _i42.PageInfo page = _i42.PageInfo(
    name,
    builder: (data) {
      return const _i34.SignupPage();
    },
  );
}

/// generated route for
/// [_i35.SongbookPage]
class SongbookRoute extends _i42.PageRouteInfo<void> {
  const SongbookRoute({List<_i42.PageRouteInfo>? children})
      : super(SongbookRoute.name, initialChildren: children);

  static const String name = 'SongbookRoute';

  static _i42.PageInfo page = _i42.PageInfo(
    name,
    builder: (data) {
      return const _i35.SongbookPage();
    },
  );
}

/// generated route for
/// [_i36.TimetablePage]
class TimetableRoute extends _i42.PageRouteInfo<void> {
  const TimetableRoute({List<_i42.PageRouteInfo>? children})
      : super(TimetableRoute.name, initialChildren: children);

  static const String name = 'TimetableRoute';

  static _i42.PageInfo page = _i42.PageInfo(
    name,
    builder: (data) {
      return const _i36.TimetablePage();
    },
  );
}

/// generated route for
/// [_i37.TransferPage]
class TransferRoute extends _i42.PageRouteInfo<TransferRouteArgs> {
  TransferRoute({
    _i43.Key? key,
    String? access_token,
    String? refresh_token,
    String? redirect,
    List<_i42.PageRouteInfo>? children,
  }) : super(
          TransferRoute.name,
          args: TransferRouteArgs(
            key: key,
            access_token: access_token,
            refresh_token: refresh_token,
            redirect: redirect,
          ),
          rawQueryParams: {
            'access_token': access_token,
            'refresh_token': refresh_token,
            'redirect': redirect,
          },
          initialChildren: children,
        );

  static const String name = 'TransferRoute';

  static _i42.PageInfo page = _i42.PageInfo(
    name,
    builder: (data) {
      final queryParams = data.queryParams;
      final args = data.argsAs<TransferRouteArgs>(
        orElse: () => TransferRouteArgs(
          access_token: queryParams.optString('access_token'),
          refresh_token: queryParams.optString('refresh_token'),
          redirect: queryParams.optString('redirect'),
        ),
      );
      return _i37.TransferPage(
        key: args.key,
        access_token: args.access_token,
        refresh_token: args.refresh_token,
        redirect: args.redirect,
      );
    },
  );
}

class TransferRouteArgs {
  const TransferRouteArgs({
    this.key,
    this.access_token,
    this.refresh_token,
    this.redirect,
  });

  final _i43.Key? key;

  final String? access_token;

  final String? refresh_token;

  final String? redirect;

  @override
  String toString() {
    return 'TransferRouteArgs{key: $key, access_token: $access_token, refresh_token: $refresh_token, redirect: $redirect}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! TransferRouteArgs) return false;
    return key == other.key &&
        access_token == other.access_token &&
        refresh_token == other.refresh_token &&
        redirect == other.redirect;
  }

  @override
  int get hashCode =>
      key.hashCode ^
      access_token.hashCode ^
      refresh_token.hashCode ^
      redirect.hashCode;
}

/// generated route for
/// [_i38.UnitAdminPage]
class UnitAdminRoute extends _i42.PageRouteInfo<UnitAdminRouteArgs> {
  UnitAdminRoute({
    required int? id,
    _i43.Key? key,
    List<_i42.PageRouteInfo>? children,
  }) : super(
          UnitAdminRoute.name,
          args: UnitAdminRouteArgs(id: id, key: key),
          rawPathParams: {'id': id},
          initialChildren: children,
        );

  static const String name = 'UnitAdminRoute';

  static _i42.PageInfo page = _i42.PageInfo(
    name,
    builder: (data) {
      final pathParams = data.inheritedPathParams;
      final args = data.argsAs<UnitAdminRouteArgs>(
        orElse: () => UnitAdminRouteArgs(id: pathParams.optInt('id')),
      );
      return _i38.UnitAdminPage(id: args.id, key: args.key);
    },
  );
}

class UnitAdminRouteArgs {
  const UnitAdminRouteArgs({required this.id, this.key});

  final int? id;

  final _i43.Key? key;

  @override
  String toString() {
    return 'UnitAdminRouteArgs{id: $id, key: $key}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! UnitAdminRouteArgs) return false;
    return id == other.id && key == other.key;
  }

  @override
  int get hashCode => id.hashCode ^ key.hashCode;
}

/// generated route for
/// [_i39.UnitPage]
class UnitRoute extends _i42.PageRouteInfo<UnitRouteArgs> {
  UnitRoute({int? id, _i43.Key? key, List<_i42.PageRouteInfo>? children})
      : super(
          UnitRoute.name,
          args: UnitRouteArgs(id: id, key: key),
          rawPathParams: {'id': id},
          initialChildren: children,
        );

  static const String name = 'UnitRoute';

  static _i42.PageInfo page = _i42.PageInfo(
    name,
    builder: (data) {
      final pathParams = data.inheritedPathParams;
      final args = data.argsAs<UnitRouteArgs>(
        orElse: () => UnitRouteArgs(id: pathParams.optInt('id')),
      );
      return _i39.UnitPage(id: args.id, key: args.key);
    },
  );
}

class UnitRouteArgs {
  const UnitRouteArgs({this.id, this.key});

  final int? id;

  final _i43.Key? key;

  @override
  String toString() {
    return 'UnitRouteArgs{id: $id, key: $key}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! UnitRouteArgs) return false;
    return id == other.id && key == other.key;
  }

  @override
  int get hashCode => id.hashCode ^ key.hashCode;
}

/// generated route for
/// [_i40.UserPage]
class UserRoute extends _i42.PageRouteInfo<void> {
  const UserRoute({List<_i42.PageRouteInfo>? children})
      : super(UserRoute.name, initialChildren: children);

  static const String name = 'UserRoute';

  static _i42.PageInfo page = _i42.PageInfo(
    name,
    builder: (data) {
      return const _i40.UserPage();
    },
  );
}

/// generated route for
/// [_i41.UserStayPage]
class UserStayRoute extends _i42.PageRouteInfo<void> {
  const UserStayRoute({List<_i42.PageRouteInfo>? children})
      : super(UserStayRoute.name, initialChildren: children);

  static const String name = 'UserStayRoute';

  static _i42.PageInfo page = _i42.PageInfo(
    name,
    builder: (data) {
      return const _i41.UserStayPage();
    },
  );
}
