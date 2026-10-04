import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fstapp/theme_config.dart';
import 'package:fstapp/components/information/information_strings.dart';
import '../../html/html_view.dart';

class SongDialog extends StatefulWidget {
  final String title;
  final String description;
  final bool isDarkMode;

  const SongDialog({
    super.key,
    required this.title,
    required this.description,
    required this.isDarkMode,
  });

  @override
  _SongDialogState createState() => _SongDialogState();
}

class _SongDialogState extends State<SongDialog> {
  static double fontSize = 18;
  static const double fontSizeStep = 2;
  static const double maxFontSize = 50;
  static const double minFontSize = 8;
  static const double scrollThreshold = 30.0;
  static const Duration buttonFadeDelay = Duration(seconds: 3);

  final ScrollController _scrollController = ScrollController();
  double _buttonOpacity = 1;
  Timer? _fadeTimer;

  BuildContext? themedContext;

  double buttonVisibleOpacity(BuildContext context) =>
      ThemeConfig.isDarkMode(context) ? 1 : 0.9;
  static const double buttonHiddenOpacity = 0.4;
  static const int buttonFadeAnimationDuration = 400;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_updateButtonOpacity);
    _startFadeTimer(); // Start the fade-out timer
  }

  @override
  void dispose() {
    _scrollController.removeListener(_updateButtonOpacity);
    _scrollController.dispose();
    _fadeTimer?.cancel();
    super.dispose();
  }

  void _startFadeTimer() {
    _fadeTimer?.cancel();
    _fadeTimer = Timer(buttonFadeDelay, () {
      setState(() {
        _buttonOpacity = buttonHiddenOpacity;
      });
    });
  }

  void _updateButtonOpacity() {
    if (_scrollController.position.pixels <= scrollThreshold) {
      _fadeTimer?.cancel();
      setState(() {
        _buttonOpacity = buttonVisibleOpacity(themedContext ?? context);
      });
    } else {
      setState(() {
        _buttonOpacity = buttonHiddenOpacity;
      });
    }
    _startFadeTimer(); // Restart fade timer on interaction
  }

  @override
  Widget build(BuildContext context) {
    final themeData = widget.isDarkMode
        ? ThemeConfig.theme(brightness: Brightness.dark)
        : ThemeConfig.theme();

    return Theme(
      data: themeData,
      child: Builder(
        builder: (BuildContext context) {
          themedContext = context;
          return Dialog(
            insetPadding: EdgeInsets.zero,
            child: Container(
              width: MediaQuery.of(context).size.width,
              height: MediaQuery.of(context).size.height,
              color: ThemeConfig.backgroundColor(context),
              child: Stack(
                alignment: Alignment.topCenter,
                children: [
                  SingleChildScrollView(
                    controller: _scrollController,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        SizedBox(height: widget.title.length < 20 ? 32 : 54),
                        Container(
                          padding: const EdgeInsets.all(12),
                          alignment: Alignment.topCenter,
                          child: HtmlView(
                            html:
                                "<div style='text-align: center;'><h3>${widget.title}</h3>${widget.description}</div>",
                            isSelectable: true,
                            fontSize: fontSize,
                          ),
                        ),
                        SizedBox(height: 102),
                      ],
                    ),
                  ),
                  Positioned(
                    bottom: 20,
                    child: AnimatedOpacity(
                      opacity: _buttonOpacity,
                      duration:
                          Duration(milliseconds: buttonFadeAnimationDuration),
                      child: Row(
                        children: [
                          ElevatedButton(
                            onPressed: () {
                              setState(() {
                                fontSize = (fontSize - fontSizeStep)
                                    .clamp(minFontSize, maxFontSize);
                              });
                              _startFadeTimer(); // Restart fade timer
                            },
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 15),
                              backgroundColor:
                                  ThemeConfig.songButtonColor(context)
                                      .withOpacity(_buttonOpacity),
                              shadowColor: Colors.transparent,
                              elevation: 0,
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.remove,
                                    size: 28,
                                    color: ThemeConfig.whiteTextColor(context)),
                                const SizedBox(width: 8),
                                Text(InformationStrings.fontSmaller,
                                    style: TextStyle(
                                        color:
                                            ThemeConfig.whiteTextColor(context),
                                        fontSize: 18)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 20),
                          ElevatedButton(
                            onPressed: () {
                              setState(() {
                                fontSize = (fontSize + fontSizeStep)
                                    .clamp(minFontSize, maxFontSize);
                              });
                              _startFadeTimer(); // Restart fade timer
                            },
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 15),
                              backgroundColor:
                                  ThemeConfig.songButtonColor(context)
                                      .withOpacity(_buttonOpacity),
                              shadowColor: Colors.transparent,
                              elevation: 0,
                            ),
                            child: Row(
                              children: [
                                Text(InformationStrings.fontLarger,
                                    style: TextStyle(
                                        color:
                                            ThemeConfig.whiteTextColor(context),
                                        fontSize: 18)),
                                const SizedBox(width: 8),
                                Icon(Icons.add,
                                    size: 28,
                                    color: ThemeConfig.whiteTextColor(context)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 20,
                    left: 20,
                    child: AnimatedOpacity(
                      opacity: _buttonOpacity,
                      duration:
                          Duration(milliseconds: buttonFadeAnimationDuration),
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _fadeTimer?.cancel(); // Cancel timer on dialog close
                        },
                        style: ElevatedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.all(16),
                          backgroundColor: ThemeConfig.songButtonColor(context)
                              .withOpacity(_buttonOpacity),
                          shadowColor: Colors.transparent,
                          elevation: 0,
                        ),
                        child: Icon(Icons.adaptive.arrow_back,
                            color: ThemeConfig.whiteTextColor(context)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
