import 'package:flutter/material.dart';
import 'package:fstapp/components/single_data_grid/data_grid_helper.dart';
import 'package:fstapp/components/users/user_strings.dart';
import 'package:fstapp/components/occasion_services/service_item_model.dart';
import 'package:fstapp/components/users/user_info_model.dart';
import 'package:fstapp/components/occasion/db_occasions.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:trina_grid/trina_grid.dart';

class UserColumns {
  static const String ID = "id";
  static const String UNIT = "unit";
  static const String EMAIL = "email";
  static const String NAME = "name";
  static const String SURNAME = "surname";
  static const String GROUP = "group";
  static const String COMPANION_OWNER = "companionOwner";
  static const String COMPANION_OWNER_ID = "companionOwnerId";
  static const String COMPANION_ORIGIN = "companionOrigin";
  static const String MANAGED_COMPANION_NAMES = "managedCompanionNames";
  static const String SEX = "sex";
  static const String ACCOMMODATION = "accommodation";
  static const String PHONE = "phone";
  static const String BIRTHDAY = "birthday";
  static const String ROLE = "role";
  static const String TEXT1 = "text1";
  static const String TEXT2 = "text2";
  static const String TEXT3 = "text3";
  static const String NOTE = "note";
  static const String DIET = "diet";
  static const String IS_VOLUNTEER = "isVolunteer";
  static const String MANAGER = "manager";
  static const String EDITOR = "editor";
  static const String EDITOR_VIEW = "editorView";
  static const String EDITOR_ORDER = "editorOrder";
  static const String EDITOR_ORDER_VIEW = "editorOrderView";
  static const String CLEANING_CREW = "cleaningCrew";
  static const String RECEPTIONIST = "receptionist";
  static const String CLEANING_BLOCKED = "cleaningBlocked";
  static const String UNIT_MANAGER = "unitManager";
  static const String UNIT_EDITOR = "unitEditor";
  static const String UNIT_EDITOR_VIEW = "unitEditorView";
  static const String APPROVER = "approver";
  static const String APPROVED = "approved";
  static const String INVITED = "invited";
  static const String APP_LINKS_SENT = "appLinksSent";
  static const String FOOD = "food";
  static const String FORM = "form";
  static const String ORDERED_AT = "ordered_at";
  static const String CREATED_AT = "created_at";
  static const String LAST_SIGN_IN_AT = "last_sign_in_at";

  /// Help is keyed by field, so it survives column reloads and reordering.
  static Map<String, String> get columnHelp => {
        MANAGER: UserStrings.administratorHelp,
        EDITOR: UserStrings.editorHelp,
        EDITOR_VIEW: UserStrings.readOnlyHelp,
        EDITOR_ORDER: UserStrings.editOrdersHelp,
        EDITOR_ORDER_VIEW: UserStrings.readOrdersHelp,
        UNIT_MANAGER: UserStrings.unitAdministratorHelp,
        UNIT_EDITOR: UserStrings.unitEditorHelp,
        UNIT_EDITOR_VIEW: UserStrings.unitReadOnlyHelp,
        APPROVER: UserStrings.approverHelp,
        APPROVED: UserStrings.approvedHelp,
        RECEPTIONIST: UserStrings.receptionistHelp,
        CLEANING_CREW: UserStrings.cleaningCrewHelp,
        CLEANING_BLOCKED: UserStrings.cleaningBlockedHelp,
        IS_VOLUNTEER: UserStrings.volunteerHelp,
        INVITED: UserStrings.invitedHelp,
      };

  static Map<String, dynamic> get columnBuilders => {
        ID: [
          TrinaColumn(
            hide: true,
            title: UserStrings.id,
            field: ID,
            type: TrinaColumnType.text(),
            readOnly: true,
            width: 50,
          ),
        ],
        UNIT: [
          TrinaColumn(
            hide: true,
            title: UserStrings.unit,
            field: UNIT,
            type: TrinaColumnType.number(),
            readOnly: true,
            width: 50,
          ),
        ],
        EMAIL: [
          TrinaColumn(
            title: UserStrings.email,
            field: EMAIL,
            type: TrinaColumnType.text(),
            checkReadOnly: (row, cell) => row.cells[ID]?.value != null,
            width: 200,
          ),
        ],
        NAME: [
          TrinaColumn(
            title: UserStrings.name,
            enableEditingMode: RightsService.canUpdateUsers(),
            field: NAME,
            type: TrinaColumnType.text(),
            width: 120,
            renderer: (rendererContext) {
              final ownerName = rendererContext
                      .row.cells[COMPANION_OWNER]?.value
                      ?.toString()
                      .trim() ??
                  '';
              final managedNames = (rendererContext
                          .row.cells[MANAGED_COMPANION_NAMES]?.value as List?)
                      ?.whereType<String>()
                      .toList(growable: false) ??
                  const <String>[];
              final tooltip = ownerName.isNotEmpty
                  ? UserStrings.companionManagedBy(ownerName)
                  : managedNames.isNotEmpty
                      ? UserStrings.companionManages(managedNames.join(', '))
                      : null;
              return Row(children: [
                Expanded(
                  child: Text(
                    rendererContext.row.cells[NAME]?.value?.toString() ?? '',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (tooltip != null)
                  Tooltip(
                    message: tooltip,
                    child: const Padding(
                      padding: EdgeInsets.only(left: 4),
                      child: Icon(Icons.link, size: 16),
                    ),
                  ),
              ]);
            },
          ),
        ],
        SURNAME: [
          TrinaColumn(
            title: UserStrings.surname,
            enableEditingMode: RightsService.canUpdateUsers(),
            field: SURNAME,
            type: TrinaColumnType.text(),
            width: 120,
          ),
        ],
        GROUP: [
          TrinaColumn(
            title: UserStrings.group,
            field: GROUP,
            type: TrinaColumnType.text(),
            readOnly: true,
            width: 160,
          ),
        ],
        COMPANION_OWNER: [
          TrinaColumn(
            title: UserStrings.companionOf,
            field: COMPANION_OWNER,
            type: TrinaColumnType.text(),
            readOnly: true,
            width: 180,
          ),
        ],
        SEX: [
          TrinaColumn(
            title: UserStrings.sex,
            enableEditingMode: RightsService.canUpdateUsers(),
            field: SEX,
            type: TrinaColumnType.select(UserInfoModel.sexes,
                defaultValue: UserInfoModel.sexes.first),
            formatter: (value) => DataGridHelper.textTransform(
                value, UserInfoModel.sexes, UserInfoModel.sexToLocale),
            applyFormatterInEditing: true,
            width: 100,
          ),
        ],
        PHONE: [
          TrinaColumn(
            title: UserStrings.phone,
            enableEditingMode: RightsService.canUpdateUsers(),
            field: PHONE,
            type: TrinaColumnType.text(),
            width: 100,
          ),
        ],
        BIRTHDAY: [
          TrinaColumn(
            title: UserStrings.birthday,
            enableEditingMode: RightsService.canUpdateUsers(),
            field: BIRTHDAY,
            type: TrinaColumnType.date(defaultValue: DateTime.now()),
            width: 140,
          ),
        ],
        ROLE: [
          TrinaColumn(
            title: UserStrings.role,
            enableEditingMode: RightsService.canUpdateUsers(),
            field: ROLE,
            type: TrinaColumnType.text(),
            width: 100,
          ),
        ],
        TEXT1: [
          TrinaColumn(
            title: UserStrings.text1,
            enableEditingMode: RightsService.canUpdateUsers(),
            field: TEXT1,
            type: TrinaColumnType.text(),
            width: 100,
          ),
        ],
        TEXT2: [
          TrinaColumn(
            title: UserStrings.text2,
            enableEditingMode: RightsService.canUpdateUsers(),
            field: TEXT2,
            type: TrinaColumnType.text(),
            width: 100,
          ),
        ],
        TEXT3: [
          TrinaColumn(
            title: UserStrings.text3,
            enableEditingMode: RightsService.canUpdateUsers(),
            field: TEXT3,
            type: TrinaColumnType.text(),
            width: 100,
          ),
        ],
        NOTE: [
          TrinaColumn(
            title: UserStrings.note,
            enableEditingMode: RightsService.canUpdateUsers(),
            field: NOTE,
            type: TrinaColumnType.text(),
            width: 200,
          ),
        ],
        DIET: [
          TrinaColumn(
            title: UserStrings.diet,
            enableEditingMode: RightsService.canUpdateUsers(),
            field: DIET,
            type: TrinaColumnType.text(),
            width: 200,
          ),
        ],
        FORM: [
          TrinaColumn(
            title: UserStrings.form,
            field: FORM,
            type: TrinaColumnType.text(),
            readOnly: true,
            width: 200,
          ),
        ],
        ORDERED_AT: [
          TrinaColumn(
            title: UserStrings.orderedAt,
            field: ORDERED_AT,
            type: TrinaColumnType.date(),
            readOnly: true,
            width: 140,
          ),
        ],
        CREATED_AT: [
          TrinaColumn(
            title: UserStrings.createdAt,
            field: CREATED_AT,
            type: TrinaColumnType.date(),
            readOnly: true,
            width: 140,
          ),
        ],
        LAST_SIGN_IN_AT: [
          TrinaColumn(
            title: UserStrings.lastSignInAt,
            field: LAST_SIGN_IN_AT,
            type: TrinaColumnType.date(),
            readOnly: true,
            width: 140,
          ),
        ],
        FOOD: (Map<String, dynamic> data) {
          if (data[FOOD] == null) {
            return <TrinaColumn>[];
          }
          var columns = <TrinaColumn>[];
          for (var f in (data[FOOD]) as List<ServiceItemModel>) {
            var cc =
                _foodColumn(f.title!, DbOccasions.serviceTypeFood + f.code);
            columns.add(cc);
          }
          return columns;
        },
        ACCOMMODATION: (Map<String, dynamic> data) {
          final items = List<ServiceItemModel>.from(
            data[DbOccasions.serviceTypeAccommodation] ?? const [],
          );
          final labels = {
            for (final item in items)
              item.code: [
                if (item.title?.trim().isNotEmpty == true) item.title!.trim(),
                if (item.placeTitle?.trim().isNotEmpty == true &&
                    item.placeTitle!.trim() != item.title?.trim())
                  item.placeTitle!.trim(),
              ].join(' — '),
          };
          final select = <String>["", ...items.map((item) => item.code)];
          String labelFor(dynamic code) {
            if (code == null || code.toString().isEmpty) return "—";
            final title = labels[code];
            return title == null || title.isEmpty
                ? code.toString()
                : '$title (${code.toString()})';
          }

          return [
            TrinaColumn(
              title: UserStrings.accommodation,
              field: ACCOMMODATION,
              type: TrinaColumnType.select<String>(
                select,
                itemToString: labelFor,
                menuItemBuilder: (code) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(labelFor(code)),
                  ),
                ),
              ),
              formatter: labelFor,
              applyFormatterInEditing: true,
              enableEditingMode: RightsService.canUpdateUsers(),
              width: 190,
            )
          ];
        },
        IS_VOLUNTEER: [_statusColumn(UserStrings.volunteer, IS_VOLUNTEER)],
        MANAGER: [_statusColumn(UserStrings.administrator, MANAGER)],
        EDITOR: [_statusColumn(UserStrings.editor, EDITOR)],
        EDITOR_VIEW: [_statusColumn(UserStrings.readOnly, EDITOR_VIEW)],
        EDITOR_ORDER: [_statusColumn(UserStrings.editOrders, EDITOR_ORDER)],
        EDITOR_ORDER_VIEW: [
          _statusColumn(UserStrings.readOrders, EDITOR_ORDER_VIEW)
        ],
        CLEANING_CREW: [_statusColumn(UserStrings.cleaningCrew, CLEANING_CREW)],
        RECEPTIONIST: [_statusColumn(UserStrings.receptionist, RECEPTIONIST)],
        CLEANING_BLOCKED: [
          _statusColumn(UserStrings.cleaningBlocked, CLEANING_BLOCKED)
        ],
        UNIT_MANAGER: [
          _statusColumn(UserStrings.administrator, UNIT_MANAGER,
              canUpdateUser: RightsService.canUpdateUnitUsers)
        ],
        UNIT_EDITOR: [
          _statusColumn(UserStrings.editor, UNIT_EDITOR,
              canUpdateUser: RightsService.canUpdateUnitUsers)
        ],
        UNIT_EDITOR_VIEW: [
          _statusColumn(UserStrings.readOnly, UNIT_EDITOR_VIEW,
              canUpdateUser: RightsService.canUpdateUnitUsers)
        ],
        APPROVER: [_statusColumn(UserStrings.approver, APPROVER)],
        APPROVED: [_statusColumn(UserStrings.approved, APPROVED)],
        INVITED: [
          _statusColumn(
            UserStrings.invited,
            INVITED,
            canUpdateUser: () => false,
            readOnly: true,
          )
        ],
        APP_LINKS_SENT: [
          _statusColumn(
            UserStrings.appLinksSent,
            APP_LINKS_SENT,
            canUpdateUser: () => false,
          )
        ],
      };

  static List<TrinaColumn> generateColumns(List<String> identifiers,
      {Map<String, dynamic>? data}) {
    return identifiers
        .where((id) => columnBuilders.containsKey(id))
        .expand((id) {
      var columnEntry = columnBuilders[id];
      if (columnEntry is List<TrinaColumn>) {
        return columnEntry;
      } else if (columnEntry is Function) {
        return (columnEntry(data ?? {}) as List<TrinaColumn>);
      }
      return <TrinaColumn>[];
    }).toList();
  }

  static TrinaColumn _statusColumn(String title, String field,
      {bool Function()? canUpdateUser, bool readOnly = false}) {
    return TrinaColumn(
      title: title,
      field: field,
      type: TrinaColumnType.text(),
      applyFormatterInEditing: true,
      enableEditingMode: false,
      readOnly: readOnly,
      width: 100,
      renderer: (rendererContext) => DataGridHelper.checkBoxRenderer(
          rendererContext,
          field,
          canUpdateUser ?? RightsService.canUpdateUsers),
    );
  }

  static TrinaColumn _foodColumn(String title, String field) {
    return TrinaColumn(
      title: title,
      field: field,
      type: TrinaColumnType.text(),
      applyFormatterInEditing: true,
      enableEditingMode: false,
      cellPadding: EdgeInsets.all(0),
      width: 100,
      renderer: (rendererContext) => DataGridHelper.foodCheckBoxRenderer(
          rendererContext, field, RightsService.canUpdateUsers),
    );
  }
}
