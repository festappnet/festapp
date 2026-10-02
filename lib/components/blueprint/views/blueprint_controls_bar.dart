import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:fstapp/components/blueprint/blueprint_model.dart';
import 'package:fstapp/components/blueprint/blueprint_strings.dart';
import 'package:fstapp/components/images/db_images.dart';
import 'package:fstapp/services/dialog_helper.dart';
import 'package:fstapp/components/images/image_compression_helper.dart';
import 'package:fstapp/services/toast_helper.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';

import '../../_shared/common_strings.dart';
import '../blueprint_object_model.dart';

class BlueprintControlsBar extends StatefulWidget {
  final BlueprintModel? blueprint;
  final VenueSeatController<BlueprintObjectModel, Object> seatLayoutController;
  final bool canEdit;
  final bool allowRemoteUpload;

  const BlueprintControlsBar({
    super.key,
    required this.blueprint,
    required this.seatLayoutController,
    required this.canEdit,
    this.allowRemoteUpload = true,
  });

  @override
  State<BlueprintControlsBar> createState() => _BlueprintControlsBarState();
}

class _BlueprintControlsBarState extends State<BlueprintControlsBar> {
  /// Checks if decreasing width is safe (won't cut off seats)
  bool _canDecreaseWidth() {
    if (widget.blueprint == null) return false;
    int newValue = widget.blueprint!.configuration!.width! - 1;
    if (newValue <= 0) return false; // Can't go below 1

    int maxX = -1;
    for (var seat in widget.blueprint!.objects!) {
      if (seat.x! > maxX) {
        maxX = seat.x!;
      }
    }
    // If new value (1-based count) is <= max 0-based index, a seat would be cut off.
    if (newValue <= maxX) {
      return false; // Not safe
    }
    return true; // Safe
  }

  /// Checks if decreasing height is safe (won't cut off seats)
  bool _canDecreaseHeight() {
    if (widget.blueprint == null) return false;
    int newValue = widget.blueprint!.configuration!.height! - 1;
    if (newValue <= 0) return false; // Can't go below 1

    int maxY = -1;
    for (var seat in widget.blueprint!.objects!) {
      if (seat.y! > maxY) {
        maxY = seat.y!;
      }
    }
    // If new value (1-based count) is <= max 0-based index, a seat would be cut off.
    if (newValue <= maxY) {
      return false; // Not safe
    }
    return true; // Safe
  }

  @override
  Widget build(BuildContext context) {
    if (widget.blueprint == null) {
      return const SizedBox.shrink();
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildDimensionEditor(
          label: BlueprintStrings.width,
          currentValue: widget.blueprint!.configuration!.width!,
          isDecreaseEnabled: _canDecreaseWidth(), // Pass the check result
          onChanged: (value) {
            if (widget.seatLayoutController.setDimensions(
              widget.blueprint!.configuration!.height!,
              value,
            )) {
              setState(() {
                widget.blueprint!.configuration!.width = value;
              });
            }
          },
        ),
        const SizedBox(width: 12),
        _buildDimensionEditor(
          label: BlueprintStrings.height,
          currentValue: widget.blueprint!.configuration!.height!,
          isDecreaseEnabled: _canDecreaseHeight(), // Pass the check result
          onChanged: (value) {
            if (widget.seatLayoutController.setDimensions(
              value,
              widget.blueprint!.configuration!.width!,
            )) {
              setState(() {
                widget.blueprint!.configuration!.height = value;
              });
            }
          },
        ),
        const SizedBox(width: 24),
        _buildBackgroundControls(),
      ],
    );
  }

  Widget _buildBackgroundControls() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PopupMenuButton<String>(
          tooltip: BlueprintStrings.changeBackground,
          enabled: widget.canEdit,
          onSelected: (value) {
            if (value == 'svg') {
              _uploadSvgBackground();
            } else if (value == 'image') {
              _uploadImageBackground();
            }
          },
          itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
            if (widget.allowRemoteUpload) PopupMenuItem<String>(
              value: 'svg',
              child: Text(BlueprintStrings.uploadSVG),
            ),
            PopupMenuItem<String>(
              value: 'image',
              child: Text(BlueprintStrings.uploadImage),
            ),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(BlueprintStrings.background),
                const SizedBox(width: 8),
                Icon(Icons.grid_on, color: widget.canEdit ? null : Colors.grey),
              ],
            ),
          ),
        ),
        if (widget.blueprint?.backgroundSvg != null &&
            widget.blueprint!.backgroundSvg!.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: BlueprintStrings.removeBackground,
            onPressed: widget.canEdit ? _removeBackground : null,
          ),
      ],
    );
  }

  Widget _buildDimensionEditor({
    required String label,
    required int currentValue,
    required ValueChanged<int> onChanged,
    bool isDecreaseEnabled = true, // New parameter
  }) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.remove),
              iconSize: 16,
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(),
              // Use the flag here to disable the button
              onPressed: isDecreaseEnabled && widget.canEdit
                  ? () {
                      if (currentValue > 1) {
                        onChanged(currentValue - 1);
                      }
                    }
                  : null,
            ),
            Text(
              "$currentValue",
              style: const TextStyle(
                fontSize: 14,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add),
              iconSize: 16,
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(),
              onPressed: widget.canEdit
                  ? () {
                      onChanged(currentValue + 1);
                    }
                  : null,
            ),
          ],
        ),
      ],
    );
  }

  void _uploadSvgBackground() async {
    // Using the new DialogHelper API structure from your file
    var file = await DialogHelper.dropFilesHere(
      context,
      BlueprintStrings.dialogImportSvgTitle,
      CommonStrings.ok,
      CommonStrings.storno,
    );
    if (file != null) {
      try {
        var content = await file.readAsString();
        if (!content.trim().startsWith('<svg')) {
          ToastHelper.Show(context, BlueprintStrings.toastInvalidSvg,
              severity: ToastSeverity.NotOk);
          return;
        }
        setState(() {
          widget.blueprint!.backgroundSvg = content;
        });
        widget.seatLayoutController.setBackdrop(
          VenueBackdrop.parse(content),
        );
        ToastHelper.Show(context, BlueprintStrings.toastSvgUploadSuccess);
      } catch (e) {
        ToastHelper.Show(context, BlueprintStrings.toastSvgReadFail,
            severity: ToastSeverity.NotOk);
      }
    }
  }

  void _uploadImageBackground() async {
    var file = await DialogHelper.dropFilesHere(
      context,
      BlueprintStrings.dialogImportImageTitle,
      CommonStrings.ok,
      CommonStrings.storno,
    );
    if (file != null) {
      try {
        Uint8List imageData = await file.readAsBytes();
        var compressedImageData = await ImageCompressionHelper.compress(
            imageData, 3000,
            quality: 100);
        final publicUrl = await DbImages.uploadImage(
            compressedImageData, widget.blueprint!.occasion, null);
        setState(() {
          widget.blueprint!.backgroundSvg = publicUrl;
        });
        widget.seatLayoutController.setBackdrop(
          VenueBackdrop.parse(publicUrl),
        );
        ToastHelper.Show(context, BlueprintStrings.toastImageUploadSuccess);
      } catch (e) {
        ToastHelper.Show(context, BlueprintStrings.toastImageUploadFail,
            severity: ToastSeverity.NotOk);
      }
    }
  }

  void _removeBackground() async {
    // Using the new DialogHelper API structure from your file
    final confirmed = await DialogHelper.showConfirmationDialog(
        context,
        BlueprintStrings.dialogConfirmRemoveBackgroundTitle,
        BlueprintStrings.dialogConfirmRemoveBackgroundContent);

    if (confirmed == true) {
      setState(() {
        widget.blueprint!.backgroundSvg = null;
      });
      widget.seatLayoutController.setBackdrop(null);
      ToastHelper.Show(context, BlueprintStrings.toastBackgroundRemoved);
    }
  }
}
