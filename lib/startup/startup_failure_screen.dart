import 'package:flutter/material.dart';

/// Does not depend on localization assets or storage that may have stalled.
class StartupFailureScreen extends StatelessWidget {
  final VoidCallback? onRetry;
  final String phase;
  final String language;
  final bool storageOpenFailed;
  const StartupFailureScreen(
      {super.key,
      this.onRetry,
      required this.phase,
      required this.language,
      this.storageOpenFailed = false});

  @override
  Widget build(BuildContext context) {
    final copy = switch (language) {
      'cs' => (
          'Aplikaci se nepodařilo spustit. Zkuste ji znovu otevřít.',
          'Zkusit znovu',
          'Kód pro podporu'
        ),
      'sk' => (
          'Aplikáciu sa nepodarilo spustiť. Skúste ju znovu otvoriť.',
          'Skúsiť znova',
          'Kód pre podporu'
        ),
      'de' => (
          'Die App konnte nicht starten. Bitte öffnen Sie sie erneut.',
          'Erneut versuchen',
          'Support-Code'
        ),
      'pl' => (
          'Nie udało się uruchomić aplikacji. Otwórz ją ponownie.',
          'Spróbuj ponownie',
          'Kod pomocy'
        ),
      'uk' => (
          'Не вдалося запустити застосунок. Відкрийте його знову.',
          'Спробувати знову',
          'Код підтримки'
        ),
      _ => (
          'The app could not start. Please open it again.',
          'Try again',
          'Support code'
        ),
    };
    final message = !storageOpenFailed
        ? copy.$1
        : switch (language) {
            'cs' =>
              'Úložiště aplikace se neotevřelo. Zavřete ostatní karty Festapp a zkuste to znovu.',
            'sk' =>
              'Úložisko aplikácie sa neotvorilo. Zavrite ostatné karty Festapp a skúste to znova.',
            'de' =>
              'Der App-Speicher konnte nicht geöffnet werden. Schließen Sie andere Festapp-Tabs und versuchen Sie es erneut.',
            'pl' =>
              'Nie udało się otworzyć pamięci aplikacji. Zamknij inne karty Festapp i spróbuj ponownie.',
            'uk' =>
              'Не вдалося відкрити сховище застосунку. Закрийте інші вкладки Festapp і спробуйте знову.',
            _ =>
              'App storage could not open. Close other Festapp tabs and try again.',
          };
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            Text('${copy.$3}: $phase'),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton(onPressed: onRetry, child: Text(copy.$2)),
            ],
          ]),
        ),
      ),
    );
  }
}
