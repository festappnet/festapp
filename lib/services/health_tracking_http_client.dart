import 'package:fstapp/services/connectivity_service.dart';
import 'package:fstapp/services/exception_handler.dart';
import 'package:http/http.dart' as http;

/// Wraps the http client Supabase uses so every backend request's outcome feeds
/// [ConnectivityService]'s backend-reachability signal:
///   - a completed response (any HTTP status) means the server answered → the
///     backend is reachable;
///   - a network / timeout / connection error means a failure.
///
/// Passive: it never alters the request or the response, it only observes. This
/// is the single choke point for all REST / RPC / auth traffic, so weak signal,
/// a server outage or flaky networking are detected wherever they happen.
class HealthTrackingHttpClient extends http.BaseClient {
  final http.Client _inner;

  HealthTrackingHttpClient([http.Client? inner])
      : _inner = inner ?? http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    try {
      final response = await _inner.send(request);
      // Headers arrived → the server was reached (even a 4xx/5xx counts as
      // "reachable"; it is a server answer, not a connectivity failure).
      ConnectivityService.reportSuccess();
      return response;
    } catch (e) {
      if (ExceptionHandler.isNetworkError(e)) {
        ConnectivityService.reportNetworkFailure();
      }
      rethrow;
    }
  }

  @override
  void close() => _inner.close();
}
