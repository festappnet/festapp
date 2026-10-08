import 'package:adaptive_theme/adaptive_theme.dart';
import 'package:fstapp/components/users/user_strings.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:fstapp/router_service.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/components/app_management/language_model.dart';
import 'package:fstapp/data_services/auth_service.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/components/users/views/login_page.dart';
import 'package:fstapp/components/users/views/signup_page.dart';
import 'package:fstapp/services/dialog_helper.dart';
import 'package:fstapp/services/responsive_service.dart';
import 'package:fstapp/theme_config.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:flutter/material.dart';
import 'package:auto_route/auto_route.dart';
import 'package:fstapp/app_router.gr.dart';

class UserHeaderWidget extends StatefulWidget {
  final Color? appBarIconColor;
  final bool compact;
  final Future<void> Function()? onSignIn;
  final VoidCallback? onAdminPressed;
  const UserHeaderWidget(
      {super.key,
      this.appBarIconColor,
      this.onSignIn,
      this.onAdminPressed,
      this.compact = false});

  @override
  State<UserHeaderWidget> createState() => _UserHeaderWidgetState();
}

class _UserHeaderWidgetState extends State<UserHeaderWidget> {
  final GlobalKey _settingsKey = GlobalKey();
  final GlobalKey _userKey = GlobalKey();
  AdaptiveThemeMode? _currentThemeMode;

  // Define the popover width as a constant.
  static const double _popoverWidth = 300;

  @override
  void initState() {
    super.initState();
    AdaptiveTheme.getThemeMode().then((mode) {
      if (mounted) {
        setState(() {
          _currentThemeMode = mode;
        });
      }
    });
  }

  /// Returns the first letter of the user's name in uppercase.
  String _getUserInitial() {
    final user = RightsService.currentUser();
    String fullName = user?.name ?? "U";
    return fullName.isNotEmpty ? fullName[0].toUpperCase() : "U";
  }

  /// Extracted widget for the settings content (language & appearance).
  Widget _buildSettingsContentInner(StateSetter setState) {
    List<LanguageModel> languages = AppConfig.availableLanguages();
    LanguageModel currentLanguage = languages.firstWhere(
      (lang) => lang.locale.languageCode == context.locale.languageCode,
      orElse: () => languages.first,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (languages.length > 1) ...[
          Text(CommonStrings.languageSettings,
              style: TextStyle(
                  fontSize: 16, color: ThemeConfig.blackColor(context))),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                CommonStrings.currentLanguage(language: currentLanguage.name),
                style: TextStyle(
                    fontSize: 14, color: ThemeConfig.blackColor(context)),
              ),
              IconButton(
                onPressed: () async {
                  await DialogHelper.chooseLanguage(context);
                  setState(() {}); // refresh after language change
                },
                icon: Icon(
                  Icons.translate,
                  color: ThemeConfig.brandAccentColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
        if (ThemeConfig.isDarkModeEnabled)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(CommonStrings.appearance,
                  style: TextStyle(
                      fontSize: 16, color: ThemeConfig.blackColor(context))),
              const SizedBox(height: 8),
              ToggleButtons(
                isSelected: [
                  _currentThemeMode == AdaptiveThemeMode.dark,
                  _currentThemeMode == AdaptiveThemeMode.system,
                  _currentThemeMode == AdaptiveThemeMode.light,
                ],
                onPressed: (int index) {
                  AdaptiveThemeMode mode;
                  if (index == 0) {
                    mode = AdaptiveThemeMode.dark;
                  } else if (index == 1) {
                    mode = AdaptiveThemeMode.system;
                  } else {
                    mode = AdaptiveThemeMode.light;
                  }
                  AdaptiveTheme.of(context).setThemeMode(mode);
                  setState(() {
                    _currentThemeMode = mode;
                  });
                },
                borderRadius: BorderRadius.circular(8.0),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0),
                    child: Text(CommonStrings.dark,
                        style:
                            TextStyle(color: ThemeConfig.blackColor(context))),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0),
                    child: Text(CommonStrings.auto,
                        style:
                            TextStyle(color: ThemeConfig.blackColor(context))),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0),
                    child: Text(CommonStrings.light,
                        style:
                            TextStyle(color: ThemeConfig.blackColor(context))),
                  ),
                ],
              ),
            ],
          ),
      ],
    );
  }

  /// Common popover wrapper that applies constraints, decoration and places a cross button.
  Widget _buildPopoverWrapper(Widget content, {Widget? topLeftWidget}) {
    // Use a Builder so that we always have the current Theme.
    return Builder(
      builder: (context) {
        return Center(
          child: Stack(
            children: [
              Container(
                width: _popoverWidth,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: Theme.of(context).cardColor,
                ),
                child: content,
              ),
              Positioned(
                top: 4,
                right: 4,
                child: IconButton(
                  icon: Icon(
                    Icons.close,
                    size: 28,
                    color: ThemeConfig.blackColor(context),
                  ),
                  onPressed: () => Navigator.pop(context),
                  splashColor: Colors.transparent,
                  highlightColor: Colors.transparent,
                  hoverColor: Colors.transparent,
                ),
              ),
              if (topLeftWidget != null)
                Positioned(
                  top: 4,
                  left: 4,
                  child: topLeftWidget,
                ),
            ],
          ),
        );
      },
    );
  }

  /// Combined popover for signed in state.
  void _showSignedInPopover() {
    final rootRouter = context.router.root;
    final RenderBox? button =
        _userKey.currentContext?.findRenderObject() as RenderBox?;
    if (button == null) return;
    final Offset offset = button.localToGlobal(Offset.zero);
    final Size size = button.size;
    showMenu(
      context: context,
      constraints: const BoxConstraints(maxWidth: _popoverWidth),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      position: RelativeRect.fromLTRB(
        offset.dx,
        offset.dy + size.height,
        offset.dx + size.width,
        offset.dy,
      ),
      items: [
        PopupMenuItem(
          enabled: false,
          child: StatefulBuilder(
            builder: (context, localSetState) {
              final user = RightsService.currentUser();
              final String fullName = user?.name ?? CommonStrings.user;
              final String surname = user?.surname ?? "";
              final String email = user?.email ?? "";

              // Determine if the settings section has any content to show
              final bool hasLanguageSettings =
                  AppConfig.availableLanguages().length > 1;
              final bool hasThemeSettings = ThemeConfig.isDarkModeEnabled;
              final bool showSettingsSection =
                  hasLanguageSettings || hasThemeSettings;

              return _buildPopoverWrapper(
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: ThemeConfig.brandAccentColor,
                            width: 2,
                          ),
                          color: ThemeConfig.brandAccentColor,
                        ),
                        child: Center(
                          child: Text(
                            _getUserInitial(),
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: Column(
                        children: [
                          SelectableText(
                            "$fullName $surname",
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: ThemeConfig.blackColor(context)),
                          ),
                          const SizedBox(height: 4),
                          SelectableText(
                            email,
                            style: TextStyle(
                                fontSize: 14,
                                color: ThemeConfig.blackColor(context)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Conditionally render the settings block including its top divider
                    if (showSettingsSection) ...[
                      const Divider(),
                      const SizedBox(height: 16),
                      _buildSettingsContentInner(localSetState),
                      const SizedBox(height: 16),
                    ],

                    // This divider separates the content above from the sign out button
                    const Divider(),
                    ListTile(
                      leading: Icon(
                        Icons.logout,
                        color: Theme.of(context).primaryColor,
                      ),
                      title: Text(
                        UserStrings.signOut,
                        style: TextStyle(
                            fontSize: 16,
                            color: ThemeConfig.blackColor(context)),
                      ),
                      onTap: () async {
                        Navigator.pop(context);
                        await AuthService.logout();
                        await RouterService.goToApplicationHome(rootRouter);
                      },
                    ),
                  ],
                ),
                topLeftWidget: RightsService.isAdmin()
                    ? IconButton(
                        icon: Icon(
                          Icons.business,
                          size: 24, // Slightly smaller than close button (28)
                          color: ThemeConfig.blackColor(context),
                        ),
                        tooltip: "Platform Settings",
                        onPressed: () {
                          Navigator.pop(context);
                          context.router
                              .push(const OrganizationEditRedirectRoute());
                        },
                      )
                    : null,
              );
            },
          ),
        ),
      ],
    );
  }

  /// Popover for not-signed in state.
  void _showSettingsPopover() {
    final RenderBox? button =
        _settingsKey.currentContext?.findRenderObject() as RenderBox?;
    if (button == null) return;
    final Offset offset = button.localToGlobal(Offset.zero);
    final Size size = button.size;
    showMenu(
      context: context,
      constraints: const BoxConstraints(maxWidth: _popoverWidth),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      position: RelativeRect.fromLTRB(
        offset.dx,
        offset.dy + size.height,
        offset.dx + size.width,
        offset.dy,
      ),
      items: [
        PopupMenuItem(
          enabled: false,
          child: StatefulBuilder(
            builder: (context, localSetState) {
              return _buildPopoverWrapper(
                _buildSettingsContentInner(localSetState),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Unified widget for signed-in state (same for mobile and desktop).
  Widget _buildSignedInWidget(Color iconColor) {
    return InkWell(
      key: _userKey,
      onTap: _showSignedInPopover,
      child: SizedBox(
          width: widget.compact ? 40 : 38,
          height: widget.compact ? 40 : 38,
          child: Center(
              child: Container(
            width: widget.compact ? 36 : 38,
            height: widget.compact ? 36 : 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: ThemeConfig.brandAccentColor,
                width: 2,
              ),
              color: ThemeConfig.brandAccentColor,
            ),
            child: Center(
              // The bundled bold face has 0.682em cap height and 0.318em
              // descent. Center the capital itself, rather than its line box.
              child: Transform.translate(
                  offset: Offset(
                      0, MediaQuery.textScalerOf(context).scale(20) * .159),
                  child: Text(
                    _getUserInitial(),
                    textHeightBehavior: const TextHeightBehavior(
                        applyHeightToFirstAscent: false,
                        applyHeightToLastDescent: false),
                    style: TextStyle(
                      fontFamily: ThemeConfig.fontFamily,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      height: 1,
                      color: Colors.white,
                    ),
                  )),
            ),
          ))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isSignedIn = AuthService.isLoggedIn();
    final bool isMobile = ResponsiveService.isMobile(context);
    final iconColor = widget.appBarIconColor ?? ThemeConfig.blackColor(context);

    final canRegister =
        RightsService.occasionLinkModel?.organization?.isRegistrationEnabled ??
            false;
    final addEventButton = FilledButton(
      onPressed: () => RouterService.navigate(context, SignupPage.ROUTE),
      style: FilledButton.styleFrom(
        backgroundColor: ThemeConfig.brandAccentColor,
        foregroundColor: ThemeData.estimateBrightnessForColor(
                    ThemeConfig.brandAccentColor) ==
                Brightness.light
            ? Colors.black
            : Colors.white,
        padding: EdgeInsets.symmetric(horizontal: isMobile ? 10 : 18),
        minimumSize: const Size(0, 40),
      ),
      child: Text(UserStrings.addEvent),
    );

    // Define the admin button widget first if it exists
    Widget? adminButton;
    if (widget.onAdminPressed != null) {
      if (isMobile) {
        // Mobile version: Icon button
        adminButton = IconButton(
          padding: EdgeInsets.zero, // Remove padding for alignment
          constraints: const BoxConstraints(
            minWidth: 38, // Match avatar height
            minHeight: 38, // Match avatar height
          ),
          icon: Icon(
            Icons.confirmation_number_outlined,
            size: 32,
            color: iconColor,
          ),
          tooltip: UserStrings.myEvents,
          onPressed: widget.onAdminPressed,
        );
      } else {
        // Desktop version: Outlined button
        adminButton = OutlinedButton.icon(
          onPressed: widget.onAdminPressed,
          icon: Icon(
            Icons.confirmation_number_outlined,
            color: iconColor,
          ),
          label: Text(UserStrings.myEvents),
          style: OutlinedButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
            side: BorderSide(
              color: iconColor,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            textStyle: const TextStyle(fontSize: 16),
          ),
        );
      }
    }

    if (isSignedIn) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (adminButton != null) ...[
            adminButton,
            SizedBox(width: isMobile ? 24 : 16), // Adjust spacing
          ],
          _buildSignedInWidget(iconColor), // The user avatar
        ],
      );
    } else {
      // Non-signed in state remains platform-specific.
      if (isMobile) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (canRegister) ...[
              IconButton.filled(
                tooltip: UserStrings.addEvent,
                onPressed: () =>
                    RouterService.navigate(context, SignupPage.ROUTE),
                icon: const Icon(Icons.add),
              ),
              const SizedBox(width: 8),
            ],
            IconButton(
              key: _userKey,
              constraints: const BoxConstraints(
                minWidth: 32,
                minHeight: 32,
              ),
              icon: Icon(
                Icons.person,
                size: 32,
                color: iconColor,
              ),
              tooltip: UserStrings.signIn,
              onPressed: () async {
                await RouterService.navigate(context, LoginPage.ROUTE);
                await widget.onSignIn?.call();
                if (mounted) setState(() {});
              },
            ),
            const SizedBox(width: 8),
            IconButton(
              key: _settingsKey,
              constraints: const BoxConstraints(
                minWidth: 32,
                minHeight: 32,
              ),
              icon: Icon(
                Icons.settings,
                color: iconColor,
                size: 32,
              ),
              tooltip: CommonStrings.settings,
              onPressed: _showSettingsPopover,
            ),
          ],
        );
      } else {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (canRegister) ...[
              addEventButton,
              const SizedBox(width: 16),
            ],
            OutlinedButton.icon(
              onPressed: () async {
                await RouterService.navigate(context, LoginPage.ROUTE);
                await widget.onSignIn?.call();
                if (mounted) setState(() {}); // refresh after sign in
              },
              icon: Icon(
                Icons.person,
                color: iconColor,
              ),
              label: Text(UserStrings.signIn),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
                side: BorderSide(
                  color: iconColor,
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                textStyle: const TextStyle(fontSize: 16),
              ),
            ),
            const SizedBox(width: 16),
            IconButton(
              key: _settingsKey,
              onPressed: _showSettingsPopover,
              icon: Icon(
                Icons.settings,
                color: iconColor,
                size: 28,
              ),
              tooltip: CommonStrings.settings,
            ),
          ],
        );
      }
    }
  }
}
