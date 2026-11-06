import 'package:venue_layout_core/venue_layout_core.dart';

/// Editor visibility only. Hidden declarations remain part of the saved cascade.
/// Document and group presets are aggregate operations, not object materials.
class AppearanceControls {
  const AppearanceControls(this.target, {required this.scope});

  final LayoutNode? target;
  final String scope;

  bool get _document => scope == 'document';
  bool get _object => !_document && target != null && target!.kind != 'group';
  bool get _media => const {'image', 'vector'}.contains(target?.kind);
  bool get _surface => _object && !_media && target!.kind != 'text';
  bool get openPath =>
      _surface &&
      target!.kind == 'shape' &&
      const {'line', 'polyline', 'arrow'}.contains(target!.properties['shape']);

  bool get construction =>
      _surface && const {'seat', 'table', 'furniture'}.contains(target!.kind);
  bool get familyPresets =>
      _document || target?.kind == 'group' || construction;
  bool get chairStyle => _object && target!.kind == 'seat';
  bool get fill => _surface && !openPath;
  bool get outline => _surface;
  bool get cornerRadius => _surface && !openPath;
  bool get text => _document || (_object && !_media && target!.kind != 'seat');
  bool get labelOrientation => text && target?.kind != 'text';
  bool get opacity => _object;
}
