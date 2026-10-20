import 'package:flutter/foundation.dart';

import 'occasion_commands.dart';
import 'occasion_media_copier.dart';
import 'occasion_model.dart';

/// Owns the committed database copy and its subsequent external media setup.
class OccasionDuplicator {
  OccasionDuplicator({
    required this.commands,
    required this.loadOccasion,
    required this.copyImage,
  });

  final OccasionCommands commands;
  final Future<OccasionModel> Function(int) loadOccasion;
  final CopyOccasionImage copyImage;

  Future<({int occasionId, bool mediaCopied})> duplicate(
    int source, {
    int? targetUnitId,
    String locale = 'en',
    String? commandId,
  }) async {
    final id = await commands.duplicate(source,
        targetUnitId: targetUnitId, locale: locale, commandId: commandId);
    try {
      final occasion = await loadOccasion(id);
      if (await copyOccasionMedia(occasion, copyImage)) {
        await commands.save(occasion);
      }
      return (occasionId: id, mediaCopied: true);
    } catch (_) {
      // SQL creation has committed. A media failure must never create a second
      // occasion or hide the ID needed to open the existing copy.
      debugPrint('Occasion $id was copied, but media setup failed.');
      return (occasionId: id, mediaCopied: false);
    }
  }
}
