import 'package:web/web.dart' as web;
import 'mcp_callback_window.dart';

McpCallbackWindow? openMcpCallbackWindow() {
  // Called synchronously from the approval gesture, before any network await.
  // Sever the child's opener immediately; it cannot navigate the tenant page.
  final window =
      web.window.open('about:blank', '_blank', 'popup,width=520,height=640');
  if (window == null) return null;
  window.opener = null;
  return _CallbackWindow(window);
}

class _CallbackWindow implements McpCallbackWindow {
  _CallbackWindow(this.window);
  final web.Window window;
  @override
  void navigate(Uri uri) => window.location.replace(uri.toString());
  @override
  void close() => window.close();
}

void closeMcpConfirmationWindow() => web.window.close();
