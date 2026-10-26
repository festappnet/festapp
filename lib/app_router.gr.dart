// dart format width=80
// GENERATED CODE - DO NOT MODIFY BY HAND

// **************************************************************************
// AutoRouterGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'dart:async' as _i79;

import 'package:auto_route/auto_route.dart' as _i77;
import 'package:festapp_core/eshop.dart' as _i80;
import 'package:flutter/foundation.dart' as _i81;
import 'package:material_ui/material_ui.dart' as _i78;
import 'package:fstapp/components/activities/volunteers_section_page.dart'
    as _i76;
import 'package:fstapp/components/app_management/install_page.dart' as _i24;
import 'package:fstapp/components/app_management/settings_page.dart' as _i58;
import 'package:fstapp/components/bank_accounts/views/bank_account_navigation_page.dart'
    as _i3;
import 'package:fstapp/components/bank_accounts/views/bank_account_settings_screen.dart'
    as _i2;
import 'package:fstapp/components/blueprint/views/blueprint_section_page.dart'
    as _i4;
import 'package:fstapp/components/cleaning/cleaning_page.dart' as _i7;
import 'package:fstapp/components/client_changes/changes_section_page.dart'
    as _i5;
import 'package:fstapp/components/email_templates/views/email_templates_section_page.dart'
    as _i9;
import 'package:fstapp/components/eshop/tickets_section_page.dart' as _i66;
import 'package:fstapp/components/eshop/views/orders_email_history_page.dart'
    as _i39;
import 'package:fstapp/components/eshop/views/orders_navigation_page.dart'
    as _i40;
import 'package:fstapp/components/eshop/views/orders_tab.dart' as _i38;
import 'package:fstapp/components/eshop/views/products_section_page.dart'
    as _i46;
import 'package:fstapp/components/eshop/views/report_section_page.dart' as _i48;
import 'package:fstapp/components/eshop/views/ticket_batches_page.dart' as _i65;
import 'package:fstapp/components/forms/models/form_bundle.dart' as _i82;
import 'package:fstapp/components/forms/views/form_page.dart' as _i14;
import 'package:fstapp/components/forms/views/form_tab.dart' as _i13;
import 'package:fstapp/components/forms/views/forms_navigation_page.dart'
    as _i15;
import 'package:fstapp/components/forms/views/forms_tab.dart' as _i16;
import 'package:fstapp/components/forms/views/reservation_page.dart' as _i49;
import 'package:fstapp/components/groups/game_navigation_page.dart' as _i18;
import 'package:fstapp/components/groups/game_tab.dart' as _i17;
import 'package:fstapp/components/groups/groups_section_page.dart' as _i20;
import 'package:fstapp/components/information/game/game_page.dart' as _i19;
import 'package:fstapp/components/information/info_page.dart' as _i21;
import 'package:fstapp/components/information/information_navigation_page.dart'
    as _i23;
import 'package:fstapp/components/information/information_tab.dart' as _i22;
import 'package:fstapp/components/information/song/song_page.dart' as _i61;
import 'package:fstapp/components/inventory/models/inventory_pools_list_bundle.dart'
    as _i83;
import 'package:fstapp/components/inventory/views/inventory_pool_detail_view.dart'
    as _i25;
import 'package:fstapp/components/inventory/views/inventory_pools_navigation_page.dart'
    as _i26;
import 'package:fstapp/components/inventory/views/inventory_pools_tab.dart'
    as _i27;
import 'package:fstapp/components/inventory/views/user_stay_page.dart' as _i74;
import 'package:fstapp/components/map/map_page.dart' as _i30;
import 'package:fstapp/components/map/places_navigation_page.dart' as _i45;
import 'package:fstapp/components/map/places_tab.dart' as _i44;
import 'package:fstapp/components/mcp/mcp_callback_window.dart' as _i84;
import 'package:fstapp/components/mcp/mcp_connection_page.dart' as _i31;
import 'package:fstapp/components/navigation/routed_tab_scaffold.dart' as _i33;
import 'package:fstapp/components/navigation/unit_administration_access.dart'
    as _i85;
import 'package:fstapp/components/news/news_form_page.dart' as _i34;
import 'package:fstapp/components/news/news_page.dart' as _i35;
import 'package:fstapp/components/occasion/admin_page.dart' as _i1;
import 'package:fstapp/components/occasion/occasion_home_page.dart' as _i36;
import 'package:fstapp/components/occasion_services/service_section_page.dart'
    as _i57;
import 'package:fstapp/components/occasion_settings/settings_section_page.dart'
    as _i59;
import 'package:fstapp/components/organization/views/organization_edit_page.dart'
    as _i41;
import 'package:fstapp/components/organization/views/organization_edit_redirect_page.dart'
    as _i42;
import 'package:fstapp/components/reception/login_qr_scanner_page.dart' as _i29;
import 'package:fstapp/components/reception/reception_page.dart' as _i47;
import 'package:fstapp/components/scan/check_page.dart' as _i6;
import 'package:fstapp/components/scan/scan_page.dart' as _i51;
import 'package:fstapp/components/schedule/event_edit_page.dart' as _i10;
import 'package:fstapp/components/schedule/event_page.dart' as _i11;
import 'package:fstapp/components/schedule/my_schedule_page.dart' as _i32;
import 'package:fstapp/components/schedule/schedule_basic_page.dart' as _i52;
import 'package:fstapp/components/schedule/schedule_light_page.dart' as _i54;
import 'package:fstapp/components/schedule/schedule_navigation_screen.dart'
    as _i55;
import 'package:fstapp/components/schedule/schedule_page.dart' as _i56;
import 'package:fstapp/components/schedule/schedule_tab.dart' as _i53;
import 'package:fstapp/components/schedule/timetable_page.dart' as _i67;
import 'package:fstapp/components/speakers/admin/speakers_section_page.dart'
    as _i62;
import 'package:fstapp/components/speakers/counseling_page.dart' as _i8;
import 'package:fstapp/components/stripe_payments/stripe_connect_callback_page.dart'
    as _i63;
import 'package:fstapp/components/stripe_payments/stripe_payment_page.dart'
    as _i64;
import 'package:fstapp/components/stripe_payments/unit_card_payments_page.dart'
    as _i70;
import 'package:fstapp/components/unit/verification/unit_legal_profile_screen.dart'
    as _i71;
import 'package:fstapp/components/unit/views/organization_page.dart' as _i43;
import 'package:fstapp/components/unit/views/unit_admin_page.dart' as _i69;
import 'package:fstapp/components/unit/views/unit_page.dart' as _i72;
import 'package:fstapp/components/users/views/forgot_password_page.dart'
    as _i12;
import 'package:fstapp/components/users/views/login_page.dart' as _i28;
import 'package:fstapp/components/users/views/occasion_team_invitation_page.dart'
    as _i37;
import 'package:fstapp/components/users/views/reset_password_page.dart' as _i50;
import 'package:fstapp/components/users/views/signup_page.dart' as _i60;
import 'package:fstapp/components/users/views/transfer_page.dart' as _i68;
import 'package:fstapp/components/users/views/user_page.dart' as _i73;
import 'package:fstapp/components/users/views/users_section_page.dart' as _i75;

/// generated route for
/// [_i1.AdminPage]
class AdminRoute extends _i77.PageRouteInfo<void> {
  const AdminRoute({List<_i77.PageRouteInfo>? children})
      : super(AdminRoute.name, initialChildren: children);

  static const String name = 'AdminRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i1.AdminPage();
    },
  );
}

/// generated route for
/// [_i1.AdminTabsPage]
class AdminTabsRoute extends _i77.PageRouteInfo<void> {
  const AdminTabsRoute({List<_i77.PageRouteInfo>? children})
      : super(AdminTabsRoute.name, initialChildren: children);

  static const String name = 'AdminTabsRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i1.AdminTabsPage();
    },
  );
}

/// generated route for
/// [_i2.BankAccountConnectionPage]
class BankAccountConnectionRoute extends _i77.PageRouteInfo<void> {
  const BankAccountConnectionRoute({List<_i77.PageRouteInfo>? children})
      : super(BankAccountConnectionRoute.name, initialChildren: children);

  static const String name = 'BankAccountConnectionRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i2.BankAccountConnectionPage();
    },
  );
}

/// generated route for
/// [_i3.BankAccountConnectionSettingsPage]
class BankAccountConnectionSettingsRoute
    extends _i77.PageRouteInfo<BankAccountConnectionSettingsRouteArgs> {
  BankAccountConnectionSettingsRoute({
    _i78.Key? key,
    required String accountId,
    List<_i77.PageRouteInfo>? children,
  }) : super(
          BankAccountConnectionSettingsRoute.name,
          args: BankAccountConnectionSettingsRouteArgs(
            key: key,
            accountId: accountId,
          ),
          rawPathParams: {'accountId': accountId},
          initialChildren: children,
        );

  static const String name = 'BankAccountConnectionSettingsRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      final pathParams = data.inheritedPathParams;
      final args = data.argsAs<BankAccountConnectionSettingsRouteArgs>(
        orElse: () => BankAccountConnectionSettingsRouteArgs(
          accountId: pathParams.getString('accountId'),
        ),
      );
      return _i3.BankAccountConnectionSettingsPage(
        key: args.key,
        accountId: args.accountId,
      );
    },
  );
}

class BankAccountConnectionSettingsRouteArgs {
  const BankAccountConnectionSettingsRouteArgs({
    this.key,
    required this.accountId,
  });

  final _i78.Key? key;

  final String accountId;

  @override
  String toString() {
    return 'BankAccountConnectionSettingsRouteArgs{key: $key, accountId: $accountId}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! BankAccountConnectionSettingsRouteArgs) return false;
    return key == other.key && accountId == other.accountId;
  }

  @override
  int get hashCode => key.hashCode ^ accountId.hashCode;
}

/// generated route for
/// [_i3.BankAccountDetailPage]
class BankAccountDetailRoute
    extends _i77.PageRouteInfo<BankAccountDetailRouteArgs> {
  BankAccountDetailRoute({
    _i78.Key? key,
    required String accountId,
    _i79.Future<List<_i80.BankAccountModel>> Function(int)? loadAccounts,
    List<_i77.PageRouteInfo>? children,
  }) : super(
          BankAccountDetailRoute.name,
          args: BankAccountDetailRouteArgs(
            key: key,
            accountId: accountId,
            loadAccounts: loadAccounts,
          ),
          rawPathParams: {'accountId': accountId},
          initialChildren: children,
        );

  static const String name = 'BankAccountDetailRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      final pathParams = data.inheritedPathParams;
      final args = data.argsAs<BankAccountDetailRouteArgs>(
        orElse: () => BankAccountDetailRouteArgs(
          accountId: pathParams.getString('accountId'),
        ),
      );
      return _i3.BankAccountDetailPage(
        key: args.key,
        accountId: args.accountId,
        loadAccounts: args.loadAccounts,
      );
    },
  );
}

class BankAccountDetailRouteArgs {
  const BankAccountDetailRouteArgs({
    this.key,
    required this.accountId,
    this.loadAccounts,
  });

  final _i78.Key? key;

  final String accountId;

  final _i79.Future<List<_i80.BankAccountModel>> Function(int)? loadAccounts;

  @override
  String toString() {
    return 'BankAccountDetailRouteArgs{key: $key, accountId: $accountId, loadAccounts: $loadAccounts}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! BankAccountDetailRouteArgs) return false;
    return key == other.key && accountId == other.accountId;
  }

  @override
  int get hashCode => key.hashCode ^ accountId.hashCode;
}

/// generated route for
/// [_i2.BankAccountGeneralPage]
class BankAccountGeneralRoute extends _i77.PageRouteInfo<void> {
  const BankAccountGeneralRoute({List<_i77.PageRouteInfo>? children})
      : super(BankAccountGeneralRoute.name, initialChildren: children);

  static const String name = 'BankAccountGeneralRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i2.BankAccountGeneralPage();
    },
  );
}

/// generated route for
/// [_i2.BankAccountTabsPage]
class BankAccountTabsRoute extends _i77.PageRouteInfo<void> {
  const BankAccountTabsRoute({List<_i77.PageRouteInfo>? children})
      : super(BankAccountTabsRoute.name, initialChildren: children);

  static const String name = 'BankAccountTabsRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i2.BankAccountTabsPage();
    },
  );
}

/// generated route for
/// [_i2.BankAccountUsersPage]
class BankAccountUsersRoute extends _i77.PageRouteInfo<void> {
  const BankAccountUsersRoute({List<_i77.PageRouteInfo>? children})
      : super(BankAccountUsersRoute.name, initialChildren: children);

  static const String name = 'BankAccountUsersRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i2.BankAccountUsersPage();
    },
  );
}

/// generated route for
/// [_i4.BlueprintSectionPage]
class BlueprintSectionRoute extends _i77.PageRouteInfo<void> {
  const BlueprintSectionRoute({List<_i77.PageRouteInfo>? children})
      : super(BlueprintSectionRoute.name, initialChildren: children);

  static const String name = 'BlueprintSectionRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i4.BlueprintSectionPage();
    },
  );
}

/// generated route for
/// [_i5.ChangesSectionPage]
class ChangesSectionRoute extends _i77.PageRouteInfo<void> {
  const ChangesSectionRoute({List<_i77.PageRouteInfo>? children})
      : super(ChangesSectionRoute.name, initialChildren: children);

  static const String name = 'ChangesSectionRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i5.ChangesSectionPage();
    },
  );
}

/// generated route for
/// [_i6.CheckPage]
class CheckRoute extends _i77.PageRouteInfo<CheckRouteArgs> {
  CheckRoute({
    required int id,
    _i81.Key? key,
    List<_i77.PageRouteInfo>? children,
  }) : super(
          CheckRoute.name,
          args: CheckRouteArgs(id: id, key: key),
          rawPathParams: {'id': id},
          initialChildren: children,
        );

  static const String name = 'CheckRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      final pathParams = data.inheritedPathParams;
      final args = data.argsAs<CheckRouteArgs>(
        orElse: () => CheckRouteArgs(id: pathParams.getInt('id')),
      );
      return _i6.CheckPage(id: args.id, key: args.key);
    },
  );
}

class CheckRouteArgs {
  const CheckRouteArgs({required this.id, this.key});

  final int id;

  final _i81.Key? key;

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
/// [_i7.CleaningPage]
class CleaningRoute extends _i77.PageRouteInfo<CleaningRouteArgs> {
  CleaningRoute({int? id, _i81.Key? key, List<_i77.PageRouteInfo>? children})
      : super(
          CleaningRoute.name,
          args: CleaningRouteArgs(id: id, key: key),
          rawPathParams: {'id': id},
          initialChildren: children,
        );

  static const String name = 'CleaningRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      final pathParams = data.inheritedPathParams;
      final args = data.argsAs<CleaningRouteArgs>(
        orElse: () => CleaningRouteArgs(id: pathParams.optInt('id')),
      );
      return _i7.CleaningPage(id: args.id, key: args.key);
    },
  );
}

class CleaningRouteArgs {
  const CleaningRouteArgs({this.id, this.key});

  final int? id;

  final _i81.Key? key;

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
/// [_i8.CounselingPage]
class CounselingRoute extends _i77.PageRouteInfo<void> {
  const CounselingRoute({List<_i77.PageRouteInfo>? children})
      : super(CounselingRoute.name, initialChildren: children);

  static const String name = 'CounselingRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i8.CounselingPage();
    },
  );
}

/// generated route for
/// [_i9.EmailTemplatesSectionPage]
class EmailTemplatesSectionRoute extends _i77.PageRouteInfo<void> {
  const EmailTemplatesSectionRoute({List<_i77.PageRouteInfo>? children})
      : super(EmailTemplatesSectionRoute.name, initialChildren: children);

  static const String name = 'EmailTemplatesSectionRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i9.EmailTemplatesSectionPage();
    },
  );
}

/// generated route for
/// [_i10.EventEditPage]
class EventEditRoute extends _i77.PageRouteInfo<EventEditRouteArgs> {
  EventEditRoute({_i78.Key? key, int? id, List<_i77.PageRouteInfo>? children})
      : super(
          EventEditRoute.name,
          args: EventEditRouteArgs(key: key, id: id),
          rawPathParams: {'id': id},
          initialChildren: children,
        );

  static const String name = 'EventEditRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      final pathParams = data.inheritedPathParams;
      final args = data.argsAs<EventEditRouteArgs>(
        orElse: () => EventEditRouteArgs(id: pathParams.optInt('id')),
      );
      return _i10.EventEditPage(key: args.key, id: args.id);
    },
  );
}

class EventEditRouteArgs {
  const EventEditRouteArgs({this.key, this.id});

  final _i78.Key? key;

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
/// [_i11.EventPage]
class EventRoute extends _i77.PageRouteInfo<EventRouteArgs> {
  EventRoute({int? id, _i78.Key? key, List<_i77.PageRouteInfo>? children})
      : super(
          EventRoute.name,
          args: EventRouteArgs(id: id, key: key),
          rawPathParams: {'id': id},
          initialChildren: children,
        );

  static const String name = 'EventRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      final pathParams = data.inheritedPathParams;
      final args = data.argsAs<EventRouteArgs>(
        orElse: () => EventRouteArgs(id: pathParams.optInt('id')),
      );
      return _i11.EventPage(id: args.id, key: args.key);
    },
  );
}

class EventRouteArgs {
  const EventRouteArgs({this.id, this.key});

  final int? id;

  final _i78.Key? key;

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
/// [_i12.ForgotPasswordPage]
class ForgotPasswordRoute extends _i77.PageRouteInfo<void> {
  const ForgotPasswordRoute({List<_i77.PageRouteInfo>? children})
      : super(ForgotPasswordRoute.name, initialChildren: children);

  static const String name = 'ForgotPasswordRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i12.ForgotPasswordPage();
    },
  );
}

/// generated route for
/// [_i13.FormDesignPage]
class FormDesignRoute extends _i77.PageRouteInfo<void> {
  const FormDesignRoute({List<_i77.PageRouteInfo>? children})
      : super(FormDesignRoute.name, initialChildren: children);

  static const String name = 'FormDesignRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i13.FormDesignPage();
    },
  );
}

/// generated route for
/// [_i13.FormDetailPage]
class FormDetailRoute extends _i77.PageRouteInfo<FormDetailRouteArgs> {
  FormDetailRoute({
    _i78.Key? key,
    required String formLink,
    _i79.Future<List<_i82.FormBundle>> Function(String)? loadForms,
    List<_i77.PageRouteInfo>? children,
  }) : super(
          FormDetailRoute.name,
          args: FormDetailRouteArgs(
            key: key,
            formLink: formLink,
            loadForms: loadForms,
          ),
          rawPathParams: {'formLink': formLink},
          initialChildren: children,
        );

  static const String name = 'FormDetailRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      final pathParams = data.inheritedPathParams;
      final args = data.argsAs<FormDetailRouteArgs>(
        orElse: () =>
            FormDetailRouteArgs(formLink: pathParams.getString('formLink')),
      );
      return _i13.FormDetailPage(
        key: args.key,
        formLink: args.formLink,
        loadForms: args.loadForms,
      );
    },
  );
}

class FormDetailRouteArgs {
  const FormDetailRouteArgs({this.key, required this.formLink, this.loadForms});

  final _i78.Key? key;

  final String formLink;

  final _i79.Future<List<_i82.FormBundle>> Function(String)? loadForms;

  @override
  String toString() {
    return 'FormDetailRouteArgs{key: $key, formLink: $formLink, loadForms: $loadForms}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! FormDetailRouteArgs) return false;
    return key == other.key && formLink == other.formLink;
  }

  @override
  int get hashCode => key.hashCode ^ formLink.hashCode;
}

/// generated route for
/// [_i13.FormEditorPage]
class FormEditorRoute extends _i77.PageRouteInfo<void> {
  const FormEditorRoute({List<_i77.PageRouteInfo>? children})
      : super(FormEditorRoute.name, initialChildren: children);

  static const String name = 'FormEditorRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i13.FormEditorPage();
    },
  );
}

/// generated route for
/// [_i14.FormPage]
class FormRoute extends _i77.PageRouteInfo<FormRouteArgs> {
  FormRoute({
    _i78.Key? key,
    String? formLink,
    String? offerId,
    int? waitlistOrderId,
    List<_i77.PageRouteInfo>? children,
  }) : super(
          FormRoute.name,
          args: FormRouteArgs(
            key: key,
            formLink: formLink,
            offerId: offerId,
            waitlistOrderId: waitlistOrderId,
          ),
          rawPathParams: {'formLink': formLink},
          initialChildren: children,
        );

  static const String name = 'FormRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      final pathParams = data.inheritedPathParams;
      final args = data.argsAs<FormRouteArgs>(
        orElse: () => FormRouteArgs(formLink: pathParams.optString('formLink')),
      );
      return _i14.FormPage(
        key: args.key,
        formLink: args.formLink,
        offerId: args.offerId,
        waitlistOrderId: args.waitlistOrderId,
      );
    },
  );
}

class FormRouteArgs {
  const FormRouteArgs({
    this.key,
    this.formLink,
    this.offerId,
    this.waitlistOrderId,
  });

  final _i78.Key? key;

  final String? formLink;

  final String? offerId;

  final int? waitlistOrderId;

  @override
  String toString() {
    return 'FormRouteArgs{key: $key, formLink: $formLink, offerId: $offerId, waitlistOrderId: $waitlistOrderId}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! FormRouteArgs) return false;
    return key == other.key &&
        formLink == other.formLink &&
        offerId == other.offerId &&
        waitlistOrderId == other.waitlistOrderId;
  }

  @override
  int get hashCode =>
      key.hashCode ^
      formLink.hashCode ^
      offerId.hashCode ^
      waitlistOrderId.hashCode;
}

/// generated route for
/// [_i13.FormResponsesPage]
class FormResponsesRoute extends _i77.PageRouteInfo<void> {
  const FormResponsesRoute({List<_i77.PageRouteInfo>? children})
      : super(FormResponsesRoute.name, initialChildren: children);

  static const String name = 'FormResponsesRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i13.FormResponsesPage();
    },
  );
}

/// generated route for
/// [_i13.FormSettingsPage]
class FormSettingsRoute extends _i77.PageRouteInfo<void> {
  const FormSettingsRoute({List<_i77.PageRouteInfo>? children})
      : super(FormSettingsRoute.name, initialChildren: children);

  static const String name = 'FormSettingsRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i13.FormSettingsPage();
    },
  );
}

/// generated route for
/// [_i13.FormTab]
class FormTabsRoute extends _i77.PageRouteInfo<void> {
  const FormTabsRoute({List<_i77.PageRouteInfo>? children})
      : super(FormTabsRoute.name, initialChildren: children);

  static const String name = 'FormTabsRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i13.FormTab();
    },
  );
}

/// generated route for
/// [_i15.FormsNavigationPage]
class FormsNavigationRoute extends _i77.PageRouteInfo<void> {
  const FormsNavigationRoute({List<_i77.PageRouteInfo>? children})
      : super(FormsNavigationRoute.name, initialChildren: children);

  static const String name = 'FormsNavigationRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i15.FormsNavigationPage();
    },
  );
}

/// generated route for
/// [_i16.FormsTab]
class FormsListRoute extends _i77.PageRouteInfo<void> {
  const FormsListRoute({List<_i77.PageRouteInfo>? children})
      : super(FormsListRoute.name, initialChildren: children);

  static const String name = 'FormsListRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i16.FormsTab();
    },
  );
}

/// generated route for
/// [_i17.GameCheckpointsPage]
class GameCheckpointsRoute extends _i77.PageRouteInfo<void> {
  const GameCheckpointsRoute({List<_i77.PageRouteInfo>? children})
      : super(GameCheckpointsRoute.name, initialChildren: children);

  static const String name = 'GameCheckpointsRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i17.GameCheckpointsPage();
    },
  );
}

/// generated route for
/// [_i17.GameGroupsPage]
class GameGroupsRoute extends _i77.PageRouteInfo<void> {
  const GameGroupsRoute({List<_i77.PageRouteInfo>? children})
      : super(GameGroupsRoute.name, initialChildren: children);

  static const String name = 'GameGroupsRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i17.GameGroupsPage();
    },
  );
}

/// generated route for
/// [_i18.GameNavigationPage]
class GameNavigationRoute extends _i77.PageRouteInfo<void> {
  const GameNavigationRoute({List<_i77.PageRouteInfo>? children})
      : super(GameNavigationRoute.name, initialChildren: children);

  static const String name = 'GameNavigationRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i18.GameNavigationPage();
    },
  );
}

/// generated route for
/// [_i19.GamePage]
class GameRoute extends _i77.PageRouteInfo<void> {
  const GameRoute({List<_i77.PageRouteInfo>? children})
      : super(GameRoute.name, initialChildren: children);

  static const String name = 'GameRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i19.GamePage();
    },
  );
}

/// generated route for
/// [_i17.GameSettingsPage]
class GameSettingsRoute extends _i77.PageRouteInfo<void> {
  const GameSettingsRoute({List<_i77.PageRouteInfo>? children})
      : super(GameSettingsRoute.name, initialChildren: children);

  static const String name = 'GameSettingsRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i17.GameSettingsPage();
    },
  );
}

/// generated route for
/// [_i17.GameTab]
class GameTabsRoute extends _i77.PageRouteInfo<void> {
  const GameTabsRoute({List<_i77.PageRouteInfo>? children})
      : super(GameTabsRoute.name, initialChildren: children);

  static const String name = 'GameTabsRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i17.GameTab();
    },
  );
}

/// generated route for
/// [_i20.GroupsSectionPage]
class GroupsSectionRoute extends _i77.PageRouteInfo<void> {
  const GroupsSectionRoute({List<_i77.PageRouteInfo>? children})
      : super(GroupsSectionRoute.name, initialChildren: children);

  static const String name = 'GroupsSectionRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i20.GroupsSectionPage();
    },
  );
}

/// generated route for
/// [_i21.InfoPage]
class InfoRoute extends _i77.PageRouteInfo<InfoRouteArgs> {
  InfoRoute({int? id, _i81.Key? key, List<_i77.PageRouteInfo>? children})
      : super(
          InfoRoute.name,
          args: InfoRouteArgs(id: id, key: key),
          rawPathParams: {'id': id},
          initialChildren: children,
        );

  static const String name = 'InfoRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      final pathParams = data.inheritedPathParams;
      final args = data.argsAs<InfoRouteArgs>(
        orElse: () => InfoRouteArgs(id: pathParams.optInt('id')),
      );
      return _i21.InfoPage(id: args.id, key: args.key);
    },
  );
}

class InfoRouteArgs {
  const InfoRouteArgs({this.id, this.key});

  final int? id;

  final _i81.Key? key;

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
/// [_i22.InformationInformationPage]
class InformationInformationRoute extends _i77.PageRouteInfo<void> {
  const InformationInformationRoute({List<_i77.PageRouteInfo>? children})
      : super(InformationInformationRoute.name, initialChildren: children);

  static const String name = 'InformationInformationRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i22.InformationInformationPage();
    },
  );
}

/// generated route for
/// [_i23.InformationNavigationPage]
class InformationNavigationRoute extends _i77.PageRouteInfo<void> {
  const InformationNavigationRoute({List<_i77.PageRouteInfo>? children})
      : super(InformationNavigationRoute.name, initialChildren: children);

  static const String name = 'InformationNavigationRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i23.InformationNavigationPage();
    },
  );
}

/// generated route for
/// [_i22.InformationSongbookPage]
class InformationSongbookRoute extends _i77.PageRouteInfo<void> {
  const InformationSongbookRoute({List<_i77.PageRouteInfo>? children})
      : super(InformationSongbookRoute.name, initialChildren: children);

  static const String name = 'InformationSongbookRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i22.InformationSongbookPage();
    },
  );
}

/// generated route for
/// [_i22.InformationTab]
class InformationTabsRoute extends _i77.PageRouteInfo<void> {
  const InformationTabsRoute({List<_i77.PageRouteInfo>? children})
      : super(InformationTabsRoute.name, initialChildren: children);

  static const String name = 'InformationTabsRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i22.InformationTab();
    },
  );
}

/// generated route for
/// [_i24.InstallPage]
class InstallRoute extends _i77.PageRouteInfo<void> {
  const InstallRoute({List<_i77.PageRouteInfo>? children})
      : super(InstallRoute.name, initialChildren: children);

  static const String name = 'InstallRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i24.InstallPage();
    },
  );
}

/// generated route for
/// [_i25.InventoryPoolDetailPage]
class InventoryPoolDetailRoute
    extends _i77.PageRouteInfo<InventoryPoolDetailRouteArgs> {
  InventoryPoolDetailRoute({
    _i78.Key? key,
    required String poolId,
    _i79.Future<_i83.InventoryPoolsListBundle> Function(String)? loadPools,
    List<_i77.PageRouteInfo>? children,
  }) : super(
          InventoryPoolDetailRoute.name,
          args: InventoryPoolDetailRouteArgs(
            key: key,
            poolId: poolId,
            loadPools: loadPools,
          ),
          rawPathParams: {'poolId': poolId},
          initialChildren: children,
        );

  static const String name = 'InventoryPoolDetailRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      final pathParams = data.inheritedPathParams;
      final args = data.argsAs<InventoryPoolDetailRouteArgs>(
        orElse: () => InventoryPoolDetailRouteArgs(
          poolId: pathParams.getString('poolId'),
        ),
      );
      return _i25.InventoryPoolDetailPage(
        key: args.key,
        poolId: args.poolId,
        loadPools: args.loadPools,
      );
    },
  );
}

class InventoryPoolDetailRouteArgs {
  const InventoryPoolDetailRouteArgs({
    this.key,
    required this.poolId,
    this.loadPools,
  });

  final _i78.Key? key;

  final String poolId;

  final _i79.Future<_i83.InventoryPoolsListBundle> Function(String)? loadPools;

  @override
  String toString() {
    return 'InventoryPoolDetailRouteArgs{key: $key, poolId: $poolId, loadPools: $loadPools}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! InventoryPoolDetailRouteArgs) return false;
    return key == other.key && poolId == other.poolId;
  }

  @override
  int get hashCode => key.hashCode ^ poolId.hashCode;
}

/// generated route for
/// [_i25.InventoryPoolDetailView]
class InventoryPoolTabsRoute extends _i77.PageRouteInfo<void> {
  const InventoryPoolTabsRoute({List<_i77.PageRouteInfo>? children})
      : super(InventoryPoolTabsRoute.name, initialChildren: children);

  static const String name = 'InventoryPoolTabsRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i25.InventoryPoolDetailView();
    },
  );
}

/// generated route for
/// [_i25.InventoryPoolOccupancyPage]
class InventoryPoolOccupancyRoute extends _i77.PageRouteInfo<void> {
  const InventoryPoolOccupancyRoute({List<_i77.PageRouteInfo>? children})
      : super(InventoryPoolOccupancyRoute.name, initialChildren: children);

  static const String name = 'InventoryPoolOccupancyRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i25.InventoryPoolOccupancyPage();
    },
  );
}

/// generated route for
/// [_i25.InventoryPoolRoomsPage]
class InventoryPoolRoomsRoute extends _i77.PageRouteInfo<void> {
  const InventoryPoolRoomsRoute({List<_i77.PageRouteInfo>? children})
      : super(InventoryPoolRoomsRoute.name, initialChildren: children);

  static const String name = 'InventoryPoolRoomsRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i25.InventoryPoolRoomsPage();
    },
  );
}

/// generated route for
/// [_i25.InventoryPoolSettingsPage]
class InventoryPoolSettingsRoute extends _i77.PageRouteInfo<void> {
  const InventoryPoolSettingsRoute({List<_i77.PageRouteInfo>? children})
      : super(InventoryPoolSettingsRoute.name, initialChildren: children);

  static const String name = 'InventoryPoolSettingsRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i25.InventoryPoolSettingsPage();
    },
  );
}

/// generated route for
/// [_i26.InventoryPoolsNavigationPage]
class InventoryPoolsNavigationRoute extends _i77.PageRouteInfo<void> {
  const InventoryPoolsNavigationRoute({List<_i77.PageRouteInfo>? children})
      : super(InventoryPoolsNavigationRoute.name, initialChildren: children);

  static const String name = 'InventoryPoolsNavigationRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i26.InventoryPoolsNavigationPage();
    },
  );
}

/// generated route for
/// [_i27.InventoryPoolsTab]
class InventoryPoolsListRoute
    extends _i77.PageRouteInfo<InventoryPoolsListRouteArgs> {
  InventoryPoolsListRoute({
    _i78.Key? key,
    _i79.Future<_i83.InventoryPoolsListBundle> Function(String)? loadPools,
    List<_i77.PageRouteInfo>? children,
  }) : super(
          InventoryPoolsListRoute.name,
          args: InventoryPoolsListRouteArgs(key: key, loadPools: loadPools),
          initialChildren: children,
        );

  static const String name = 'InventoryPoolsListRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<InventoryPoolsListRouteArgs>(
        orElse: () => const InventoryPoolsListRouteArgs(),
      );
      return _i27.InventoryPoolsTab(key: args.key, loadPools: args.loadPools);
    },
  );
}

class InventoryPoolsListRouteArgs {
  const InventoryPoolsListRouteArgs({this.key, this.loadPools});

  final _i78.Key? key;

  final _i79.Future<_i83.InventoryPoolsListBundle> Function(String)? loadPools;

  @override
  String toString() {
    return 'InventoryPoolsListRouteArgs{key: $key, loadPools: $loadPools}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! InventoryPoolsListRouteArgs) return false;
    return key == other.key;
  }

  @override
  int get hashCode => key.hashCode;
}

/// generated route for
/// [_i28.LoginPage]
class LoginRoute extends _i77.PageRouteInfo<LoginRouteArgs> {
  LoginRoute({
    _i78.Key? key,
    String? redirect,
    List<_i77.PageRouteInfo>? children,
  }) : super(
          LoginRoute.name,
          args: LoginRouteArgs(key: key, redirect: redirect),
          rawQueryParams: {'redirect': redirect},
          initialChildren: children,
        );

  static const String name = 'LoginRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      final queryParams = data.queryParams;
      final args = data.argsAs<LoginRouteArgs>(
        orElse: () =>
            LoginRouteArgs(redirect: queryParams.optString('redirect')),
      );
      return _i28.LoginPage(key: args.key, redirect: args.redirect);
    },
  );
}

class LoginRouteArgs {
  const LoginRouteArgs({this.key, this.redirect});

  final _i78.Key? key;

  final String? redirect;

  @override
  String toString() {
    return 'LoginRouteArgs{key: $key, redirect: $redirect}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! LoginRouteArgs) return false;
    return key == other.key && redirect == other.redirect;
  }

  @override
  int get hashCode => key.hashCode ^ redirect.hashCode;
}

/// generated route for
/// [_i29.LoginQrScannerPage]
class LoginQrScannerRoute extends _i77.PageRouteInfo<void> {
  const LoginQrScannerRoute({List<_i77.PageRouteInfo>? children})
      : super(LoginQrScannerRoute.name, initialChildren: children);

  static const String name = 'LoginQrScannerRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i29.LoginQrScannerPage();
    },
  );
}

/// generated route for
/// [_i30.MapEditorPage]
class MapEditorRoute extends _i77.PageRouteInfo<MapEditorRouteArgs> {
  MapEditorRoute({
    required _i30.MapEditorMode mode,
    _i81.Key? key,
    List<_i77.PageRouteInfo>? children,
  }) : super(
          MapEditorRoute.name,
          args: MapEditorRouteArgs(mode: mode, key: key),
          initialChildren: children,
        );

  static const String name = 'MapEditorRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<MapEditorRouteArgs>();
      return _i30.MapEditorPage(mode: args.mode, key: args.key);
    },
  );
}

class MapEditorRouteArgs {
  const MapEditorRouteArgs({required this.mode, this.key});

  final _i30.MapEditorMode mode;

  final _i81.Key? key;

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
/// [_i31.McpConnectionPage]
class McpConnectionRoute extends _i77.PageRouteInfo<McpConnectionRouteArgs> {
  McpConnectionRoute({
    _i78.Key? key,
    String? request,
    _i31.McpConnectionRequester? requester,
    bool Function()? isLoggedIn,
    String? accountEmail,
    _i84.McpCallbackWindow? Function()? openCallbackWindow,
    List<_i77.PageRouteInfo>? children,
  }) : super(
          McpConnectionRoute.name,
          args: McpConnectionRouteArgs(
            key: key,
            request: request,
            requester: requester,
            isLoggedIn: isLoggedIn,
            accountEmail: accountEmail,
            openCallbackWindow: openCallbackWindow,
          ),
          rawQueryParams: {'request': request},
          initialChildren: children,
        );

  static const String name = 'McpConnectionRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      final queryParams = data.queryParams;
      final args = data.argsAs<McpConnectionRouteArgs>(
        orElse: () =>
            McpConnectionRouteArgs(request: queryParams.optString('request')),
      );
      return _i31.McpConnectionPage(
        key: args.key,
        request: args.request,
        requester: args.requester,
        isLoggedIn: args.isLoggedIn,
        accountEmail: args.accountEmail,
        openCallbackWindow: args.openCallbackWindow,
      );
    },
  );
}

class McpConnectionRouteArgs {
  const McpConnectionRouteArgs({
    this.key,
    this.request,
    this.requester,
    this.isLoggedIn,
    this.accountEmail,
    this.openCallbackWindow,
  });

  final _i78.Key? key;

  final String? request;

  final _i31.McpConnectionRequester? requester;

  final bool Function()? isLoggedIn;

  final String? accountEmail;

  final _i84.McpCallbackWindow? Function()? openCallbackWindow;

  @override
  String toString() {
    return 'McpConnectionRouteArgs{key: $key, request: $request, requester: $requester, isLoggedIn: $isLoggedIn, accountEmail: $accountEmail, openCallbackWindow: $openCallbackWindow}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! McpConnectionRouteArgs) return false;
    return key == other.key &&
        request == other.request &&
        requester == other.requester &&
        accountEmail == other.accountEmail;
  }

  @override
  int get hashCode =>
      key.hashCode ^
      request.hashCode ^
      requester.hashCode ^
      accountEmail.hashCode;
}

/// generated route for
/// [_i32.MySchedulePage]
class MyScheduleRoute extends _i77.PageRouteInfo<void> {
  const MyScheduleRoute({List<_i77.PageRouteInfo>? children})
      : super(MyScheduleRoute.name, initialChildren: children);

  static const String name = 'MyScheduleRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i32.MySchedulePage();
    },
  );
}

/// generated route for
/// [_i33.NavigationNotFoundPage]
class NavigationNotFoundRoute extends _i77.PageRouteInfo<void> {
  const NavigationNotFoundRoute({List<_i77.PageRouteInfo>? children})
      : super(NavigationNotFoundRoute.name, initialChildren: children);

  static const String name = 'NavigationNotFoundRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i33.NavigationNotFoundPage();
    },
  );
}

/// generated route for
/// [_i34.NewsFormPage]
class NewsFormRoute extends _i77.PageRouteInfo<NewsFormRouteArgs> {
  NewsFormRoute({
    _i81.Key? key,
    String occasionLink = '',
    _i78.Widget? editorOverride,
    _i79.Future<void> Function(_i34.NewsSubmission)? onSubmit,
    List<_i77.PageRouteInfo>? children,
  }) : super(
          NewsFormRoute.name,
          args: NewsFormRouteArgs(
            key: key,
            occasionLink: occasionLink,
            editorOverride: editorOverride,
            onSubmit: onSubmit,
          ),
          rawPathParams: {'{occasionLink}': occasionLink},
          initialChildren: children,
        );

  static const String name = 'NewsFormRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      final pathParams = data.inheritedPathParams;
      final args = data.argsAs<NewsFormRouteArgs>(
        orElse: () => NewsFormRouteArgs(
          occasionLink: pathParams.getString('{occasionLink}', ''),
        ),
      );
      return _i34.NewsFormPage(
        key: args.key,
        occasionLink: args.occasionLink,
        editorOverride: args.editorOverride,
        onSubmit: args.onSubmit,
      );
    },
  );
}

class NewsFormRouteArgs {
  const NewsFormRouteArgs({
    this.key,
    this.occasionLink = '',
    this.editorOverride,
    this.onSubmit,
  });

  final _i81.Key? key;

  final String occasionLink;

  final _i78.Widget? editorOverride;

  final _i79.Future<void> Function(_i34.NewsSubmission)? onSubmit;

  @override
  String toString() {
    return 'NewsFormRouteArgs{key: $key, occasionLink: $occasionLink, editorOverride: $editorOverride, onSubmit: $onSubmit}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! NewsFormRouteArgs) return false;
    return key == other.key &&
        occasionLink == other.occasionLink &&
        editorOverride == other.editorOverride;
  }

  @override
  int get hashCode =>
      key.hashCode ^ occasionLink.hashCode ^ editorOverride.hashCode;
}

/// generated route for
/// [_i35.NewsPage]
class NewsRoute extends _i77.PageRouteInfo<NewsRouteArgs> {
  NewsRoute({
    _i78.Key? key,
    _i78.VoidCallback? onSetAsRead,
    List<_i77.PageRouteInfo>? children,
  }) : super(
          NewsRoute.name,
          args: NewsRouteArgs(key: key, onSetAsRead: onSetAsRead),
          initialChildren: children,
        );

  static const String name = 'NewsRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<NewsRouteArgs>(
        orElse: () => const NewsRouteArgs(),
      );
      return _i35.NewsPage(key: args.key, onSetAsRead: args.onSetAsRead);
    },
  );
}

class NewsRouteArgs {
  const NewsRouteArgs({this.key, this.onSetAsRead});

  final _i78.Key? key;

  final _i78.VoidCallback? onSetAsRead;

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
/// [_i36.OccasionHomePage]
class OccasionHomeRoute extends _i77.PageRouteInfo<void> {
  const OccasionHomeRoute({List<_i77.PageRouteInfo>? children})
      : super(OccasionHomeRoute.name, initialChildren: children);

  static const String name = 'OccasionHomeRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i36.OccasionHomePage();
    },
  );
}

/// generated route for
/// [_i37.OccasionTeamInvitationPage]
class OccasionTeamInvitationRoute
    extends _i77.PageRouteInfo<OccasionTeamInvitationRouteArgs> {
  OccasionTeamInvitationRoute({
    _i78.Key? key,
    String? token,
    _i37.OccasionTeamInvitationLoader? loader,
    _i37.OccasionTeamInvitationAcceptor? acceptor,
    bool Function()? isLoggedIn,
    List<_i77.PageRouteInfo>? children,
  }) : super(
          OccasionTeamInvitationRoute.name,
          args: OccasionTeamInvitationRouteArgs(
            key: key,
            token: token,
            loader: loader,
            acceptor: acceptor,
            isLoggedIn: isLoggedIn,
          ),
          rawQueryParams: {'token': token},
          initialChildren: children,
        );

  static const String name = 'OccasionTeamInvitationRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      final queryParams = data.queryParams;
      final args = data.argsAs<OccasionTeamInvitationRouteArgs>(
        orElse: () => OccasionTeamInvitationRouteArgs(
          token: queryParams.optString('token'),
        ),
      );
      return _i37.OccasionTeamInvitationPage(
        key: args.key,
        token: args.token,
        loader: args.loader,
        acceptor: args.acceptor,
        isLoggedIn: args.isLoggedIn,
      );
    },
  );
}

class OccasionTeamInvitationRouteArgs {
  const OccasionTeamInvitationRouteArgs({
    this.key,
    this.token,
    this.loader,
    this.acceptor,
    this.isLoggedIn,
  });

  final _i78.Key? key;

  final String? token;

  final _i37.OccasionTeamInvitationLoader? loader;

  final _i37.OccasionTeamInvitationAcceptor? acceptor;

  final bool Function()? isLoggedIn;

  @override
  String toString() {
    return 'OccasionTeamInvitationRouteArgs{key: $key, token: $token, loader: $loader, acceptor: $acceptor, isLoggedIn: $isLoggedIn}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! OccasionTeamInvitationRouteArgs) return false;
    return key == other.key &&
        token == other.token &&
        loader == other.loader &&
        acceptor == other.acceptor;
  }

  @override
  int get hashCode =>
      key.hashCode ^ token.hashCode ^ loader.hashCode ^ acceptor.hashCode;
}

/// generated route for
/// [_i38.OrdersCurrentPage]
class OrdersCurrentRoute extends _i77.PageRouteInfo<void> {
  const OrdersCurrentRoute({List<_i77.PageRouteInfo>? children})
      : super(OrdersCurrentRoute.name, initialChildren: children);

  static const String name = 'OrdersCurrentRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i38.OrdersCurrentPage();
    },
  );
}

/// generated route for
/// [_i39.OrdersEmailHistoryPage]
class OrdersEmailHistoryRoute extends _i77.PageRouteInfo<void> {
  const OrdersEmailHistoryRoute({List<_i77.PageRouteInfo>? children})
      : super(OrdersEmailHistoryRoute.name, initialChildren: children);

  static const String name = 'OrdersEmailHistoryRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i39.OrdersEmailHistoryPage();
    },
  );
}

/// generated route for
/// [_i38.OrdersHistoryPage]
class OrdersHistoryRoute extends _i77.PageRouteInfo<void> {
  const OrdersHistoryRoute({List<_i77.PageRouteInfo>? children})
      : super(OrdersHistoryRoute.name, initialChildren: children);

  static const String name = 'OrdersHistoryRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i38.OrdersHistoryPage();
    },
  );
}

/// generated route for
/// [_i40.OrdersNavigationPage]
class OrdersNavigationRoute extends _i77.PageRouteInfo<void> {
  const OrdersNavigationRoute({List<_i77.PageRouteInfo>? children})
      : super(OrdersNavigationRoute.name, initialChildren: children);

  static const String name = 'OrdersNavigationRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i40.OrdersNavigationPage();
    },
  );
}

/// generated route for
/// [_i38.OrdersTab]
class OrdersTabsRoute extends _i77.PageRouteInfo<void> {
  const OrdersTabsRoute({List<_i77.PageRouteInfo>? children})
      : super(OrdersTabsRoute.name, initialChildren: children);

  static const String name = 'OrdersTabsRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i38.OrdersTab();
    },
  );
}

/// generated route for
/// [_i41.OrganizationEditPage]
class OrganizationEditRoute
    extends _i77.PageRouteInfo<OrganizationEditRouteArgs> {
  OrganizationEditRoute({
    _i78.Key? key,
    required int id,
    List<_i77.PageRouteInfo>? children,
  }) : super(
          OrganizationEditRoute.name,
          args: OrganizationEditRouteArgs(key: key, id: id),
          rawPathParams: {'id': id},
          initialChildren: children,
        );

  static const String name = 'OrganizationEditRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      final pathParams = data.inheritedPathParams;
      final args = data.argsAs<OrganizationEditRouteArgs>(
        orElse: () => OrganizationEditRouteArgs(id: pathParams.getInt('id')),
      );
      return _i41.OrganizationEditPage(key: args.key, id: args.id);
    },
  );
}

class OrganizationEditRouteArgs {
  const OrganizationEditRouteArgs({this.key, required this.id});

  final _i78.Key? key;

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
/// [_i42.OrganizationEditRedirectPage]
class OrganizationEditRedirectRoute extends _i77.PageRouteInfo<void> {
  const OrganizationEditRedirectRoute({List<_i77.PageRouteInfo>? children})
      : super(OrganizationEditRedirectRoute.name, initialChildren: children);

  static const String name = 'OrganizationEditRedirectRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i42.OrganizationEditRedirectPage();
    },
  );
}

/// generated route for
/// [_i43.OrganizationPage]
class OrganizationRoute extends _i77.PageRouteInfo<OrganizationRouteArgs> {
  OrganizationRoute({
    int? id,
    _i78.Key? key,
    List<_i77.PageRouteInfo>? children,
  }) : super(
          OrganizationRoute.name,
          args: OrganizationRouteArgs(id: id, key: key),
          rawPathParams: {'id': id},
          initialChildren: children,
        );

  static const String name = 'OrganizationRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      final pathParams = data.inheritedPathParams;
      final args = data.argsAs<OrganizationRouteArgs>(
        orElse: () => OrganizationRouteArgs(id: pathParams.optInt('id')),
      );
      return _i43.OrganizationPage(id: args.id, key: args.key);
    },
  );
}

class OrganizationRouteArgs {
  const OrganizationRouteArgs({this.id, this.key});

  final int? id;

  final _i78.Key? key;

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
/// [_i44.PlacesIconsPage]
class PlacesIconsRoute extends _i77.PageRouteInfo<void> {
  const PlacesIconsRoute({List<_i77.PageRouteInfo>? children})
      : super(PlacesIconsRoute.name, initialChildren: children);

  static const String name = 'PlacesIconsRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i44.PlacesIconsPage();
    },
  );
}

/// generated route for
/// [_i44.PlacesListPage]
class PlacesListRoute extends _i77.PageRouteInfo<void> {
  const PlacesListRoute({List<_i77.PageRouteInfo>? children})
      : super(PlacesListRoute.name, initialChildren: children);

  static const String name = 'PlacesListRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i44.PlacesListPage();
    },
  );
}

/// generated route for
/// [_i45.PlacesNavigationPage]
class PlacesNavigationRoute extends _i77.PageRouteInfo<void> {
  const PlacesNavigationRoute({List<_i77.PageRouteInfo>? children})
      : super(PlacesNavigationRoute.name, initialChildren: children);

  static const String name = 'PlacesNavigationRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i45.PlacesNavigationPage();
    },
  );
}

/// generated route for
/// [_i44.PlacesPathsPage]
class PlacesPathsRoute extends _i77.PageRouteInfo<void> {
  const PlacesPathsRoute({List<_i77.PageRouteInfo>? children})
      : super(PlacesPathsRoute.name, initialChildren: children);

  static const String name = 'PlacesPathsRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i44.PlacesPathsPage();
    },
  );
}

/// generated route for
/// [_i44.PlacesTab]
class PlacesTabsRoute extends _i77.PageRouteInfo<void> {
  const PlacesTabsRoute({List<_i77.PageRouteInfo>? children})
      : super(PlacesTabsRoute.name, initialChildren: children);

  static const String name = 'PlacesTabsRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i44.PlacesTab();
    },
  );
}

/// generated route for
/// [_i44.PlacesTypesPage]
class PlacesTypesRoute extends _i77.PageRouteInfo<void> {
  const PlacesTypesRoute({List<_i77.PageRouteInfo>? children})
      : super(PlacesTypesRoute.name, initialChildren: children);

  static const String name = 'PlacesTypesRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i44.PlacesTypesPage();
    },
  );
}

/// generated route for
/// [_i46.ProductsSectionPage]
class ProductsSectionRoute extends _i77.PageRouteInfo<void> {
  const ProductsSectionRoute({List<_i77.PageRouteInfo>? children})
      : super(ProductsSectionRoute.name, initialChildren: children);

  static const String name = 'ProductsSectionRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i46.ProductsSectionPage();
    },
  );
}

/// generated route for
/// [_i30.PublicMapPage]
class PublicMapRoute extends _i77.PageRouteInfo<PublicMapRouteArgs> {
  PublicMapRoute({
    String destination = 'overview',
    String? placeType,
    _i81.Key? key,
    List<_i77.PageRouteInfo>? children,
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

  static _i77.PageInfo page = _i77.PageInfo(
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
      return _i30.PublicMapPage(
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

  final _i81.Key? key;

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
/// [_i47.ReceptionPage]
class ReceptionRoute extends _i77.PageRouteInfo<void> {
  const ReceptionRoute({List<_i77.PageRouteInfo>? children})
      : super(ReceptionRoute.name, initialChildren: children);

  static const String name = 'ReceptionRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i47.ReceptionPage();
    },
  );
}

/// generated route for
/// [_i48.ReportSectionPage]
class ReportSectionRoute extends _i77.PageRouteInfo<void> {
  const ReportSectionRoute({List<_i77.PageRouteInfo>? children})
      : super(ReportSectionRoute.name, initialChildren: children);

  static const String name = 'ReportSectionRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i48.ReportSectionPage();
    },
  );
}

/// generated route for
/// [_i49.ReservationsPage]
class ReservationsRoute extends _i77.PageRouteInfo<void> {
  const ReservationsRoute({List<_i77.PageRouteInfo>? children})
      : super(ReservationsRoute.name, initialChildren: children);

  static const String name = 'ReservationsRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i49.ReservationsPage();
    },
  );
}

/// generated route for
/// [_i49.ReservationsTabsPage]
class ReservationsTabsRoute extends _i77.PageRouteInfo<void> {
  const ReservationsTabsRoute({List<_i77.PageRouteInfo>? children})
      : super(ReservationsTabsRoute.name, initialChildren: children);

  static const String name = 'ReservationsTabsRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i49.ReservationsTabsPage();
    },
  );
}

/// generated route for
/// [_i50.ResetPasswordPage]
class ResetPasswordRoute extends _i77.PageRouteInfo<ResetPasswordRouteArgs> {
  ResetPasswordRoute({
    String? token,
    _i78.Key? key,
    List<_i77.PageRouteInfo>? children,
  }) : super(
          ResetPasswordRoute.name,
          args: ResetPasswordRouteArgs(token: token, key: key),
          rawQueryParams: {'token': token},
          initialChildren: children,
        );

  static const String name = 'ResetPasswordRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      final queryParams = data.queryParams;
      final args = data.argsAs<ResetPasswordRouteArgs>(
        orElse: () =>
            ResetPasswordRouteArgs(token: queryParams.optString('token')),
      );
      return _i50.ResetPasswordPage(token: args.token, key: args.key);
    },
  );
}

class ResetPasswordRouteArgs {
  const ResetPasswordRouteArgs({this.token, this.key});

  final String? token;

  final _i78.Key? key;

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
/// [_i51.ScanPage]
class ScanRoute extends _i77.PageRouteInfo<ScanRouteArgs> {
  ScanRoute({
    String? scanCode,
    _i81.Key? key,
    List<_i77.PageRouteInfo>? children,
  }) : super(
          ScanRoute.name,
          args: ScanRouteArgs(scanCode: scanCode, key: key),
          rawPathParams: {'scanCode': scanCode},
          initialChildren: children,
        );

  static const String name = 'ScanRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      final pathParams = data.inheritedPathParams;
      final args = data.argsAs<ScanRouteArgs>(
        orElse: () => ScanRouteArgs(scanCode: pathParams.optString('scanCode')),
      );
      return _i51.ScanPage(scanCode: args.scanCode, key: args.key);
    },
  );
}

class ScanRouteArgs {
  const ScanRouteArgs({this.scanCode, this.key});

  final String? scanCode;

  final _i81.Key? key;

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
/// [_i52.ScheduleBasicPage]
class ScheduleBasicRoute extends _i77.PageRouteInfo<void> {
  const ScheduleBasicRoute({List<_i77.PageRouteInfo>? children})
      : super(ScheduleBasicRoute.name, initialChildren: children);

  static const String name = 'ScheduleBasicRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i52.ScheduleBasicPage();
    },
  );
}

/// generated route for
/// [_i53.ScheduleExclusivityPage]
class ScheduleExclusivityRoute extends _i77.PageRouteInfo<void> {
  const ScheduleExclusivityRoute({List<_i77.PageRouteInfo>? children})
      : super(ScheduleExclusivityRoute.name, initialChildren: children);

  static const String name = 'ScheduleExclusivityRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i53.ScheduleExclusivityPage();
    },
  );
}

/// generated route for
/// [_i53.ScheduleFeedbackPage]
class ScheduleFeedbackRoute extends _i77.PageRouteInfo<void> {
  const ScheduleFeedbackRoute({List<_i77.PageRouteInfo>? children})
      : super(ScheduleFeedbackRoute.name, initialChildren: children);

  static const String name = 'ScheduleFeedbackRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i53.ScheduleFeedbackPage();
    },
  );
}

/// generated route for
/// [_i54.ScheduleLightPage]
class ScheduleLightRoute extends _i77.PageRouteInfo<void> {
  const ScheduleLightRoute({List<_i77.PageRouteInfo>? children})
      : super(ScheduleLightRoute.name, initialChildren: children);

  static const String name = 'ScheduleLightRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i54.ScheduleLightPage();
    },
  );
}

/// generated route for
/// [_i55.ScheduleNavigationPage]
class ScheduleNavigationRoute extends _i77.PageRouteInfo<void> {
  const ScheduleNavigationRoute({List<_i77.PageRouteInfo>? children})
      : super(ScheduleNavigationRoute.name, initialChildren: children);

  static const String name = 'ScheduleNavigationRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i55.ScheduleNavigationPage();
    },
  );
}

/// generated route for
/// [_i56.SchedulePage]
class ScheduleRoute extends _i77.PageRouteInfo<void> {
  const ScheduleRoute({List<_i77.PageRouteInfo>? children})
      : super(ScheduleRoute.name, initialChildren: children);

  static const String name = 'ScheduleRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i56.SchedulePage();
    },
  );
}

/// generated route for
/// [_i53.ScheduleSchedulePage]
class ScheduleScheduleRoute extends _i77.PageRouteInfo<void> {
  const ScheduleScheduleRoute({List<_i77.PageRouteInfo>? children})
      : super(ScheduleScheduleRoute.name, initialChildren: children);

  static const String name = 'ScheduleScheduleRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i53.ScheduleSchedulePage();
    },
  );
}

/// generated route for
/// [_i53.ScheduleSuspiciousPage]
class ScheduleSuspiciousRoute extends _i77.PageRouteInfo<void> {
  const ScheduleSuspiciousRoute({List<_i77.PageRouteInfo>? children})
      : super(ScheduleSuspiciousRoute.name, initialChildren: children);

  static const String name = 'ScheduleSuspiciousRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i53.ScheduleSuspiciousPage();
    },
  );
}

/// generated route for
/// [_i53.ScheduleTab]
class ScheduleTabsRoute extends _i77.PageRouteInfo<void> {
  const ScheduleTabsRoute({List<_i77.PageRouteInfo>? children})
      : super(ScheduleTabsRoute.name, initialChildren: children);

  static const String name = 'ScheduleTabsRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i53.ScheduleTab();
    },
  );
}

/// generated route for
/// [_i57.ServiceSectionPage]
class ServiceSectionRoute extends _i77.PageRouteInfo<void> {
  const ServiceSectionRoute({List<_i77.PageRouteInfo>? children})
      : super(ServiceSectionRoute.name, initialChildren: children);

  static const String name = 'ServiceSectionRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i57.ServiceSectionPage();
    },
  );
}

/// generated route for
/// [_i58.SettingsPage]
class SettingsRoute extends _i77.PageRouteInfo<void> {
  const SettingsRoute({List<_i77.PageRouteInfo>? children})
      : super(SettingsRoute.name, initialChildren: children);

  static const String name = 'SettingsRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i58.SettingsPage();
    },
  );
}

/// generated route for
/// [_i59.SettingsSectionPage]
class SettingsSectionRoute extends _i77.PageRouteInfo<void> {
  const SettingsSectionRoute({List<_i77.PageRouteInfo>? children})
      : super(SettingsSectionRoute.name, initialChildren: children);

  static const String name = 'SettingsSectionRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i59.SettingsSectionPage();
    },
  );
}

/// generated route for
/// [_i60.SignupPage]
class SignupRoute extends _i77.PageRouteInfo<void> {
  const SignupRoute({List<_i77.PageRouteInfo>? children})
      : super(SignupRoute.name, initialChildren: children);

  static const String name = 'SignupRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i60.SignupPage();
    },
  );
}

/// generated route for
/// [_i61.SongbookPage]
class SongbookRoute extends _i77.PageRouteInfo<void> {
  const SongbookRoute({List<_i77.PageRouteInfo>? children})
      : super(SongbookRoute.name, initialChildren: children);

  static const String name = 'SongbookRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i61.SongbookPage();
    },
  );
}

/// generated route for
/// [_i62.SpeakersSectionPage]
class SpeakersSectionRoute extends _i77.PageRouteInfo<void> {
  const SpeakersSectionRoute({List<_i77.PageRouteInfo>? children})
      : super(SpeakersSectionRoute.name, initialChildren: children);

  static const String name = 'SpeakersSectionRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i62.SpeakersSectionPage();
    },
  );
}

/// generated route for
/// [_i63.StripeConnectCallbackPage]
class StripeConnectCallbackRoute
    extends _i77.PageRouteInfo<StripeConnectCallbackRouteArgs> {
  StripeConnectCallbackRoute({
    _i78.Key? key,
    String? code,
    String? state,
    String? error,
    List<_i77.PageRouteInfo>? children,
  }) : super(
          StripeConnectCallbackRoute.name,
          args: StripeConnectCallbackRouteArgs(
            key: key,
            code: code,
            state: state,
            error: error,
          ),
          rawQueryParams: {'code': code, 'state': state, 'error': error},
          initialChildren: children,
        );

  static const String name = 'StripeConnectCallbackRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      final queryParams = data.queryParams;
      final args = data.argsAs<StripeConnectCallbackRouteArgs>(
        orElse: () => StripeConnectCallbackRouteArgs(
          code: queryParams.optString('code'),
          state: queryParams.optString('state'),
          error: queryParams.optString('error'),
        ),
      );
      return _i63.StripeConnectCallbackPage(
        key: args.key,
        code: args.code,
        state: args.state,
        error: args.error,
      );
    },
  );
}

class StripeConnectCallbackRouteArgs {
  const StripeConnectCallbackRouteArgs({
    this.key,
    this.code,
    this.state,
    this.error,
  });

  final _i78.Key? key;

  final String? code;

  final String? state;

  final String? error;

  @override
  String toString() {
    return 'StripeConnectCallbackRouteArgs{key: $key, code: $code, state: $state, error: $error}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! StripeConnectCallbackRouteArgs) return false;
    return key == other.key &&
        code == other.code &&
        state == other.state &&
        error == other.error;
  }

  @override
  int get hashCode =>
      key.hashCode ^ code.hashCode ^ state.hashCode ^ error.hashCode;
}

/// generated route for
/// [_i64.StripePayPage]
class StripePayRoute extends _i77.PageRouteInfo<void> {
  const StripePayRoute({List<_i77.PageRouteInfo>? children})
      : super(StripePayRoute.name, initialChildren: children);

  static const String name = 'StripePayRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i64.StripePayPage();
    },
  );
}

/// generated route for
/// [_i64.StripeReturnPage]
class StripeReturnRoute extends _i77.PageRouteInfo<void> {
  const StripeReturnRoute({List<_i77.PageRouteInfo>? children})
      : super(StripeReturnRoute.name, initialChildren: children);

  static const String name = 'StripeReturnRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i64.StripeReturnPage();
    },
  );
}

/// generated route for
/// [_i65.TicketBatchDetailPage]
class TicketBatchDetailRoute
    extends _i77.PageRouteInfo<TicketBatchDetailRouteArgs> {
  TicketBatchDetailRoute({
    _i78.Key? key,
    required String batchId,
    List<_i77.PageRouteInfo>? children,
  }) : super(
          TicketBatchDetailRoute.name,
          args: TicketBatchDetailRouteArgs(key: key, batchId: batchId),
          rawPathParams: {'batchId': batchId},
          initialChildren: children,
        );

  static const String name = 'TicketBatchDetailRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      final pathParams = data.inheritedPathParams;
      final args = data.argsAs<TicketBatchDetailRouteArgs>(
        orElse: () => TicketBatchDetailRouteArgs(
          batchId: pathParams.getString('batchId'),
        ),
      );
      return _i65.TicketBatchDetailPage(key: args.key, batchId: args.batchId);
    },
  );
}

class TicketBatchDetailRouteArgs {
  const TicketBatchDetailRouteArgs({this.key, required this.batchId});

  final _i78.Key? key;

  final String batchId;

  @override
  String toString() {
    return 'TicketBatchDetailRouteArgs{key: $key, batchId: $batchId}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! TicketBatchDetailRouteArgs) return false;
    return key == other.key && batchId == other.batchId;
  }

  @override
  int get hashCode => key.hashCode ^ batchId.hashCode;
}

/// generated route for
/// [_i65.TicketBatchListPage]
class TicketBatchListRoute extends _i77.PageRouteInfo<void> {
  const TicketBatchListRoute({List<_i77.PageRouteInfo>? children})
      : super(TicketBatchListRoute.name, initialChildren: children);

  static const String name = 'TicketBatchListRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i65.TicketBatchListPage();
    },
  );
}

/// generated route for
/// [_i65.TicketBatchesPage]
class TicketBatchesRoute extends _i77.PageRouteInfo<void> {
  const TicketBatchesRoute({List<_i77.PageRouteInfo>? children})
      : super(TicketBatchesRoute.name, initialChildren: children);

  static const String name = 'TicketBatchesRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i65.TicketBatchesPage();
    },
  );
}

/// generated route for
/// [_i66.TicketsSectionPage]
class TicketsSectionRoute extends _i77.PageRouteInfo<void> {
  const TicketsSectionRoute({List<_i77.PageRouteInfo>? children})
      : super(TicketsSectionRoute.name, initialChildren: children);

  static const String name = 'TicketsSectionRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i66.TicketsSectionPage();
    },
  );
}

/// generated route for
/// [_i67.TimetablePage]
class TimetableRoute extends _i77.PageRouteInfo<void> {
  const TimetableRoute({List<_i77.PageRouteInfo>? children})
      : super(TimetableRoute.name, initialChildren: children);

  static const String name = 'TimetableRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i67.TimetablePage();
    },
  );
}

/// generated route for
/// [_i68.TransferPage]
class TransferRoute extends _i77.PageRouteInfo<TransferRouteArgs> {
  TransferRoute({
    _i78.Key? key,
    String? access_token,
    String? refresh_token,
    String? redirect,
    List<_i77.PageRouteInfo>? children,
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

  static _i77.PageInfo page = _i77.PageInfo(
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
      return _i68.TransferPage(
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

  final _i78.Key? key;

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
/// [_i69.UnitAdminPage]
class UnitAdminRoute extends _i77.PageRouteInfo<UnitAdminRouteArgs> {
  UnitAdminRoute({
    _i78.Key? key,
    required int? id,
    _i85.UnitAdministrationAccess? access,
    List<_i77.PageRouteInfo>? children,
  }) : super(
          UnitAdminRoute.name,
          args: UnitAdminRouteArgs(key: key, id: id, access: access),
          rawPathParams: {'id': id},
          initialChildren: children,
        );

  static const String name = 'UnitAdminRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      final pathParams = data.inheritedPathParams;
      final args = data.argsAs<UnitAdminRouteArgs>(
        orElse: () => UnitAdminRouteArgs(id: pathParams.optInt('id')),
      );
      return _i69.UnitAdminPage(
        key: args.key,
        id: args.id,
        access: args.access,
      );
    },
  );
}

class UnitAdminRouteArgs {
  const UnitAdminRouteArgs({this.key, required this.id, this.access});

  final _i78.Key? key;

  final int? id;

  final _i85.UnitAdministrationAccess? access;

  @override
  String toString() {
    return 'UnitAdminRouteArgs{key: $key, id: $id, access: $access}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! UnitAdminRouteArgs) return false;
    return key == other.key && id == other.id && access == other.access;
  }

  @override
  int get hashCode => key.hashCode ^ id.hashCode ^ access.hashCode;
}

/// generated route for
/// [_i69.UnitAdministrationTabsPage]
class UnitAdministrationTabsRoute extends _i77.PageRouteInfo<void> {
  const UnitAdministrationTabsRoute({List<_i77.PageRouteInfo>? children})
      : super(UnitAdministrationTabsRoute.name, initialChildren: children);

  static const String name = 'UnitAdministrationTabsRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i69.UnitAdministrationTabsPage();
    },
  );
}

/// generated route for
/// [_i3.UnitBankAccountsListPage]
class UnitBankAccountsListRoute extends _i77.PageRouteInfo<void> {
  const UnitBankAccountsListRoute({List<_i77.PageRouteInfo>? children})
      : super(UnitBankAccountsListRoute.name, initialChildren: children);

  static const String name = 'UnitBankAccountsListRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i3.UnitBankAccountsListPage();
    },
  );
}

/// generated route for
/// [_i3.UnitBankAccountsNavigationPage]
class UnitBankAccountsNavigationRoute extends _i77.PageRouteInfo<void> {
  const UnitBankAccountsNavigationRoute({List<_i77.PageRouteInfo>? children})
      : super(UnitBankAccountsNavigationRoute.name, initialChildren: children);

  static const String name = 'UnitBankAccountsNavigationRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i3.UnitBankAccountsNavigationPage();
    },
  );
}

/// generated route for
/// [_i70.UnitCardPaymentsPage]
class UnitCardPaymentsRoute extends _i77.PageRouteInfo<void> {
  const UnitCardPaymentsRoute({List<_i77.PageRouteInfo>? children})
      : super(UnitCardPaymentsRoute.name, initialChildren: children);

  static const String name = 'UnitCardPaymentsRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i70.UnitCardPaymentsPage();
    },
  );
}

/// generated route for
/// [_i69.UnitEmailTemplatesPage]
class UnitEmailTemplatesRoute extends _i77.PageRouteInfo<void> {
  const UnitEmailTemplatesRoute({List<_i77.PageRouteInfo>? children})
      : super(UnitEmailTemplatesRoute.name, initialChildren: children);

  static const String name = 'UnitEmailTemplatesRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i69.UnitEmailTemplatesPage();
    },
  );
}

/// generated route for
/// [_i71.UnitLegalProfilePage]
class UnitLegalProfileRoute extends _i77.PageRouteInfo<void> {
  const UnitLegalProfileRoute({List<_i77.PageRouteInfo>? children})
      : super(UnitLegalProfileRoute.name, initialChildren: children);

  static const String name = 'UnitLegalProfileRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i71.UnitLegalProfilePage();
    },
  );
}

/// generated route for
/// [_i69.UnitOccasionsPage]
class UnitOccasionsRoute extends _i77.PageRouteInfo<void> {
  const UnitOccasionsRoute({List<_i77.PageRouteInfo>? children})
      : super(UnitOccasionsRoute.name, initialChildren: children);

  static const String name = 'UnitOccasionsRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i69.UnitOccasionsPage();
    },
  );
}

/// generated route for
/// [_i72.UnitPage]
class UnitRoute extends _i77.PageRouteInfo<UnitRouteArgs> {
  UnitRoute({int? id, _i78.Key? key, List<_i77.PageRouteInfo>? children})
      : super(
          UnitRoute.name,
          args: UnitRouteArgs(id: id, key: key),
          rawPathParams: {'id': id},
          initialChildren: children,
        );

  static const String name = 'UnitRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      final pathParams = data.inheritedPathParams;
      final args = data.argsAs<UnitRouteArgs>(
        orElse: () => UnitRouteArgs(id: pathParams.optInt('id')),
      );
      return _i72.UnitPage(id: args.id, key: args.key);
    },
  );
}

class UnitRouteArgs {
  const UnitRouteArgs({this.id, this.key});

  final int? id;

  final _i78.Key? key;

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
/// [_i69.UnitQuotesPage]
class UnitQuotesRoute extends _i77.PageRouteInfo<void> {
  const UnitQuotesRoute({List<_i77.PageRouteInfo>? children})
      : super(UnitQuotesRoute.name, initialChildren: children);

  static const String name = 'UnitQuotesRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i69.UnitQuotesPage();
    },
  );
}

/// generated route for
/// [_i69.UnitSettingsContentPage]
class UnitSettingsContentRoute extends _i77.PageRouteInfo<void> {
  const UnitSettingsContentRoute({List<_i77.PageRouteInfo>? children})
      : super(UnitSettingsContentRoute.name, initialChildren: children);

  static const String name = 'UnitSettingsContentRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i69.UnitSettingsContentPage();
    },
  );
}

/// generated route for
/// [_i69.UnitSettingsPage]
class UnitSettingsRoute extends _i77.PageRouteInfo<void> {
  const UnitSettingsRoute({List<_i77.PageRouteInfo>? children})
      : super(UnitSettingsRoute.name, initialChildren: children);

  static const String name = 'UnitSettingsRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i69.UnitSettingsPage();
    },
  );
}

/// generated route for
/// [_i69.UnitUsersPage]
class UnitUsersRoute extends _i77.PageRouteInfo<void> {
  const UnitUsersRoute({List<_i77.PageRouteInfo>? children})
      : super(UnitUsersRoute.name, initialChildren: children);

  static const String name = 'UnitUsersRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i69.UnitUsersPage();
    },
  );
}

/// generated route for
/// [_i73.UserPage]
class UserRoute extends _i77.PageRouteInfo<void> {
  const UserRoute({List<_i77.PageRouteInfo>? children})
      : super(UserRoute.name, initialChildren: children);

  static const String name = 'UserRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i73.UserPage();
    },
  );
}

/// generated route for
/// [_i74.UserStayPage]
class UserStayRoute extends _i77.PageRouteInfo<void> {
  const UserStayRoute({List<_i77.PageRouteInfo>? children})
      : super(UserStayRoute.name, initialChildren: children);

  static const String name = 'UserStayRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i74.UserStayPage();
    },
  );
}

/// generated route for
/// [_i75.UsersSectionPage]
class UsersSectionRoute extends _i77.PageRouteInfo<void> {
  const UsersSectionRoute({List<_i77.PageRouteInfo>? children})
      : super(UsersSectionRoute.name, initialChildren: children);

  static const String name = 'UsersSectionRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i75.UsersSectionPage();
    },
  );
}

/// generated route for
/// [_i76.VolunteersSectionPage]
class VolunteersSectionRoute extends _i77.PageRouteInfo<void> {
  const VolunteersSectionRoute({List<_i77.PageRouteInfo>? children})
      : super(VolunteersSectionRoute.name, initialChildren: children);

  static const String name = 'VolunteersSectionRoute';

  static _i77.PageInfo page = _i77.PageInfo(
    name,
    builder: (data) {
      return const _i76.VolunteersSectionPage();
    },
  );
}
