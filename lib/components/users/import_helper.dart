import 'package:fstapp/services/import_file.dart';
import 'package:csv/csv.dart';
import 'package:fstapp/database_tables/tb.dart';
import 'package:fstapp/components/occasion/db_occasions.dart';
import 'package:intl/intl.dart';

class ImportHelper {
  static const String groupColumn = 'group';
  static const String deliveryEmailField = 'email_delivery';

  static Map<String, String> get migrateColumns => {
    Tb.occasion_users.data_email: "E-mailová adresa",
    Tb.occasion_users.data_sex: "Jsi:",
    Tb.occasion_users.data_name: "Jméno:",
    Tb.occasion_users.data_surname: "Příjmení:",
    Tb.occasion_users.services_accommodation: "Ubytování:",
    Tb.occasion_users.data_phone: "Mobilní telefon:",
    Tb.occasion_users.data_text1: "Typ účastníka:",
    Tb.occasion_users.data_text2: "Přípravný tým:",
    Tb.occasion_users.data_birthDate: "Datum narození:",
    Tb.occasion_users.data_note: "Poznámka:",
    Tb.occasion_users.data_diet: "Stravovací omezení:",
    Tb.occasion_users.services_food: "Stravování:",
    groupColumn: "Skupina:",
  };

  static Future<List<Map<String, dynamic>>> getUsersFromFile(ImportFile file) async {
    final rawData = await file.readAsString();
    return getUsersFromCsv(rawData);
  }

  static List<Map<String, dynamic>> getUsersFromCsv(String rawData) {
    // Imported user fields are text, including phone numbers and postal codes.
    // Keep quoted newlines and let the maintained decoder detect CSV dialects.
    final fields = Csv().decode(rawData);

    if (fields.isEmpty) {
      throw const FormatException('CSV file is empty.');
    }

    List<Map<String, dynamic>> userList = [];

    var firstRow = fields[0].map((e) => e.toString().trim()).toList();
    if (firstRow.isNotEmpty) {
      firstRow[0] = firstRow[0].replaceFirst('\ufeff', '');
    }
    Map<String, int> userColumnIndex = {};
    for (var keyValue in migrateColumns.entries) {
      final matchingIndexes = <int>[
        for (var index = 0; index < firstRow.length; index++)
          if (firstRow[index] == keyValue.value) index,
      ];
      if (matchingIndexes.length > 1) {
        throw FormatException(
          'CSV contains duplicate column ${keyValue.value}.',
        );
      }
      var index = matchingIndexes.isEmpty ? -1 : matchingIndexes.single;
      if (index == -1 && keyValue.key == groupColumn) {
        index = firstRow.indexWhere(
          (header) => header.trim().toLowerCase() == 'skupina',
        );
      }
      if (index == -1) {
        continue;
      }
      userColumnIndex[keyValue.key] = index;
    }

    if (!userColumnIndex.keys.toSet().containsAll([
      Tb.occasion_users.data_email,
      Tb.occasion_users.data_name,
      Tb.occasion_users.data_surname,
    ])) {
      throw const FormatException("Table doesn't contain required columns.");
    }

    for (int r = 1; r < fields.length; r++) {
      if (fields[r].every((value) => value.toString().trim().isEmpty)) {
        continue;
      }
      Map<String, dynamic> userJsonObject = {};
      for (var entry in userColumnIndex.entries) {
        if (entry.value >= fields[r].length) {
          throw FormatException('CSV row ${r + 1} has too few columns.');
        }
        var trimmedString = fields[r][entry.value].toString().trim();
        if (entry.key == Tb.occasion_users.data_email) {
          if (trimmedString.isEmpty) {
            throw FormatException('CSV row ${r + 1} has no email address.');
          }
          trimmedString = _normalizeEmail(trimmedString, r + 1);
        } else if (entry.key == Tb.occasion_users.role) {
          if (trimmedString.isEmpty) {
            continue;
          }
          var role = trimmedString.toLowerCase().startsWith("p") ? 1 : 2;
          userJsonObject[entry.key] = role;
          continue;
        } else if (entry.key == Tb.occasion_users.data_sex) {
          if (trimmedString.isEmpty) {
            continue;
          }
          trimmedString =
              (trimmedString.toLowerCase().startsWith("m") ||
                  trimmedString.toLowerCase().startsWith("k"))
              ? "male"
              : "female";
        } else if (entry.key == Tb.occasion_users.data_birthDate) {
          if (trimmedString.isEmpty) {
            continue;
          }
          final format = DateFormat("d.M.y");
          var dateTime = format.parseStrict(trimmedString);
          userJsonObject[entry.key] = dateTime.toIso8601String();
          continue;
        } else if (entry.key == Tb.occasion_users.services_food) {
          var foodJson = createServicesJson(
            trimmedString,
            DbOccasions.serviceTypeFood,
          );
          userJsonObject[Tb.occasion_users.services] = addJson(
            userJsonObject[Tb.occasion_users.services],
            foodJson,
          );
          continue;
        } else if (entry.key == Tb.occasion_users.services_accommodation) {
          var accommodationJson = createServicesJson(
            trimmedString,
            DbOccasions.serviceTypeAccommodation,
          );
          userJsonObject[Tb.occasion_users.services] = addJson(
            userJsonObject[Tb.occasion_users.services],
            accommodationJson,
          );
          continue;
        }

        userJsonObject[entry.key] = trimmedString;
        continue;
      }
      if (!userJsonObject.keys.toSet().containsAll([
        Tb.occasion_users.data_email,
        Tb.occasion_users.data_name,
        Tb.occasion_users.data_surname,
      ])) {
        throw FormatException('CSV row ${r + 1} is missing required values.');
      }
      if ((userJsonObject[Tb.occasion_users.data_name] as String).isEmpty ||
          (userJsonObject[Tb.occasion_users.data_surname] as String).isEmpty) {
        throw FormatException('CSV row ${r + 1} is missing required values.');
      }
      userList.add(userJsonObject);
    }

    _assignSignInEmails(userList);
    return userList;
  }

  static void _assignSignInEmails(List<Map<String, dynamic>> users) {
    final reservedDeliveryEmails = users
        .map((user) => user[Tb.occasion_users.data_email] as String)
        .toSet();
    final usedSignInEmails = <String>{};

    final usersByDeliveryEmail = <String, List<Map<String, dynamic>>>{};
    for (final user in users) {
      final deliveryEmail = user[Tb.occasion_users.data_email] as String;
      usersByDeliveryEmail.putIfAbsent(deliveryEmail, () => []).add(user);
    }

    final deliveryEmails = usersByDeliveryEmail.keys.toList()..sort();
    for (final deliveryEmail in deliveryEmails) {
      final sharedMailboxUsers = usersByDeliveryEmail[deliveryEmail]!
        ..sort(
          (first, second) =>
              _stableIdentityKey(first).compareTo(_stableIdentityKey(second)),
        );
      final identityKeys = sharedMailboxUsers.map(_stableIdentityKey).toList();
      if (identityKeys.toSet().length != identityKeys.length) {
        throw const FormatException(
          'People sharing an email address need distinct names or a stable ID.',
        );
      }

      var suffix = 0;
      for (final user in sharedMailboxUsers) {
        var signInEmail = suffix == 0
            ? deliveryEmail
            : _withNumericAlias(deliveryEmail, suffix);
        while (usedSignInEmails.contains(signInEmail) ||
            (signInEmail != deliveryEmail &&
                reservedDeliveryEmails.contains(signInEmail))) {
          signInEmail = _withNumericAlias(deliveryEmail, ++suffix);
        }

        user[deliveryEmailField] = deliveryEmail;
        user[Tb.occasion_users.data_email] = signInEmail;
        usedSignInEmails.add(signInEmail);
        suffix++;
      }
    }
  }

  static String _stableIdentityKey(Map<String, dynamic> user) => [
    user[Tb.occasion_users.data_surname],
    user[Tb.occasion_users.data_name],
  ].map((value) => value?.toString().trim().toLowerCase() ?? '').join('\u0000');

  static String _withNumericAlias(String email, int suffix) {
    final at = email.lastIndexOf('@');
    if (at <= 0 || at == email.length - 1) {
      throw const FormatException('Invalid email address in CSV import.');
    }
    return '${email.substring(0, at)}+$suffix${email.substring(at)}';
  }

  static String _normalizeEmail(String value, int rowNumber) {
    final email = value.toLowerCase();
    final at = email.indexOf('@');
    if (email.length > 254 ||
        at <= 0 ||
        at != email.lastIndexOf('@') ||
        at == email.length - 1 ||
        RegExp(r'\s').hasMatch(email)) {
      throw FormatException('CSV row $rowNumber has an invalid email address.');
    }
    return email;
  }

  static Map<String, dynamic> createServicesJson(
    String data,
    String serviceType,
  ) {
    final items = data
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();

    Map<String, String> servicesMap = {
      for (var item in items) item: DbOccasions.servicePaid,
    };

    return {serviceType: servicesMap};
  }

  static Map<String, dynamic> addJson(
    Map<String, dynamic>? existingJson,
    Map<String, dynamic> newJson,
  ) {
    existingJson ??= {};

    // Merge new JSON into existing JSON
    newJson.forEach((key, value) {
      if (existingJson![key] is Map && value is Map) {
        existingJson[key] = addJson(
          existingJson[key] as Map<String, dynamic>,
          value as Map<String, dynamic>,
        );
      } else {
        existingJson[key] = value;
      }
    });

    return existingJson;
  }
}
