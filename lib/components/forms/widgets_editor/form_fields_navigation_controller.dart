import 'package:flutter/foundation.dart';

import '../models/form_field_draft.dart';

/// A navigation snapshot, never a second owner of the editable field data.
class FormFieldNavigationItem {
  const FormFieldNavigationItem({
    required this.field,
    required this.identity,
    required this.title,
  });
  final FormFieldDraft field;
  final Object identity;
  final String title;
}

class FormFieldsNavigationController extends ChangeNotifier {
  List<FormFieldNavigationItem> _fields = const [];
  Object? _selectedIdentity;
  Object? _owner;
  ValueChanged<FormFieldDraft>? _reveal;
  VoidCallback? _clearSelection;
  bool _needsPublication = true;

  List<FormFieldNavigationItem> get fields => _fields;
  Object? get selectedIdentity => _selectedIdentity;

  void revealField(FormFieldDraft field) => _reveal?.call(field);
  void clearSelection() => _clearSelection?.call();

  void attach(
    Object owner, {
    required ValueChanged<FormFieldDraft> reveal,
    required VoidCallback clearSelection,
  }) {
    _owner = owner;
    _reveal = reveal;
    _clearSelection = clearSelection;
    _fields = const [];
    _selectedIdentity = null;
    _needsPublication = true;
  }

  void publish(
    Object owner,
    List<FormFieldNavigationItem> fields,
    Object? selectedIdentity,
  ) {
    if (!identical(owner, _owner)) return;
    final unchanged =
        selectedIdentity == _selectedIdentity &&
        fields.length == _fields.length &&
        List.generate(fields.length, (i) => i).every(
          (i) =>
              fields[i].identity == _fields[i].identity &&
              identical(fields[i].field, _fields[i].field) &&
              fields[i].title == _fields[i].title,
        );
    if (unchanged && !_needsPublication) return;
    _needsPublication = false;
    _fields = List.unmodifiable(fields);
    _selectedIdentity = selectedIdentity;
    notifyListeners();
  }

  void detach(Object owner) {
    if (!identical(owner, _owner)) return;
    _owner = null;
    _reveal = null;
    _clearSelection = null;
    _fields = const [];
    _selectedIdentity = null;
  }

  @override
  void dispose() {
    _owner = null;
    _reveal = null;
    _clearSelection = null;
    super.dispose();
  }
}
