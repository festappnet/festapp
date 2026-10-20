/// An app-owned helper window transports the native OAuth callback. Its
/// cross-origin document and URL are never read by the tenant application.
abstract interface class McpCallbackWindow {
  void navigate(Uri uri);
  void close();
}
