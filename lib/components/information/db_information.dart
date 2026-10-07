import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/components/information/information_model.dart';
import 'package:fstapp/components/information/information_strings.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/database_tables/tb.dart';
import 'package:fstapp/data_services/offline_data_service.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/data_services/client_sync/client_sync_runtime.dart';
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
    var select = "${Tb.information.id},"
        "${Tb.information.unit},"
        "${Tb.information.occasion},"
        "${Tb.information.created_at},"
        "${Tb.information.updated_at},"
        "${Tb.information.is_hidden},"
        "${Tb.information.title},"
        "${Tb.information.description},"
        "${Tb.information.order},"
        "${Tb.information.type},"
        "${Tb.information.data},"
        "${Tb.information_hidden.table}(*)";
    List<Map<String, dynamic>> data = [];
    if (type != null) {
      data = await _supabase
          .from(Tb.information.table)
          .select(select)
          .or("${Tb.information.occasion}.is.null")
          .eq(Tb.information.unit, unitId)
          .filter(Tb.information.type, "eq", type);
    } else {
      data = await _supabase
          .from(Tb.information.table)
          .select(select)
          .or("${Tb.information.occasion}.is.null")
          .eq(Tb.information.unit, unitId)
          .or("${Tb.information.type}.eq.,${Tb.information.type}.is.null");
    }
    var infoList = List<InformationModel>.from(
        data.map((x) => InformationModel.fromJson(x)));
    return _sortViaDatetime(infoList);
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
    if (RightsService.isEditor()) {
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
    if (info.unit == null) {
      final result =
          await _commands.save(RightsService.currentOccasionId()!, info);
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
      return;
    }
    if (info.type == InformationModel.gameType) {
      Map<String, dynamic> upsertObj = {
        Tb.information_hidden.data: info.informationHidden?.data,
        Tb.information_hidden.occasion: RightsService.currentOccasionId()!
      };
      Map<String, dynamic> ref;
      if (info.informationHidden?.id != null) {
        upsertObj.addAll({
          Tb.information_hidden.id: info.informationHidden?.id,
        });
        ref = await _supabase
            .from(Tb.information_hidden.table)
            .update(upsertObj)
            .eq(Tb.information_hidden.id, info.informationHidden!.id!)
            .select(Tb.information_hidden.id)
            .single();
      } else {
        ref = await _supabase
            .from(Tb.information_hidden.table)
            .insert(upsertObj)
            .select(Tb.information_hidden.id)
            .single();
      }

      info.informationHidden =
          InformationHiddenModel(id: ref[Tb.information_hidden.id]);
    }
    var upsertObj = {
      Tb.information.title: info.title,
      Tb.information.type: info.type,
      Tb.information.is_hidden: info.isHidden,
      Tb.information.order: info.order,
      Tb.information.data: info.data,
      Tb.information.information_hidden: info.informationHidden?.id
    };
    if (info.description != null) {
      upsertObj.addAll({Tb.information.description: info.description});
    }
    if (info.id != null) {
      upsertObj.addAll({Tb.information.id: info.id});
      await _supabase
          .from(Tb.information.table)
          .update(upsertObj)
          .eq(Tb.information.id, info.id!);
    } else {
      if (info.unit == null) {
        upsertObj.addAll(
            {Tb.information.occasion: RightsService.currentOccasionId()!});
      } else {
        upsertObj.addAll({Tb.information.unit: info.unit});
      }
      await _supabase.from(Tb.information.table).insert(upsertObj);
    }
  }

  static Future<void> deleteInformation(InformationModel info) async {
    if (ClientSyncRuntime.isV1Selected && info.unit == null) {
      final result =
          await _commands.delete(RightsService.currentOccasionId()!, info);
      if (result.status == InformationCommandStatus.conflict) {
        throw StateError('Information was changed by another editor');
      }
      if (result.status == InformationCommandStatus.rejected) {
        throw StateError('Information delete was rejected');
      }
      return;
    }
    await _supabase
        .from(Tb.information.table)
        .delete()
        .eq(Tb.information.id, info.id!);
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
