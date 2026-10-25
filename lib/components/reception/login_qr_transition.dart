import 'package:material_ui/material_ui.dart';

enum LoginQrTransitionState { signingIn, success }

class LoginQrTransition extends StatelessWidget {
  const LoginQrTransition({
    required this.state,
    required this.title,
    required this.subtitle,
    super.key,
  });

  final LoginQrTransitionState state;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final success = state == LoginQrTransitionState.success;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return ColoredBox(
      color: colors.surface,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Semantics(
            container: true,
            liveRegion: true,
            label: '$title. $subtitle',
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                elevation: 0,
                color: colors.surfaceContainerHigh,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
                  child: AnimatedSwitcher(
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 250),
                    child: Column(
                      key: ValueKey(state),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (success)
                          TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0.75, end: 1),
                            duration: reduceMotion
                                ? Duration.zero
                                : const Duration(milliseconds: 320),
                            curve: Curves.easeOutBack,
                            builder: (context, scale, child) =>
                                Transform.scale(scale: scale, child: child),
                            child: Container(
                              width: 88,
                              height: 88,
                              decoration: BoxDecoration(
                                color: colors.primary,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.check_rounded,
                                  size: 58, color: colors.onPrimary),
                            ),
                          )
                        else
                          SizedBox(
                            width: 72,
                            height: 72,
                            child: CircularProgressIndicator(
                                strokeWidth: 6, color: colors.primary),
                          ),
                        const SizedBox(height: 28),
                        Text(title,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        Text(subtitle,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyLarge
                                ?.copyWith(color: colors.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
