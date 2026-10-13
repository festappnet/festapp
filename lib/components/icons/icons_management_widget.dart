import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:cross_file/cross_file.dart';
import 'package:fstapp/widgets/drop_file.dart';
import 'package:fstapp/components/icons/db_icons.dart';
import 'package:fstapp/components/icons/icons_strings.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/map/icon_model.dart';
import 'package:fstapp/theme_config.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/services/toast_helper.dart';
import 'package:fstapp/services/launch_url_service.dart';

/// Occasion/unit SVG icon library manager. Mirrors the deployed layout: a
/// wrap of icon tiles + an Upload button; upload opens a dialog (pick SVG ≤50KB,
/// Google Material Symbols hint, preview, name). Legacy icons (no owning unit)
/// are read-only.
class IconsManagementWidget extends StatefulWidget {
  const IconsManagementWidget({super.key});

  @override
  State<IconsManagementWidget> createState() => _IconsManagementWidgetState();
}

class _IconsManagementWidgetState extends State<IconsManagementWidget> {
  List<IconModel> _icons = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final icons = await DbIcons.getManagedIcons();
      if (!mounted) return;
      setState(() {
        _icons = icons;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _delete(IconModel icon) async {
    if (icon.isLegacy) {
      ToastHelper.Show(context, IconsStrings.legacyReadOnly);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(IconsStrings.uploadIcon),
        content: Text(IconsStrings.deleteConfirm),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(CommonStrings.storno)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(CommonStrings.delete)),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await DbIcons.deleteIcon(icon.id!);
      await _load();
    } on IconInUseException catch (e) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(IconsStrings.inUseTitle),
            content: Text(
                IconsStrings.inUseDetail(e.places, e.pathGroups, e.placeTypes)),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(CommonStrings.close)),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) ToastHelper.Show(context, '$e');
    }
  }

  Future<void> _openUpload() async {
    if (RightsService.currentUnit()?.id == null) {
      ToastHelper.Show(context, IconsStrings.noUnit);
      return;
    }
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => const UploadIconDialog(),
    );
    if (saved == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header: title + count on the left, Upload action on the right.
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Row(
            children: [
              Icon(Icons.emoji_symbols_outlined,
                  color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Text(
                IconsStrings.icons,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              if (!_loading && _icons.isNotEmpty) ...[
                const SizedBox(width: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_icons.length}',
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: theme.colorScheme.primary),
                  ),
                ),
              ],
              const Spacer(),
              FilledButton.icon(
                onPressed: _openUpload,
                icon: const Icon(Icons.upload, size: 18),
                label: Text(IconsStrings.uploadIcon),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // Mini how-to (get an SVG from Google Material Symbols) shown directly
        // on the screen, not hidden behind the Upload dialog.
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: _GoogleIconsHint(),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _icons.isEmpty
                  ? _emptyState(theme)
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Wrap(
                        spacing: 16,
                        runSpacing: 16,
                        children: _icons
                            .map((i) => _IconCard(
                                  icon: i,
                                  onDelete: () => _delete(i),
                                ))
                            .toList(),
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _emptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.emoji_symbols_outlined,
              size: 56, color: theme.colorScheme.outline),
          const SizedBox(height: 16),
          Text(
            IconsStrings.empty,
            style: theme.textTheme.bodyLarge
                ?.copyWith(color: theme.colorScheme.outline),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: _openUpload,
            icon: const Icon(Icons.upload, size: 18),
            label: Text(IconsStrings.uploadIcon),
          ),
        ],
      ),
    );
  }
}

/// A single icon tile — a hover-reactive card with the SVG, its name, and a
/// delete affordance (locked for legacy icons).
class _IconCard extends StatefulWidget {
  final IconModel icon;
  final VoidCallback onDelete;
  const _IconCard({required this.icon, required this.onDelete});

  @override
  State<_IconCard> createState() => _IconCardState();
}

class _IconCardState extends State<_IconCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final icon = widget.icon;
    final svgData = icon.renderableSvgData;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: 108,
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _hover
                ? theme.colorScheme.primary.withValues(alpha: 0.5)
                : theme.colorScheme.outlineVariant,
          ),
          boxShadow: _hover
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.10),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  )
                ]
              : null,
        ),
        child: Stack(
          children: [
            SizedBox(
              width: double.infinity,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 56,
                    height: 56,
                    child: svgData != null
                        ? SvgPicture.string(svgData,
                            fit: BoxFit.contain,
                            colorFilter: ColorFilter.mode(
                                ThemeConfig.blackColor(context),
                                BlendMode.srcIn),
                            errorBuilder: (context, error, stackTrace) => Icon(
                                Icons.image_not_supported,
                                size: 24,
                                color: theme.colorScheme.outline))
                        : Icon(Icons.image_not_supported,
                            size: 24, color: theme.colorScheme.outline),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    icon.displayLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            // Always-visible action in the card corner (inside the Stack's
            // bounds — hit testing ignores children positioned outside them),
            // so it also works on touch screens with no hover.
            Positioned(
              top: 0,
              right: 0,
              child: icon.isLegacy
                  ? Tooltip(
                      message: IconsStrings.legacyReadOnly,
                      child: Icon(Icons.lock_outline,
                          size: 16, color: theme.colorScheme.outline),
                    )
                  : Tooltip(
                      message: CommonStrings.delete,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: widget.onDelete,
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(Icons.delete_outline,
                              size: 16, color: theme.colorScheme.outline),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Upload dialog: pick an SVG (≤50KB), Google Material Symbols hint, preview,
/// and a name (link). Matches the deployed dialog.
class UploadIconDialog extends StatefulWidget {
  const UploadIconDialog({super.key});

  @override
  State<UploadIconDialog> createState() => _UploadIconDialogState();
}

class _UploadIconDialogState extends State<UploadIconDialog> {
  final TextEditingController _name = TextEditingController();
  String? _svg;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Save is disabled until both SVG and name are present (same pattern as
    // InputDialogs.showImportDialog), so rebuild on name edits.
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _onFile(XFile file) async {
    final bytes = await file.readAsBytes();
    setState(() {
      _error = null;
      _svg = null;
    });
    if (bytes.length > DbIcons.maxBytes) {
      setState(() => _error = IconsStrings.tooLarge);
      return;
    }
    final svg = utf8.decode(bytes, allowMalformed: true);
    final svgData = IconModel(data: svg).renderableSvgData;
    if (svgData == null) {
      setState(() => _error = IconsStrings.invalidSvg);
      return;
    }
    setState(() {
      _svg = svgData;
      if (_name.text.isEmpty) {
        _name.text = file.name.replaceAll(RegExp(r'\.svg$'), '');
      }
    });
  }

  Future<void> _save() async {
    if (_svg == null || _name.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      await DbIcons.insertIcon(link: _name.text.trim(), svgData: _svg!);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(IconsStrings.uploadIcon),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropFile(
                onFilePathChanged: _onFile,
                allowedExtensions: const ['svg'],
                hint: IconsStrings.uploadHint,
                height: 120,
              ),
              if (_svg != null) ...[
                const SizedBox(height: 16),
                Center(
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.black26),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    padding: const EdgeInsets.all(10),
                    child: SvgPicture.string(_svg!,
                        fit: BoxFit.contain,
                        colorFilter: ColorFilter.mode(
                            ThemeConfig.blackColor(context), BlendMode.srcIn)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _name,
                  decoration: InputDecoration(
                    labelText: IconsStrings.linkLabel,
                    helperText: IconsStrings.linkHelper,
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: Text(CommonStrings.storno),
        ),
        FilledButton(
          onPressed: (_svg == null || _name.text.trim().isEmpty || _saving)
              ? null
              : _save,
          child: Text(CommonStrings.save),
        ),
      ],
    );
  }
}

/// Mini how-to for grabbing an SVG icon from Google Material Symbols. Shown
/// directly on the icons screen (and in the upload dialog). The link opens
/// fonts.google.com/icons.
class _GoogleIconsHint extends StatelessWidget {
  const _GoogleIconsHint();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline, size: 16),
        const SizedBox(width: 6),
        Expanded(
          child: Text.rich(
            TextSpan(
              style: theme.textTheme.bodySmall,
              children: [
                TextSpan(text: '${IconsStrings.googleHint} '),
                TextSpan(
                  text: IconsStrings.googleLink,
                  style: TextStyle(
                    color: theme.colorScheme.primary,
                    decoration: TextDecoration.underline,
                  ),
                  recognizer: TapGestureRecognizer()
                    ..onTap = () => LaunchUrlService.openExternalUrl(
                          'https://fonts.google.com/icons',
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
