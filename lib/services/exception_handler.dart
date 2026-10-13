import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/services/app_logger.dart';
import 'toast_helper.dart';

// ... (AppError class remains the same) ...
class AppError {
  final dynamic code;
  final String message;
  final String rawJson;

  AppError({
    required this.code,
    required this.message,
    required this.rawJson,
  });
}

class ExceptionHandler {
  /// **NEW:** Executes an async function and handles any exceptions that occur.
  ///
  /// This avoids repetitive try...catch blocks in your UI code.
  /// - [futureFunction]: The asynchronous database call to execute.
  /// - [rethrowError]: If true, the exception will be re-thrown after the dialog is closed.
  /// This is useful for data grids that need to know the operation failed.
  /// - Returns the result of [futureFunction] on success, or `null` on a handled error.
  static Future<T?> guard<T>(
    BuildContext context, {
    required Future<T> Function() futureFunction,
    String? defaultErrorMessage,
    bool rethrowError = false,
    bool showAsDialog = false,
  }) async {
    try {
      return await futureFunction();
    } catch (e) {
      if (context.mounted) {
        await handle(
          context,
          error: e,
          defaultMessage: defaultErrorMessage,
          showAsDialog: showAsDialog,
        );
      }
      if (rethrowError) {
        rethrow;
      }
      return null;
    }
  }

  /// Returns `true` on success and `false` on a handled failure.
  static Future<bool> guardVoid(
    BuildContext context, {
    required Future<void> Function() futureFunction,
    String? defaultErrorMessage,
    bool rethrowError = false,
    bool showAsDialog = false,
  }) async {
    try {
      await futureFunction();
      return true;
    } catch (e) {
      if (context.mounted) {
        await handle(
          context,
          error: e,
          defaultMessage: defaultErrorMessage,
          showAsDialog: showAsDialog,
        );
      }
      if (rethrowError) {
        rethrow;
      }
      return false;
    }
  }

  /// Handles an error by showing a user-friendly UI.
  /// Returns a Future that completes when the UI (e.g., dialog) is dismissed.
  static Future<void> handle(
    BuildContext context, {
    required Object error,
    String? defaultMessage,
    bool showAsDialog = false,
  }) async {
    final AppError? appError = _parsePostgrestException(error);

    if (appError != null) {
      if (showAsDialog) {
        await _showErrorDialog(context, appError);
      } else {
        ToastHelper.Show(context, appError.message,
            severity: ToastSeverity.NotOk);
      }
    } else {
      final message = defaultMessage ?? CommonStrings.unexpectedError;
      ToastHelper.Show(context, message, severity: ToastSeverity.NotOk);
      AppLogger.error('Unhandled Exception: ${error.toString()}');
    }
  }

  /// True when [e] is a network-level failure (no connection / server
  /// unreachable) rather than a server-side error. The supabase client
  /// surfaces these as http.ClientException — "Failed to fetch" on web,
  /// a wrapped SocketException on native (matched by message; dart:io is
  /// off-limits in shared code). Server responses (PostgrestException with a
  /// code, RPC envelopes) never match.
  static bool isNetworkError(Object e) {
    if (e is http.ClientException) return true;
    if (e is AuthRetryableFetchException) return true;
    final message = e.toString();
    return message.contains('SocketException') ||
        message.contains('Failed to fetch') ||
        message.contains('Failed host lookup') ||
        message.contains('Connection refused') ||
        message.contains('Network is unreachable') ||
        message.contains('Connection timed out');
  }

  /// Returns a user-friendly message for any exception. Postgrest errors carrying
  /// a JSON body are parsed; everything else falls back to [defaultMessage] or a
  /// generic message.
  static String toFriendlyMessage(Object error, {String? defaultMessage}) {
    final parsed = _parsePostgrestException(error);
    if (parsed != null) return parsed.message;
    return defaultMessage ?? CommonStrings.unexpectedError;
  }

  // Helper methods _parsePostgrestException and _showErrorDialog remain the same...
  static AppError? _parsePostgrestException(Object exception) {
    if (exception is! PostgrestException) return null;
    final jsonRegex = RegExp(r'\{.*\}');
    final match = jsonRegex.firstMatch(exception.message);
    if (match == null) return null;
    final jsonString = match.group(0)!;
    try {
      final jsonMap = jsonDecode(jsonString) as Map<String, dynamic>;
      return AppError(
        code: jsonMap['code'] ?? 'N/A',
        message: jsonMap['message'] as String? ??
            CommonStrings.unknownDatabaseError,
        rawJson: jsonString,
      );
    } catch (e) {
      return null;
    }
  }

  static Future<void> _showErrorDialog(
      BuildContext context, AppError appError) {
    return showDialog(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final scheme = theme.colorScheme;
        return AlertDialog(
          backgroundColor: scheme.surface,
          title: Text(
            CommonStrings.errorWithCode(code: appError.code.toString()),
            style: TextStyle(color: scheme.error),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  appError.message,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  CommonStrings.detailsLabel,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: SelectableText(
                    const JsonEncoder.withIndent('  ')
                        .convert(jsonDecode(appError.rawJson)),
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(CommonStrings.ok),
            ),
          ],
        );
      },
    );
  }
}
