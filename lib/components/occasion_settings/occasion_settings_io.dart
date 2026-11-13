import 'dart:typed_data';

import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';

import '../occasion/occasion_model.dart';
import '../occasion/db_occasions.dart';
import '../images/db_images.dart';
import '../../data_services/rights_service.dart';
import 'occasion_save_state.dart';

/// External effects of the occasion editor. Defaults retain production owners.
class OccasionSettingsIo {
  final Future<void> Function(OccasionModel) updateOccasion;
  final Future<void> Function(BuildContext, String, String) refreshSaved;
  final Future<OccasionModel> Function(int) reloadOccasion;
  final Future<String> Function(Uint8List, int?) uploadImage;
  const OccasionSettingsIo({
    this.updateOccasion = DbOccasions.updateOccasion,
    this.refreshSaved = _refreshSaved,
    this.reloadOccasion = _reloadOccasion,
    this.uploadImage = _uploadImage,
  });
  static Future<void> _refreshSaved(
    BuildContext context,
    String previous,
    String saved,
  ) => refreshSavedOccasion(
    router: context.router,
    previousLink: previous,
    savedLink: saved,
    refresh: (link) async {
      await RightsService.updateAppData(
        link: link,
        force: true,
        refreshOffline: false,
      );
    },
  );
  static Future<OccasionModel> _reloadOccasion(int id) async {
    final occasion = await DbOccasions.getOccasion(id);
    return DbOccasions.getOccasionByLink(occasion.link!);
  }

  static Future<String> _uploadImage(Uint8List bytes, int? id) =>
      DbImages.uploadImage(bytes, id, null, profile: ImageUploadProfile.banner);
}
