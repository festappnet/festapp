// file: lib/helpers/csv_import_helper.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fstapp/components/features/feature_service.dart';
import 'package:fstapp/components/features/features_strings.dart';
import 'package:fstapp/components/users/occasion_user_model.dart';
import 'package:fstapp/database_tables/tb.dart';
import 'package:fstapp/components/users/db_users.dart';
import 'package:fstapp/services/dialog_helper.dart';
import 'package:fstapp/components/import/import_strings.dart';
import 'package:fstapp/components/users/import_helper.dart';
import 'package:fstapp/services/toast_helper.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/theme_config.dart';

class CsvImportHelper {
  static const String payloadUserId = 'user_id';
  static const String payloadData = 'data';
  static const String payloadGroupTitle = 'group_title';
  static const String payloadDeliveryEmail = 'email_delivery';

  static Future<void> importFromCsv(BuildContext context) async {
    // Replaced the direct file picker with a dialog that allows drag-and-drop.
    var file = await DialogHelper.dropFilesHere(
        context,
        FeaturesStrings.labelImportFromCsv,
        CommonStrings.import,
        CommonStrings.storno,
        headerContent: buildCsvFormatInfo(context));

    if (file == null) return; // User canceled the dialog

    var users = await ImportHelper.getUsersFromFile(file);
    var addOrUpdateUsers = users
        .where((element) =>
            element[Tb.occasion_users.data_text4]?.toLowerCase() != "storno")
        .toList();
    var deleteUsers = users
        .where((element) =>
            element[Tb.occasion_users.data_text4]?.toLowerCase() == "storno")
        .toList();

    var proceed = await DialogHelper.showConfirmationDialog(
      context,
      FeaturesStrings.labelImportFromCsv,
      "${CommonStrings.users} (${users.length}):\n${users.map((value) => value[Tb.occasion_users.data_email]).toList().join(",\n")}",
      confirmButtonMessage: CommonStrings.proceed,
    );

    if (!proceed) return;

    // Use the same complete, canonical payload as the users editor. A direct
    // PostgREST occasion_users select is capped at 1000 rows and does not
    // overlay user_info.email_readonly, so it cannot safely classify imports.
    var existingUsers = (await DbUsers.getOccasionEditorDataBundle()).users;
    final reconciledUsers =
        reconcileAccountEmails(addOrUpdateUsers, existingUsers);
    var toBeCreated = getUsersToBeCreated(reconciledUsers, existingUsers);
    var toBeUpdated = getUsersToBeUpdated(reconciledUsers, existingUsers);
    var toBeDeleted =
        _getUsersToBeDeleted(deleteUsers, reconciledUsers, existingUsers);

    final createApproved = await _confirmCreateUsers(context, toBeCreated);
    final updateApproved = await _confirmUpdateUsers(context, toBeUpdated);
    final deleteApproved = await _confirmDeleteUsers(context, toBeDeleted);

    final createdEmails = toBeCreated
        .map((user) => user[Tb.occasion_users.data_email] as String)
        .toSet();
    final updatedEmails = toBeUpdated
        .map((user) => user[Tb.occasion_users.data_email] as String)
        .toSet();
    final acceptedUsers = reconciledUsers.where((user) {
      final email = user[Tb.occasion_users.data_email] as String;
      if (createdEmails.contains(email) && !createApproved) return false;
      if (updatedEmails.contains(email) && !updateApproved) return false;
      return createdEmails.contains(email) ||
          updatedEmails.contains(email) ||
          user.containsKey(ImportHelper.groupColumn);
    });
    final importRows = buildImportRows(acceptedUsers, existingUsers);
    final deleteIds = deleteApproved
        ? toBeDeleted.map((user) => user.user!).toList()
        : <String>[];

    if (importRows.isEmpty && deleteIds.isEmpty) return;

    await DialogHelper.showProgressDialogAsync(
      context,
      FeaturesStrings.labelImportFromCsv,
      1,
      futures: [
        () => DbUsers.importOccasionUsersFromCsv(importRows, deleteIds),
      ],
    );
  }

  @visibleForTesting
  static List<Map<String, dynamic>> buildImportRows(
      Iterable<Map<String, dynamic>> importedUsers,
      List<OccasionUserModel> existingUsers) {
    final reconciledUsers =
        reconcileAccountEmails(importedUsers, existingUsers);
    final existingByEmail = _existingByEmail(existingUsers);
    return reconciledUsers.map((imported) {
      final email = _normalizedEmail(
        imported[Tb.occasion_users.data_email],
      );
      final existing = existingByEmail[email];
      final dataPatch = Map<String, dynamic>.from(imported)
        ..remove(ImportHelper.groupColumn)
        ..remove(ImportHelper.deliveryEmailField)
        ..remove(Tb.occasion_users.services);

      return <String, dynamic>{
        payloadUserId: existing?.user,
        payloadDeliveryEmail: imported[ImportHelper.deliveryEmailField],
        payloadData: dataPatch,
        if (imported.containsKey(Tb.occasion_users.services))
          Tb.occasion_users.services: imported[Tb.occasion_users.services],
        if (imported.containsKey(ImportHelper.groupColumn))
          payloadGroupTitle: imported[ImportHelper.groupColumn],
      };
    }).toList();
  }

  /// Reuses the canonical account identity for a person already imported from
  /// a shared mailbox and allocates collision-free +N aliases for new people.
  /// Matching includes the normalized delivery mailbox, name and surname so a
  /// partial reimport cannot update the first person who shares the address.
  @visibleForTesting
  static List<Map<String, dynamic>> reconcileAccountEmails(
      Iterable<Map<String, dynamic>> importedUsers,
      List<OccasionUserModel> existingUsers) {
    final result =
        importedUsers.map((user) => Map<String, dynamic>.from(user)).toList();
    final usedAccountEmails = existingUsers
        .map((user) =>
            _normalizedEmail(user.data?[Tb.occasion_users.data_email]))
        .where((email) => email.isNotEmpty)
        .toSet();
    final existingByIdentity = <String, OccasionUserModel>{};
    for (final existing in existingUsers) {
      final data = existing.data ?? const <String, dynamic>{};
      final accountEmail = _normalizedEmail(data[Tb.occasion_users.data_email]);
      if (accountEmail.isEmpty) continue;
      final explicitDelivery =
          _normalizedEmail(data[ImportHelper.deliveryEmailField]);
      final deliveryEmail = explicitDelivery.isNotEmpty
          ? explicitDelivery
          : _removeNumericAlias(accountEmail);
      final key = _identityKey(deliveryEmail, data);
      if (existingByIdentity.containsKey(key)) {
        throw const FormatException(
          'Existing people sharing an email address are ambiguous.',
        );
      }
      existingByIdentity[key] = existing;
    }

    final unmatchedByDelivery = <String, List<Map<String, dynamic>>>{};
    for (final imported in result) {
      final deliveryEmail = _normalizedEmail(
        imported[ImportHelper.deliveryEmailField] ??
            imported[Tb.occasion_users.data_email],
      );
      imported[ImportHelper.deliveryEmailField] = deliveryEmail;
      final existing =
          existingByIdentity[_identityKey(deliveryEmail, imported)];
      if (existing != null) {
        imported[Tb.occasion_users.data_email] = _normalizedEmail(
          existing.data?[Tb.occasion_users.data_email],
        );
      } else {
        unmatchedByDelivery.putIfAbsent(deliveryEmail, () => []).add(imported);
      }
    }

    final reservedDeliveryEmails = result
        .map((user) => user[ImportHelper.deliveryEmailField] as String)
        .toSet();
    final deliveries = unmatchedByDelivery.keys.toList()..sort();
    for (final deliveryEmail in deliveries) {
      final users = unmatchedByDelivery[deliveryEmail]!
        ..sort((first, second) => _identityKey(deliveryEmail, first)
            .compareTo(_identityKey(deliveryEmail, second)));
      var suffix = 0;
      for (final user in users) {
        var candidate = suffix == 0
            ? deliveryEmail
            : _withNumericAlias(deliveryEmail, suffix);
        while (usedAccountEmails.contains(candidate) ||
            (candidate != deliveryEmail &&
                reservedDeliveryEmails.contains(candidate))) {
          candidate = _withNumericAlias(deliveryEmail, ++suffix);
        }
        user[Tb.occasion_users.data_email] = candidate;
        usedAccountEmails.add(candidate);
        suffix++;
      }
    }
    return result;
  }

  // Helper to get users to be created
  @visibleForTesting
  static List<Map<String, dynamic>> getUsersToBeCreated(
      Iterable<Map<String, dynamic>> users,
      List<OccasionUserModel> existingUsers) {
    final existingByEmail = _existingByEmail(existingUsers);
    return users
        .where((user) => !existingByEmail.containsKey(
              _normalizedEmail(user[Tb.occasion_users.data_email]),
            ))
        .toList();
  }

  // Helper to get users to be updated
  @visibleForTesting
  static List<Map<String, dynamic>> getUsersToBeUpdated(
      Iterable<Map<String, dynamic>> users,
      List<OccasionUserModel> existingUsers) {
    final existingByEmail = _existingByEmail(existingUsers);
    return users.where((u) {
      final existing =
          existingByEmail[_normalizedEmail(u[Tb.occasion_users.data_email])];
      return existing != null && !existing.importedEquals(u);
    }).toList();
  }

  // Helper to get users to be deleted
  static List<OccasionUserModel> _getUsersToBeDeleted(
      Iterable<Map<String, dynamic>> deleteUsers,
      Iterable<Map<String, dynamic>> addOrUpdateUsers,
      List<OccasionUserModel> existingUsers) {
    final existingByEmail = _existingByEmail(existingUsers);
    final retainedEmails = addOrUpdateUsers
        .map((user) => _normalizedEmail(
              user[Tb.occasion_users.data_email],
            ))
        .toSet();
    return deleteUsers
        .map((u) {
          final email = _normalizedEmail(u[Tb.occasion_users.data_email]);
          final existing = existingByEmail[email];
          return existing != null && !retainedEmails.contains(email)
              ? existing
              : null;
        })
        .nonNulls
        .toList();
  }

  static String _normalizedEmail(Object? value) =>
      value?.toString().trim().toLowerCase() ?? '';

  static String _identityKey(String deliveryEmail, Map<String, dynamic> data) {
    String normalize(Object? value) =>
        value?.toString().trim().toLowerCase() ?? '';
    return [
      deliveryEmail,
      normalize(data[Tb.occasion_users.data_surname]),
      normalize(data[Tb.occasion_users.data_name]),
    ].join('\u0000');
  }

  static String _removeNumericAlias(String email) {
    final at = email.lastIndexOf('@');
    if (at <= 0) return email;
    final local = email.substring(0, at);
    final withoutAlias = local.replaceFirst(RegExp(r'\+[0-9]+$'), '');
    return '$withoutAlias${email.substring(at)}';
  }

  static String _withNumericAlias(String email, int suffix) {
    final at = email.lastIndexOf('@');
    if (at <= 0 || at == email.length - 1) {
      throw const FormatException('Invalid email address in CSV import.');
    }
    return '${email.substring(0, at)}+$suffix${email.substring(at)}';
  }

  static Map<String, OccasionUserModel> _existingByEmail(
      Iterable<OccasionUserModel> users) {
    final result = <String, OccasionUserModel>{};
    for (final user in users) {
      final email = _normalizedEmail(
        user.data?[Tb.occasion_users.data_email],
      );
      if (email.isNotEmpty) result.putIfAbsent(email, () => user);
    }
    return result;
  }

  static Future<bool> _confirmCreateUsers(
      BuildContext context, List<Map<String, dynamic>> toBeCreated) async {
    if (toBeCreated.isEmpty) return true;

    var proceed = await DialogHelper.showConfirmationDialog(
      context,
      ImportStrings.creatingUsers,
      "${ImportStrings.createUsersConfirm}\n${CommonStrings.users} (${toBeCreated.length}):\n${toBeCreated.map((u) => u[Tb.occasion_users.data_email]).join(",\n")}",
      confirmButtonMessage: CommonStrings.proceed,
    );

    if (!proceed) return false;

    return true;
  }

  static Future<bool> _confirmUpdateUsers(
      BuildContext context, List<Map<String, dynamic>> toBeUpdated) async {
    if (toBeUpdated.isEmpty) return true;

    var proceed = await DialogHelper.showConfirmationDialog(
      context,
      ImportStrings.updatingUsers,
      "${ImportStrings.updateUsersConfirm}\n${CommonStrings.users} (${toBeUpdated.length}):\n${toBeUpdated.map((u) => u[Tb.occasion_users.data_email]).join(",\n")}",
      confirmButtonMessage: CommonStrings.proceed,
    );

    if (!proceed) return false;

    return true;
  }

  /// Builds a collapsed help section (shown above the drop area) that, when
  /// expanded, lists every recognised column: its exact header text (as
  /// required in the CSV) and a translatable explanation. Kept collapsed by
  /// default so the drop/import area stays the focus. Accommodation, food and
  /// diet columns are only listed when the corresponding services setting is
  /// enabled, so the description matches what the event actually uses.
  static Widget buildCsvFormatInfo(BuildContext context) {
    final theme = Theme.of(context);
    final headers = ImportHelper.migrateColumns;

    final columns = <_CsvColumnInfo>[
      _CsvColumnInfo(Tb.occasion_users.data_email, FeaturesStrings.csvColEmail,
          isRequired: true),
      _CsvColumnInfo(Tb.occasion_users.data_name, FeaturesStrings.csvColName,
          isRequired: true),
      _CsvColumnInfo(
          Tb.occasion_users.data_surname, FeaturesStrings.csvColSurname,
          isRequired: true),
      _CsvColumnInfo(Tb.occasion_users.data_sex, FeaturesStrings.csvColSex),
      _CsvColumnInfo(Tb.occasion_users.data_phone, FeaturesStrings.csvColPhone),
      _CsvColumnInfo(Tb.occasion_users.data_text1, FeaturesStrings.csvColText1),
      _CsvColumnInfo(Tb.occasion_users.data_text2, FeaturesStrings.csvColText2),
      _CsvColumnInfo(
          Tb.occasion_users.data_birthDate, FeaturesStrings.csvColBirthDate),
      _CsvColumnInfo(Tb.occasion_users.data_note, FeaturesStrings.csvColNote),
      if (FeatureService.isServiceFoodEnabled())
        _CsvColumnInfo(Tb.occasion_users.data_diet, FeaturesStrings.csvColDiet),
      if (FeatureService.isServiceFoodEnabled())
        _CsvColumnInfo(
            Tb.occasion_users.services_food, FeaturesStrings.csvColFood),
      if (FeatureService.isServiceAccommodationEnabled())
        _CsvColumnInfo(Tb.occasion_users.services_accommodation,
            FeaturesStrings.csvColAccommodation),
      _CsvColumnInfo(ImportHelper.groupColumn, FeaturesStrings.csvColGroup),
    ];

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      // Collapsed by default: a slim "show more" help row above the drop area.
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 8.0),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          leading: Icon(Icons.help_outline, color: theme.colorScheme.primary),
          title: Text(
            FeaturesStrings.csvFormatTitle,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          children: [
            Text(
              FeaturesStrings.csvFormatIntro,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => _copyToClipboard(
                  context,
                  // Tab-separated so pasting splits into columns in a spreadsheet.
                  columns
                      .map((c) => headers[c.headerKey] ?? c.headerKey)
                      .join('\t'),
                ),
                icon: const Icon(Icons.copy, size: 16),
                label: Text(FeaturesStrings.csvCopyHeader),
              ),
            ),
            const SizedBox(height: 12),
            for (final col in columns)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 2,
                      children: [
                        // The chip is tappable to copy this single header value.
                        Tooltip(
                          message: FeaturesStrings.csvCopyTooltip,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(4),
                            onTap: () => _copyToClipboard(context,
                                headers[col.headerKey] ?? col.headerKey),
                            child: Container(
                              padding: const EdgeInsets.fromLTRB(6, 2, 4, 2),
                              decoration: BoxDecoration(
                                color: ThemeConfig.grey200(context),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    headers[col.headerKey] ?? col.headerKey,
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(Icons.copy,
                                      size: 13,
                                      color: ThemeConfig.grey700(context)),
                                ],
                              ),
                            ),
                          ),
                        ),
                        if (col.isRequired)
                          Text(
                            "• ${FeaturesStrings.csvFormatRequired}",
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      col.explanation,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: ThemeConfig.grey700(context)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Copies [text] to the clipboard and shows a confirmation toast.
  static void _copyToClipboard(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    ToastHelper.Show(context, FeaturesStrings.csvCopiedToast,
        severity: ToastSeverity.Ok);
  }

  static Future<bool> _confirmDeleteUsers(
      BuildContext context, List<OccasionUserModel> toBeDeleted) async {
    if (toBeDeleted.isEmpty) return true;

    var proceed = await DialogHelper.showConfirmationDialog(
      context,
      ImportStrings.removingUsers,
      "${ImportStrings.removeUsersConfirm}\n${CommonStrings.users} (${toBeDeleted.length}):\n${toBeDeleted.map((u) => u.toBasicString()).join(",\n")}",
      confirmButtonMessage: CommonStrings.proceed,
    );

    return proceed;
  }
}

/// One recognised CSV column: which header it maps to and how to explain it.
class _CsvColumnInfo {
  /// Key into [ImportHelper.migrateColumns] that yields the literal header text.
  final String headerKey;

  /// Translatable, human-readable explanation of the column's value.
  final String explanation;

  /// Whether the import fails without this column.
  final bool isRequired;

  const _CsvColumnInfo(this.headerKey, this.explanation,
      {this.isRequired = false});
}
