import 'package:flutter/material.dart';
import 'package:fstapp/services/exception_handler.dart';
import 'package:fstapp/services/toast_helper.dart';
import 'package:fstapp/theme_config.dart';
import 'package:fstapp/components/_shared/common_strings.dart';

class ProgressDialogs {
  static Future<bool> showProgressDialogAsync(
    BuildContext context,
    String title,
    int total, {
    List<Future<void> Function()>? futures,
    Duration? delay,
    bool isBasic = false,
  }) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    final progressNotifier = ValueNotifier<int>(0);
    final isCancelled = ValueNotifier<bool>(false);
    final statusMessage = ValueNotifier<String>("");
    final isStornoActive = ValueNotifier<bool>(!isBasic);
    final isOkActive = ValueNotifier<bool>(false);
    final hasError = ValueNotifier<bool>(false);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return ValueListenableBuilder<int>(
          valueListenable: progressNotifier,
          builder: (context, progress, _) {
            return AlertDialog(
              title: Text(title),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text("${CommonStrings.progress}: $progress/$total"),
                  SizedBox(height: 20),
                  LinearProgressIndicator(
                      value: total > 0 ? progress / total : 0),
                  SizedBox(height: 20),
                  ValueListenableBuilder<String>(
                    valueListenable: statusMessage,
                    builder: (context, message, _) {
                      return Text(
                        message,
                        style: TextStyle(
                          color: hasError.value
                              ? ThemeConfig.redColor(context)
                              : ThemeConfig.blackColor(context),
                        ),
                        textAlign: TextAlign.center,
                      );
                    },
                  ),
                  ValueListenableBuilder<bool>(
                    valueListenable: hasError,
                    builder: (context, errorOccurred, _) {
                      if (!isBasic || errorOccurred) {
                        return Column(
                          children: [
                            SizedBox(height: 20),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                ValueListenableBuilder<bool>(
                                  valueListenable: isStornoActive,
                                  builder: (context, isActive, _) {
                                    return SizedBox(
                                      width: 100,
                                      child: ElevatedButton(
                                        onPressed: isActive
                                            ? () {
                                                isCancelled.value = true;
                                                isStornoActive.value = false;
                                                isOkActive.value = true;
                                                statusMessage.value =
                                                    CommonStrings
                                                        .processingCancelled;
                                              }
                                            : null,
                                        child: Text(CommonStrings.storno),
                                      ),
                                    );
                                  },
                                ),
                                SizedBox(width: 20),
                                ValueListenableBuilder<bool>(
                                  valueListenable: isOkActive,
                                  builder: (context, isActive, _) {
                                    return SizedBox(
                                      width: 100,
                                      child: ElevatedButton(
                                        onPressed: isActive
                                            ? () {
                                                Navigator.of(context).pop();
                                              }
                                            : null,
                                        child: Text(CommonStrings.ok),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ],
                        );
                      } else {
                        return SizedBox.shrink();
                      }
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (futures != null && futures.isNotEmpty) {
      for (var future in futures) {
        if (isCancelled.value) break;
        try {
          statusMessage.value = CommonStrings.processing;
          await future.call();
          progressNotifier.value++;
          if (delay != null) {
            await Future.delayed(delay);
          }
        } catch (e) {
          if (isBasic) {
            if (navigator.mounted) navigator.pop();
            if (context.mounted) {
              await ExceptionHandler.handle(context, error: e);
            }
            return false;
          }
          statusMessage.value = ExceptionHandler.toFriendlyMessage(e);
          isCancelled.value = true;
          isStornoActive.value = false;
          isOkActive.value = true;
          hasError.value = true;
          break;
        }
      }
    }

    isOkActive.value = true;
    isStornoActive.value = false;
    if (hasError.value) {
      statusMessage.value = CommonStrings.processingFailed;
    } else if (isCancelled.value) {
      statusMessage.value = CommonStrings.processingCancelled;
    } else {
      statusMessage.value = CommonStrings.processingCompleted;
      if (isBasic && navigator.mounted) {
        navigator.pop();
      }
    }

    return !hasError.value && !isCancelled.value;
  }

  static Future<T?> showFutureProgressDialog<T>({
    required BuildContext context,
    required String title,
    required Future<T> Function() futureCallback,
  }) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const LinearProgressIndicator(),
              const SizedBox(height: 20),
              Text(CommonStrings.processing),
            ],
          ),
        );
      },
    );

    try {
      final result = await futureCallback();

      if (navigator.mounted) navigator.pop();
      return result;
    } catch (e) {
      if (navigator.mounted) navigator.pop();
      if (context.mounted) {
        ToastHelper.Show(context, "Error: $e");
      }
      return null;
    }
  }
}
