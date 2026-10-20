abstract interface class FormCommands {
  Future<Map<String, dynamic>> create({
    required String occasionLink,
    required String link,
    required String title,
  });
  Future<int> duplicate({
    required int sourceFormId,
    required String targetOccasionLink,
  });
  Future<void> delete(int formId, {required int expectedVersion});
  Future<Map<String, dynamic>> save(Map<String, dynamic> form);
  Future<Map<String, dynamic>> saveBlueprint(
    Map<String, dynamic> blueprint,
  );
}
