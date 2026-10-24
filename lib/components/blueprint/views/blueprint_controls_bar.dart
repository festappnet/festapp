import 'package:flutter/material.dart';
import 'package:fstapp/components/blueprint/blueprint_model.dart';
import 'package:fstapp/components/blueprint/blueprint_strings.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';

import '../blueprint_object_model.dart';

class BlueprintControlsBar extends StatefulWidget {
  final BlueprintModel? blueprint;
  final VenueSeatController<BlueprintObjectModel, Object> seatLayoutController;
  final bool canEdit;
  final bool allowRemoteUpload;
  final VoidCallback onImportSvg;
  final VoidCallback onImportImage;
  final VoidCallback onRemoveBackground;

  const BlueprintControlsBar({
    super.key,
    required this.blueprint,
    required this.seatLayoutController,
    required this.canEdit,
    this.allowRemoteUpload = true,
    required this.onImportSvg,
    required this.onImportImage,
    required this.onRemoveBackground,
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
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 8,
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
              widget.onImportSvg();
            } else if (value == 'image') {
              widget.onImportImage();
            }
          },
          itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
            PopupMenuItem<String>(
              value: 'svg',
              child: Text(BlueprintStrings.uploadSVG),
            ),
            if (widget.allowRemoteUpload)
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
            onPressed: widget.canEdit ? widget.onRemoveBackground : null,
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
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.remove),
              iconSize: 20,
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
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
              iconSize: 20,
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
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
}
