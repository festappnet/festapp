import 'dart:async';

import 'package:flutter/material.dart';

class BlueprintMobileScrollView extends StatefulWidget {
  final Widget leftPanel;
  final Widget mainContent;
  final Widget rightPanel;
  final double screenWidth;

  const BlueprintMobileScrollView({
    super.key,
    required this.leftPanel,
    required this.mainContent,
    required this.rightPanel,
    required this.screenWidth,
  });

  @override
  State<BlueprintMobileScrollView> createState() =>
      _BlueprintMobileScrollViewState();
}

class _BlueprintMobileScrollViewState extends State<BlueprintMobileScrollView> {
  late final ScrollController _mobileHorizontalController;
  bool _canScrollLeft = false;
  bool _canScrollRight = true;
  Timer? _arrowFadeTimer;
  bool _arrowsVisible = true;
  bool _hasCenteredMobileView = false;

  @override
  void initState() {
    super.initState();
    _mobileHorizontalController = ScrollController();
    _mobileHorizontalController.addListener(_updateScrollArrows);
    _resetArrowFadeTimer();
  }

  @override
  void dispose() {
    _mobileHorizontalController.dispose();
    _arrowFadeTimer?.cancel();
    super.dispose();
  }

  void _updateScrollArrows() {
    if (!_mobileHorizontalController.hasClients) return;
    final offset = _mobileHorizontalController.offset;
    final maxScroll = _mobileHorizontalController.position.maxScrollExtent;

    final canScrollLeft = offset > 10;
    final canScrollRight = offset < maxScroll - 10;

    if (canScrollLeft != _canScrollLeft || canScrollRight != _canScrollRight) {
      setState(() {
        _canScrollLeft = canScrollLeft;
        _canScrollRight = canScrollRight;
      });
    }
    _resetArrowFadeTimer();
  }

  void _resetArrowFadeTimer() {
    _arrowFadeTimer?.cancel();
    if (!_arrowsVisible) {
      setState(() {
        _arrowsVisible = true;
      });
    }
    _arrowFadeTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _arrowsVisible = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasCenteredMobileView) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_mobileHorizontalController.hasClients) {
          _mobileHorizontalController.jumpTo(250.0);
          _updateScrollArrows();
        }
      });
      _hasCenteredMobileView = true;
    }

    return Stack(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          controller: _mobileHorizontalController,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 250,
                padding: const EdgeInsets.all(16.0),
                child: widget.leftPanel,
              ),
              Container(
                width: widget.screenWidth,
                padding: const EdgeInsets.symmetric(horizontal: 12.0),
                child: widget.mainContent,
              ),
              Container(
                width: 250,
                padding: const EdgeInsets.all(16.0),
                child: widget.rightPanel,
              ),
            ],
          ),
        ),
        if (_canScrollLeft)
          Align(
            alignment: Alignment.centerLeft,
            child: AnimatedOpacity(
              opacity: _arrowsVisible ? 1.0 : 0.3,
              duration: const Duration(milliseconds: 300),
              child: Padding(
                padding: const EdgeInsets.only(left: 8.0),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () {
                        final target =
                            (_mobileHorizontalController.offset - 250.0).clamp(
                                0.0,
                                _mobileHorizontalController
                                    .position.maxScrollExtent);
                        _mobileHorizontalController.animateTo(
                          target,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOut,
                        );
                      },
                      child: const Center(
                        child: Icon(Icons.chevron_left,
                            size: 24, color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (_canScrollRight)
          Align(
            alignment: Alignment.centerRight,
            child: AnimatedOpacity(
              opacity: _arrowsVisible ? 1.0 : 0.3,
              duration: const Duration(milliseconds: 300),
              child: Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () {
                        final target =
                            (_mobileHorizontalController.offset + 250.0).clamp(
                                0.0,
                                _mobileHorizontalController
                                    .position.maxScrollExtent);
                        _mobileHorizontalController.animateTo(
                          target,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOut,
                        );
                      },
                      child: const Center(
                        child: Icon(Icons.chevron_right,
                            size: 24, color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
