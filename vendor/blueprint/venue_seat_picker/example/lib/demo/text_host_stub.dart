Future<Map<String, dynamic>> prepareTextBatch(Map<String, dynamic> batch) =>
    Future.error(
      UnsupportedError('Standalone text preparation requires the web demo'),
    );
