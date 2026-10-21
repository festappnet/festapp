String? readDraft() => null;
void writeDraft(String value) {}
Future<String?> readPreviewDraft() async => null;
Future<void> openWebPreview(String value) async =>
    throw UnsupportedError('Web preview requires the browser demo');
