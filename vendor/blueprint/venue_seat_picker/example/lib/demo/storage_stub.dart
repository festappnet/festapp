Future<String?> readDraft() async => null;
Future<void> writeDraft(String value) async {}
Future<String?> readPreviewDraft() async => null;
Future<void> openWebPreview(String value) async =>
    throw UnsupportedError('Web preview requires the browser demo');
