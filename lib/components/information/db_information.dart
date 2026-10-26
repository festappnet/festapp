import 'package:fstapp/data_services/authorization_capabilities.dart';
import 'package:collection/collection.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/information/information_model.dart';
import 'package:fstapp/components/information/information_strings.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/database_tables/tb.dart';
import 'package:fstapp/data_services/offline_data_service.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/components/information/information_commands.dart';
import 'package:fstapp/services/toast_helper.dart';
import 'package:fstapp/services/utilities_all.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DbInformation {
  static final _supabase = Supabase.instance.client;
  static final InformationCommands _commands =
      SupabaseInformationCommands(_supabase);

  static List<InformationModel> _sortViaDatetime(
      List<InformationModel> infoList) {
    infoList.sort((a, b) {
      final orderComparison = a.getDateTime().compareTo(b.getDateTime());
      return orderComparison;
    });
    return infoList;
  }

  static List<InformationModel> _sortInformationList(
      List<InformationModel> infoList) {
    infoList.sort((a, b) {
      final orderComparison = a.getOrder().compareTo(b.getOrder());
      if (orderComparison != 0) {
        return orderComparison;
      }
      return Utilities.naturalCompare(
          a.title?.toLowerCase() ?? "", b.title?.toLowerCase() ?? "");
    });
    return infoList;
  }

  static Future<List<InformationModel>> getAllInformationForDataGrid(
      [String? type]) async {
    final response = await _supabase.rpc(
      'get_information_editor_bundle_v1',
      params: {
        'p_occasion': RightsService.currentOccasionId()!,
        'p_type': type,
      },
    );
    final bundle = (response as Map).cast<String, dynamic>();
    if (bundle['code'] != 200) {
      throw StateError('Information editor data could not be loaded');
    }
    final information = ((bundle['information'] as List?) ?? const [])
        .map((x) =>
            InformationModel.fromJson((x as Map).cast<String, dynamic>()))
        .toList();
    return _sortInformationList(information);
  }

  static Future<List<InformationModel>> getAllInformationForDataGridForUnit(
      int unitId,
      [String? type]) async {
    final rows =
        await _supabase.rpc('get_unit_information_for_edit_v1', params: {
      'p_unit': unitId,
      'p_type': type,
    }) as List;
    return _sortViaDatetime(rows
        .map((row) =>
            InformationModel.fromJson(Map<String, dynamic>.from(row as Map)))
        .toList());
  }

  static Future<List<InformationModel>> getAllActiveInformation() async {
    var data = await _supabase
        .from(Tb.information.table)
        .select("${Tb.information.id},"
            "${Tb.information.updated_at},"
            "${Tb.information.order},"
            "${Tb.information.type},"
            "${Tb.information.title},"
            "${Tb.information.description},"
            "${Tb.information.id},"
            "${Tb.information.data}")
        .eq(Tb.information.is_hidden, false)
        .eq(Tb.information.occasion, RightsService.currentOccasionId()!);

    var infoList = List<InformationModel>.from(
        data.map((x) => InformationModel.fromJson(x)));
    if (RightsService.hasCapability(
        AuthorizationCapabilities.informationWrite)) {
      // The inline writer must freeze content and its version from one read.
      // Keep other information types in the shared public/offline catalog.
      final editable = await getAllInformationForDataGrid();
      infoList.removeWhere((info) => info.type == null || info.type!.isEmpty);
      infoList.addAll(editable.where((info) => !(info.isHidden ?? false)));
    }
    infoList.sortBy((element) => element.title ?? "".toLowerCase());
    infoList.sort((a, b) => (a.getOrder().compareTo(b.getOrder())));
    return infoList;
  }

  static Future<void> updateInformation(InformationModel info) async {
    final result = await _commands.save(
        info.unit ?? RightsService.currentOccasionId()!, info);
    if (result.status == InformationCommandStatus.conflict) {
      throw StateError('Information was changed by another editor');
    }
    if (result.status == InformationCommandStatus.rejected ||
        result.information == null) {
      throw StateError('Information save was rejected');
    }
    final updated = result.information!;
    info
      ..id = updated.id
      ..informationHidden = updated.informationHidden
      ..updatedAt = updated.updatedAt
      ..aggregateVersion = result.version;
  }

  static Future<void> deleteInformation(InformationModel info) async {
    final result = await _commands.delete(
        info.unit ?? RightsService.currentOccasionId()!, info);
    if (result.status == InformationCommandStatus.conflict) {
      throw StateError('Information was changed by another editor');
    }
    if (result.status == InformationCommandStatus.rejected) {
      throw StateError('Information delete was rejected');
    }
  }

  static Future<void> fillDescriptionFromOffline(InformationModel info) async {
    var infoDesc =
        await OfflineDataService.getInfoDescription(info.id!.toString());
    if (infoDesc != null) {
      info.description = infoDesc.description ?? "";
    }
  }

  static Future<InformationModel?> getCurrentQuote(int unitId) async {
    var data = await _supabase.rpc("get_current_quote", params: {
      "unit_id": unitId,
    });
    if (data["code"] == 200) {
      return InformationModel.fromJson(data["data"]);
    }
    return null;
  }

  static Future<bool> makeGameGuess(
      BuildContext context, int checkPointId, String guess) async {
    final result = await _commands.guess(checkPointId, guess);
    final resultCode = result.domainCode;

    switch (resultCode) {
      case 200: // Correct answer
        ToastHelper.Show(context, InformationStrings.gameCorrect);
        return true;

      case 4031: // User not in occasion
        ToastHelper.Show(context, InformationStrings.gameNotInOccasion,
            severity: ToastSeverity.NotOk);
        break;

      case 4032: // User not part of a game group
        ToastHelper.Show(context, InformationStrings.gameNotInGroup,
            severity: ToastSeverity.NotOk);
        break;

      case 4033: // Guessing outside allowed time window
        ToastHelper.Show(context, InformationStrings.gameOutsideWindow,
            severity: ToastSeverity.NotOk);
        break;

      case 4041: // Correct reference not found
        ToastHelper.Show(
            context, InformationStrings.gameAnswerNotSetForCheckPoint,
            severity: ToastSeverity.NotOk);
        break;

      case 4042: // Hidden info not found
        ToastHelper.Show(context, InformationStrings.gameAnswerNotSet,
            severity: ToastSeverity.NotOk);
        break;

      case 4001: // Incorrect guess
        ToastHelper.Show(context, InformationStrings.gameIncorrect,
            severity: ToastSeverity.NotOk);
        break;

      default:
        ToastHelper.Show(context, CommonStrings.unexpectedError,
            severity: ToastSeverity.NotOk);
        break;
    }
    return false;
  }
}
