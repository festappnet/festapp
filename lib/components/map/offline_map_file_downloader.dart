import 'dart:io';

import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// Canonical network and atomic-file boundary for every offline map asset.
class OfflineMapFileDownloader {
  OfflineMapFileDownloader({
    http.Client? client,
    this.retryDelay = const Duration(milliseconds: 300),
    this.maximumAttempts = 3,
  }) : _client = client ?? http.Client() {
    if (maximumAttempts < 1) {
      throw ArgumentError.value(maximumAttempts, 'maximumAttempts');
    }
  }

  final http.Client _client;
  final Duration retryDelay;
  final int maximumAttempts;

  void close() => _client.close();

  Future<File> download({
    required Uri uri,
    required File destination,
    int? expectedBytes,
    String? expectedSha256,
    void Function(int bytes)? onChunk,
    void Function(double fraction)? onProgress,
  }) async {
    for (var attempt = 1;; attempt++) {
      var attemptBytes = 0;
      try {
        return await _downloadOnce(
          uri: uri,
          destination: destination,
          expectedBytes: expectedBytes,
          expectedSha256: expectedSha256,
          onProgress: onProgress,
          onChunk: (count) {
            attemptBytes += count;
            onChunk?.call(count);
          },
        );
      } catch (_) {
        if (attemptBytes > 0) onChunk?.call(-attemptBytes);
        onProgress?.call(0);
        if (attempt >= maximumAttempts) rethrow;
        if (retryDelay > Duration.zero) {
          await Future<void>.delayed(retryDelay * attempt);
        }
      }
    }
  }

  Future<File> _downloadOnce({
    required Uri uri,
    required File destination,
    required int? expectedBytes,
    required String? expectedSha256,
    required void Function(int bytes) onChunk,
    required void Function(double fraction)? onProgress,
  }) async {
    final response = await _client.send(http.Request('GET', uri));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Offline map asset download failed: ${response.statusCode}',
        uri: uri,
      );
    }
    final part = File('${destination.path}.part');
    await destination.parent.create(recursive: true);
    if (await part.exists()) await part.delete();
    final output = part.openWrite();
    final digestOutput = AccumulatorSink<Digest>();
    final digestInput = sha256.startChunkedConversion(digestOutput);
    var received = 0;
    var outputClosed = false;
    var digestClosed = false;
    try {
      await for (final chunk in response.stream) {
        output.add(chunk);
        digestInput.add(chunk);
        received += chunk.length;
        onChunk(chunk.length);
        final contentLength = response.contentLength;
        onProgress?.call(
          contentLength != null && contentLength > 0
              ? received / contentLength
              : 0,
        );
      }
      await output.flush();
      await output.close();
      outputClosed = true;
      digestInput.close();
      digestClosed = true;
      final contentLength = response.contentLength;
      if (contentLength != null &&
          contentLength >= 0 &&
          received != contentLength) {
        throw const HttpException('Offline map asset download was incomplete.');
      }
      if (expectedBytes != null && received != expectedBytes) {
        throw const HttpException('Offline map asset size mismatch.');
      }
      if (expectedSha256 != null &&
          digestOutput.events.single.toString() != expectedSha256) {
        throw const HttpException('Offline map asset checksum mismatch.');
      }
      await _publish(part: part, destination: destination);
      return destination;
    } catch (_) {
      if (!outputClosed) await output.close();
      if (!digestClosed) digestInput.close();
      if (await part.exists()) await part.delete();
      rethrow;
    }
  }

  Future<void> _publish({
    required File part,
    required File destination,
  }) async {
    final backup = File('${destination.path}.old');
    if (await backup.exists()) await backup.delete();
    if (await destination.exists()) await destination.rename(backup.path);
    try {
      await part.rename(destination.path);
    } catch (_) {
      if (!await destination.exists() && await backup.exists()) {
        await backup.rename(destination.path);
      }
      rethrow;
    }
    try {
      if (await backup.exists()) await backup.delete();
    } catch (_) {
      // The canonical file is already published. Cleanup can wait for the next
      // refresh without turning success into a user-visible failure.
    }
  }
}
