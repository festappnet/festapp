import 'package:material_ui/material_ui.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:fstapp/theme_config.dart';

enum ToastSeverity { Ok, NotOk }

class ToastHelper {
  static Future<void> Show(BuildContext context, String value,
      {ToastSeverity severity = ToastSeverity.Ok}) async {
    Color color = ThemeConfig.seed1;
    var hexCode = '#${color.value.toRadixString(16).substring(2, 8)}';
    String webColor = hexCode;
    if (severity != ToastSeverity.Ok) {
      color = Colors.red;
      webColor = "#d8392b";
    }
    await Fluttertoast.showToast(
        msg: value,
        timeInSecForIosWeb: 3,
        webBgColor: webColor,
        backgroundColor: color,
        webPosition: "left");
  }
}
