import '../../support/fixtures/localization_log_fixture.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/import/csv_import_helper.dart';
import 'package:fstapp/components/occasion/db_occasions.dart';
import 'package:fstapp/components/users/import_helper.dart';
import 'package:fstapp/components/users/occasion_user_model.dart';
import 'package:fstapp/components/users/db_users.dart';
import 'package:fstapp/components/users/user_columns.dart';
import 'package:fstapp/database_tables/tb.dart';

void main() {
  // This suite intentionally uses untranslated key fallback (no catalog).
  setUp(() {
    final logs = LocalizationLogFixture.install(expectedMissingCatalog: true);
    addTearDown(logs.dispose);
  });
  OccasionUserModel existingBujnmiUser() => OccasionUserModel(
        occasion: 42,
        user: 'existing-user',
        role: 2,
        isEditorView: true,
        isCleaningCrew: true,
        data: {
          Tb.occasion_users.data_email: 'bujnmi@gmail.com',
          Tb.occasion_users.data_name: 'Bujn',
          Tb.occasion_users.data_surname: 'Mi',
          Tb.occasion_users.data_sex: 'male',
          Tb.occasion_users.data_note: 'Původní poznámka',
        },
        services: {
          DbOccasions.serviceTypeAccommodation: {
            'room-a': DbOccasions.servicePaid,
          },
          DbOccasions.serviceTypeFood: {
            'lunch': DbOccasions.servicePaid,
          },
        },
      );

  Map<String, dynamic> fixture(String path) => ImportHelper.getUsersFromCsv(
        File(path).readAsStringSync(),
      ).single;

  test('CSV import reads the optional group column', () {
    final users = ImportHelper.getUsersFromCsv(
      'E-mailová adresa,Jméno:,Příjmení:,Skupina\r\n'
      'JAN@example.com,Jan,Novák, Modří ',
    );

    expect(users, hasLength(1));
    expect(users.single[Tb.occasion_users.data_email], 'jan@example.com');
    expect(users.single[ImportHelper.groupColumn], 'Modří');
  });

  test('CSV import keeps working without the optional group column', () {
    final users = ImportHelper.getUsersFromCsv(
      'E-mailová adresa,Jméno:,Příjmení:\n'
      'jan@example.com,Jan,Novák',
    );

    expect(users, hasLength(1));
    expect(users.single, isNot(contains(ImportHelper.groupColumn)));
  });

  test('CSV import accepts a UTF-8 BOM and surrounding header whitespace', () {
    final users = ImportHelper.getUsersFromCsv(
      '\ufeffE-mailová adresa, Jméno: , Příjmení: \n'
      'jan@example.com,Jan,Novák',
    );

    expect(users.single[Tb.occasion_users.data_email], 'jan@example.com');
  });

  test('CSV import rejects an empty file instead of crashing', () {
    expect(() => ImportHelper.getUsersFromCsv(''), throwsFormatException);
  });

  test('CSV import rejects duplicate required headers', () {
    expect(
      () => ImportHelper.getUsersFromCsv(
        'E-mailová adresa,E-mailová adresa,Jméno:,Příjmení:\n'
        'one@example.com,two@example.com,Jan,Novák',
      ),
      throwsFormatException,
    );
  });

  test('CSV import rejects a short non-empty row atomically', () {
    expect(
      () => ImportHelper.getUsersFromCsv(
        'E-mailová adresa,Jméno:,Příjmení:,Poznámka:\n'
        'jan@example.com,Jan',
      ),
      throwsFormatException,
    );
  });

  test('CSV import rejects blank required values and malformed emails', () {
    for (final row in [
      'not-an-email,Jan,Novák',
      'jan@example.com,,Novák',
      'jan@example.com,Jan,',
    ]) {
      expect(
        () => ImportHelper.getUsersFromCsv(
          'E-mailová adresa,Jméno:,Příjmení:\n$row',
        ),
        throwsFormatException,
      );
    }
  });

  test('CSV import ignores completely blank trailing rows', () {
    final users = ImportHelper.getUsersFromCsv(
      'E-mailová adresa,Jméno:,Příjmení:\n'
      'jan@example.com,Jan,Novák\n,,',
    );

    expect(users, hasLength(1));
  });

  test('CSV import autodetects semicolons, CRLF and quoted delimiters', () {
    final users = ImportHelper.getUsersFromCsv(
      'E-mailová adresa;Jméno:;Příjmení:;Poznámka:\r\n'
      'jan@example.com;Jan;Novák;"Poznámka; s oddělovačem"',
    );

    expect(
        users.single[Tb.occasion_users.data_note], 'Poznámka; s oddělovačem');
  });

  test('CSV import rejects impossible calendar dates', () {
    expect(
      () => ImportHelper.getUsersFromCsv(
        'E-mailová adresa,Jméno:,Příjmení:,Datum narození:\n'
        'jan@example.com,Jan,Novák,31.2.2026',
      ),
      throwsFormatException,
    );
  });

  test('CSV import preserves duplicate delivery emails with sign-in aliases',
      () {
    final users = ImportHelper.getUsersFromCsv(
      'E-mailová adresa,Jméno:,Příjmení:\n'
      'shared@example.com,Klára,Vomelová\n'
      'shared@example.com,Marie,Vomelová',
    );

    expect(users, hasLength(2));
    expect(
      users.map((user) => user[Tb.occasion_users.data_email]),
      ['shared@example.com', 'shared+1@example.com'],
    );
    expect(
      users.map((user) => user[ImportHelper.deliveryEmailField]),
      everyElement('shared@example.com'),
    );
  });

  test('CSV aliases do not collide with another real delivery address', () {
    final users = ImportHelper.getUsersFromCsv(
      'E-mailová adresa,Jméno:,Příjmení:\n'
      'shared@example.com,Klára,Vomelová\n'
      'shared+1@example.com,Petr,Novák\n'
      'shared@example.com,Marie,Vomelová',
    );

    expect(
      users.map((user) => user[Tb.occasion_users.data_email]),
      ['shared@example.com', 'shared+1@example.com', 'shared+2@example.com'],
    );
  });

  test('CSV aliases stay attached to people when duplicate rows are reordered',
      () {
    final firstOrder = ImportHelper.getUsersFromCsv(
      'E-mailová adresa,Jméno:,Příjmení:\n'
      'shared@example.com,Klára,Vomelová\n'
      'shared@example.com,Marie,Vomelová',
    );
    final reversedOrder = ImportHelper.getUsersFromCsv(
      'E-mailová adresa,Jméno:,Příjmení:\n'
      'shared@example.com,Marie,Vomelová\n'
      'shared@example.com,Klára,Vomelová',
    );

    Map<String, String> aliasesByName(List<Map<String, dynamic>> users) => {
          for (final user in users)
            user[Tb.occasion_users.data_name] as String:
                user[Tb.occasion_users.data_email] as String,
        };
    expect(aliasesByName(reversedOrder), aliasesByName(firstOrder));
  });

  test('partial reimport of a shared mailbox keeps the same person identity',
      () {
    final original = ImportHelper.getUsersFromCsv(
      'E-mailová adresa,Jméno:,Příjmení:\n'
      'shared@example.com,Klára,Vomelová\n'
      'shared@example.com,Marie,Vomelová',
    );
    final existing = original
        .map((row) => OccasionUserModel(
              user: row[Tb.occasion_users.data_name] == 'Klára'
                  ? 'user-klara'
                  : 'user-marie',
              data: Map<String, dynamic>.from(row),
            ))
        .toList();
    final partial = ImportHelper.getUsersFromCsv(
      'E-mailová adresa,Jméno:,Příjmení:\n'
      'shared@example.com,Marie,Vomelová',
    );

    final rows = CsvImportHelper.buildImportRows(partial, existing);

    expect(rows, hasLength(1));
    expect(rows.single[CsvImportHelper.payloadUserId], 'user-marie');
    expect(
      (rows.single[CsvImportHelper.payloadData]
          as Map<String, dynamic>)[Tb.occasion_users.data_email],
      'shared+1@example.com',
    );
  });

  test('a later person sharing a mailbox receives the next free alias', () {
    final existing = [
      OccasionUserModel(user: 'user-klara', data: {
        Tb.occasion_users.data_email: 'shared@example.com',
        Tb.occasion_users.data_name: 'Klára',
        Tb.occasion_users.data_surname: 'Vomelová',
      }),
      OccasionUserModel(user: 'user-marie', data: {
        Tb.occasion_users.data_email: 'shared+1@example.com',
        Tb.occasion_users.data_name: 'Marie',
        Tb.occasion_users.data_surname: 'Vomelová',
      }),
    ];
    final imported = ImportHelper.getUsersFromCsv(
      'E-mailová adresa,Jméno:,Příjmení:\n'
      'shared@example.com,Tereza,Vomelová',
    );

    final rows = CsvImportHelper.buildImportRows(imported, existing);

    expect(rows.single[CsvImportHelper.payloadUserId], isNull);
    expect(
      (rows.single[CsvImportHelper.payloadData]
          as Map<String, dynamic>)[Tb.occasion_users.data_email],
      'shared+2@example.com',
    );
  });

  test('CSV rejects ambiguous people sharing both mailbox and name', () {
    expect(
      () => ImportHelper.getUsersFromCsv(
        'E-mailová adresa,Jméno:,Příjmení:\n'
        'shared@example.com,Jan,Novák\n'
        'shared@example.com,Jan,Novák',
      ),
      throwsFormatException,
    );
  });

  test('prepared files update the same user on the second import', () {
    final first = ImportHelper.getUsersFromCsv(
      File('test/fixtures/bujnmi_group_import_01.csv').readAsStringSync(),
    ).single;
    final updated = ImportHelper.getUsersFromCsv(
      File('test/fixtures/bujnmi_group_import_02_update.csv')
          .readAsStringSync(),
    ).single;
    final withoutGroup = ImportHelper.getUsersFromCsv(
      File('test/fixtures/bujnmi_group_import_03_remove.csv')
          .readAsStringSync(),
    ).single;

    expect(first[Tb.occasion_users.data_email], 'bujnmi@gmail.com');
    expect(updated[Tb.occasion_users.data_email], 'bujnmi@gmail.com');
    expect(first[ImportHelper.groupColumn], 'Testovací skupina CSV');
    expect(
        updated[ImportHelper.groupColumn], 'Přesunutá testovací skupina CSV');
    expect(withoutGroup[ImportHelper.groupColumn], isEmpty);
    expect(OccasionUserModel(data: first).importedEquals(first), isTrue);
    expect(OccasionUserModel(data: first).importedEquals(updated), isFalse);

    final existing = OccasionUserModel(user: 'existing-user', data: first);
    expect(CsvImportHelper.getUsersToBeCreated([updated], [existing]), isEmpty);
    expect(
        CsvImportHelper.getUsersToBeUpdated([updated], [existing]), [updated]);
  });

  test('full editor payload matches existing users beyond row 1000', () {
    final existing = List.generate(
      3135,
      (index) => OccasionUserModel(
        user: 'user-$index',
        data: {
          Tb.occasion_users.data_email: ' person$index@example.com ',
          Tb.occasion_users.data_name: 'Person',
          Tb.occasion_users.data_surname: '$index',
        },
      ),
    );
    final imported = List.generate(
      2431,
      (index) => {
        Tb.occasion_users.data_email: 'PERSON${index + 704}@EXAMPLE.COM',
        Tb.occasion_users.data_name: 'Person',
        Tb.occasion_users.data_surname: '${index + 704}',
        ImportHelper.groupColumn: 'Skupina ${index % 20}',
      },
    );

    expect(
      CsvImportHelper.getUsersToBeCreated(imported, existing),
      isEmpty,
    );
    final rows = CsvImportHelper.buildImportRows(imported, existing);
    expect(rows, hasLength(2431));
    expect(rows.first[CsvImportHelper.payloadUserId], 'user-704');
    expect(rows.last[CsvImportHelper.payloadUserId], 'user-3134');
    expect(rows.every((row) => row[CsvImportHelper.payloadUserId] != null),
        isTrue);
    expect(
      rows.every((row) => row.containsKey(CsvImportHelper.payloadGroupTitle)),
      isTrue,
    );
  });

  test('group-only reimport does not schedule a general user update', () {
    final imported = fixture('test/fixtures/bujnmi_group_only_import.csv');

    expect(imported, isNot(contains(Tb.occasion_users.data_sex)));
    expect(imported, isNot(contains(Tb.occasion_users.services)));
    expect(
      CsvImportHelper.getUsersToBeUpdated(
        [imported],
        [existingBujnmiUser()],
      ),
      isEmpty,
    );
  });

  test('blank optional sex does not hide columns that follow it', () {
    final imported = ImportHelper.getUsersFromCsv(
      'E-mailová adresa,Jméno:,Příjmení:,Jsi:,Ubytování:\n'
      'bujnmi@gmail.com,Bujn,Mi,,room-b',
    ).single;

    expect(imported, isNot(contains(Tb.occasion_users.data_sex)));
    expect(imported[Tb.occasion_users.services], {
      DbOccasions.serviceTypeAccommodation: {
        'room-b': DbOccasions.servicePaid,
      },
    });
  });

  test('present empty accommodation clears only that service family', () {
    final imported = ImportHelper.getUsersFromCsv(
      'E-mailová adresa,Jméno:,Příjmení:,Ubytování:\n'
      'bujnmi@gmail.com,Bujn,Mi,',
    ).single;

    expect(imported[Tb.occasion_users.services], {
      DbOccasions.serviceTypeAccommodation: <String, String>{},
    });
  });

  test('partial reimport sends only fields present in the CSV', () {
    final imported = fixture('test/fixtures/bujnmi_group_import_02_update.csv');
    final row = CsvImportHelper.buildImportRows(
      [imported],
      [existingBujnmiUser()],
    ).single;
    final data = row[CsvImportHelper.payloadData] as Map<String, dynamic>;

    expect(row[CsvImportHelper.payloadUserId], 'existing-user');
    expect(data[Tb.occasion_users.data_note],
        'Druhý import aktualizoval poznámku');
    expect(data, isNot(contains(Tb.occasion_users.data_sex)));
    expect(row, isNot(contains(Tb.occasion_users.services)));
    expect(row, isNot(contains(Tb.occasion_users.role)));
    expect(row, isNot(contains(Tb.occasion_users.is_editor_view)));
    expect(row[CsvImportHelper.payloadGroupTitle],
        'Přesunutá testovací skupina CSV');
  });

  test('import payload separates sign-in and delivery email', () {
    final imported = ImportHelper.getUsersFromCsv(
      'E-mailová adresa,Jméno:,Příjmení:\n'
      'shared@example.com,Klára,Vomelová\n'
      'shared@example.com,Marie,Vomelová',
    );
    final rows = CsvImportHelper.buildImportRows(imported, const []);

    expect(rows[1][CsvImportHelper.payloadDeliveryEmail], 'shared@example.com');
    expect(
      (rows[1][CsvImportHelper.payloadData]
          as Map<String, dynamic>)[Tb.occasion_users.data_email],
      'shared+1@example.com',
    );
    expect(rows[1][CsvImportHelper.payloadData],
        isNot(contains(ImportHelper.deliveryEmailField)));
  });

  test('reimport sends only service families present in CSV', () {
    final imported = ImportHelper.getUsersFromCsv(
      'E-mailová adresa,Jméno:,Příjmení:,Ubytování:\n'
      'bujnmi@gmail.com,Bujn,Mi,room-b',
    ).single;
    final row = CsvImportHelper.buildImportRows(
      [imported],
      [existingBujnmiUser()],
    ).single;

    expect(row[Tb.occasion_users.services], {
      DbOccasions.serviceTypeAccommodation: {
        'room-b': DbOccasions.servicePaid,
      },
    });
  });

  testWidgets('user table exposes the imported group as read only',
      (tester) async {
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (builderContext) {
        context = builderContext;
        return const SizedBox();
      }),
    ));

    final user = OccasionUserModel.fromJson({
      DbUsers.groupTitleKey: 'Testovací skupina CSV',
      Tb.occasion_users.data: <String, dynamic>{},
    });
    final groupColumn = UserColumns.generateColumns([UserColumns.GROUP]).single;

    expect(user.toTrinaRow(context).cells[UserColumns.GROUP]?.value,
        'Testovací skupina CSV');
    expect(groupColumn.readOnly, isTrue);

    final invitedColumn =
        UserColumns.generateColumns([UserColumns.INVITED]).single;
    expect(invitedColumn.readOnly, isTrue);
  });
}
