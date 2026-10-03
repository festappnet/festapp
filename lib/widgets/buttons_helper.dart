import 'package:fstapp/app_config.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/theme_config.dart';

class ButtonsHelper {
  static List<Visibility> getAddToMyProgramButton(
      bool? canSaveToMyProgram,
      Future<void> Function() addToMyProgram,
      Future<void> Function() removeFromMyProgram,
      [Color? colorIn,
      Color? colorOut]) {
    return [
      Visibility(
          visible:
              AppConfig.isOwnProgramSupported && canSaveToMyProgram == true,
          child: IconButton(
              onPressed: () async {
                await addToMyProgram();
              },
              icon: Icon(Icons.add_circle_outline, color: colorOut))),
      Visibility(
          visible:
              AppConfig.isOwnProgramSupported && canSaveToMyProgram == false,
          child: IconButton(
              onPressed: () async {
                await removeFromMyProgram();
              },
              icon: Icon(
                Icons.check_circle,
                color: colorIn,
              ))),
    ];
  }

  /// The app's standard in-page action button (the event page's sign-in /
  /// sign-out style): a [ThemeConfig.bigButtonColor] pill with rounded
  /// corners, optional leading icon and bold label. [expand] stretches it to
  /// the available width (anchored dialog actions); default hugs the content
  /// (button rows).
  static Widget actionButton({
    required BuildContext context,
    required String label,
    required VoidCallback onPressed,
    IconData? icon,
    bool expand = false,
  }) {
    final Color fg = ThemeConfig.blackColor(context);
    return Material(
      color: ThemeConfig.bigButtonColor(context),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20, color: fg),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: fg, fontWeight: FontWeight.bold, fontSize: 15)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget bigButton({
    required BuildContext context,
    required String label,
    VoidCallback? onPressed,
    Color? color,
    Color? textColor,
    bool isEnabled = true,
    double height = 50.0,
    double width = 250.0,
  }) {
    color ??= ThemeConfig.bigButtonColor(context);
    return Container(
      constraints: BoxConstraints(minHeight: height),
      width: width,
      decoration: BoxDecoration(
        color: isEnabled ? color : ThemeConfig.grey380(context),
        borderRadius: BorderRadius.circular(20),
      ),
      child: TextButton(
        onPressed: isEnabled ? onPressed : null,
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: textColor ?? ThemeConfig.textColorForBackground(color),
            fontSize: 25,
          ),
        ),
      ),
    );
  }

  static Widget bottomBarButton(
      {required String text, required VoidCallback? onPressed}) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: MaterialButton(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        color: Colors.black87,
        onPressed: onPressed,
        child: Text(
          text,
          style: TextStyle(color: Colors.grey.shade200),
        ),
      ),
    );
  }

  static Widget buildReferenceButton({
    required BuildContext context,
    required VoidCallback onPressed,
    required String label,
    IconData? icon, // Optional icon parameter
    Color? buttonColor,
    Color? iconColor,
    Color? textColor,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.transparent,
      ),
      child: IntrinsicWidth(
        child: TextButton.icon(
          onPressed: onPressed,
          iconAlignment: IconAlignment.end,
          icon: Icon(
            icon ?? Icons.qr_code, // Default to QR code icon if none provided
            color:
                iconColor ?? ThemeConfig.blackColor(context), // Set icon color
          ),
          label: Text(
            label,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: textColor ??
                  ThemeConfig.blackColor(context), // Set label color
            ),
          ),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.all(12.0),
            backgroundColor: buttonColor ??
                ThemeConfig.qrButtonColor(context), // Set button color
            minimumSize: const Size.fromHeight(60),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
    );
  }

  static Widget primaryButton({
    required BuildContext context,
    required VoidCallback? onPressed,
    required String label,
    bool isLoading = false,
    double height = 50.0,
    double? width,
    EdgeInsetsGeometry? padding,
    double borderRadius = 8.0,
    Widget? prefixIcon,
    Widget? suffixIcon,
    bool? isEnabled,
  }) {
    return Container(
      constraints: BoxConstraints(minHeight: height),
      width: width ?? double.infinity,
      child: ElevatedButton(
        onPressed: (isEnabled ?? true) && !isLoading ? onPressed : null,
        style: ElevatedButton.styleFrom(
          padding: padding ?? EdgeInsets.symmetric(horizontal: 16.0),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(borderRadius),
          ),
          backgroundColor: (isEnabled ?? true)
              ? Theme.of(context).primaryColor
              : Theme.of(context).disabledColor,
          foregroundColor: Theme.of(context).colorScheme.onPrimary,
          elevation: (isEnabled ?? true) && !isLoading ? 4.0 : 0,
          shadowColor: Colors.black26,
        ),
        child: isLoading
            ? CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(
                  Theme.of(context).colorScheme.onPrimary,
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (prefixIcon != null) ...[
                    prefixIcon,
                    const SizedBox(width: 8.0),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (suffixIcon != null) ...[
                    const SizedBox(width: 8.0),
                    suffixIcon,
                  ],
                ],
              ),
      ),
    );
  }
}
