/// An authenticated continuation, not a permission or a resource identifier.
abstract final class OrganizerDestination {
  static const create = '/organizer-action/create';

  static bool isCreate(String? value) => value == create;
}
