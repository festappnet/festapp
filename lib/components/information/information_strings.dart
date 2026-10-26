import 'package:easy_localization/easy_localization.dart';

/// Localized strings for the information feature (info pages, game, songbook).
/// Keys live under the "FeatureInformation" namespace in
/// assets/translations/*.json.
class InformationStrings {
  static String get information =>
      'FeatureInformation.information'.tr(); // "Information"

  // Game
  static String get gameSignIn => 'FeatureInformation.gameSignIn'
      .tr(); // "Sign in to participate in the game."
  static String get gameNeedsGroup => 'FeatureInformation.gameNeedsGroup'
      .tr(); // "For playing the game, you must be assigned to a game group"
  static String get gameNotStarted => 'FeatureInformation.gameNotStarted'
      .tr(); // "Game has not started yet"
  static String get gameEnded =>
      'FeatureInformation.gameEnded'.tr(); // "Game has ended"
  static String gameCheckPoint({required String title}) =>
      'FeatureInformation.gameCheckPoint'
          .tr(namedArgs: {'title': title}); // "Check point {title}"
  static String gameTimeLeft({required String time}) =>
      'FeatureInformation.gameTimeLeft'
          .tr(namedArgs: {'time': time}); // "Time left: {time}"
  static String get gameTakeAGuess =>
      'FeatureInformation.gameTakeAGuess'.tr(); // "Take a guess"
  static String get gameGuess =>
      'FeatureInformation.gameGuess'.tr(); // "Guess!"
  static String get offlineWarning => 'FeatureInformation.offlineWarning'
      .tr(); // "You are offline. Please check your internet connection."

  // Game guess feedback
  static String get gameCorrect =>
      'FeatureInformation.gameCorrect'.tr(); // "Correct!"
  static String get gameIncorrect =>
      'FeatureInformation.gameIncorrect'.tr(); // "Incorrect, try again!"
  static String get gameNotInOccasion => 'FeatureInformation.gameNotInOccasion'
      .tr(); // "You are not part of this occasion."
  static String get gameNotInGroup => 'FeatureInformation.gameNotInGroup'
      .tr(); // "You are not part of a game group."
  static String get gameOutsideWindow => 'FeatureInformation.gameOutsideWindow'
      .tr(); // "Guessing is only allowed within the game time window."
  static String get gameAnswerNotSetForCheckPoint =>
      'FeatureInformation.gameAnswerNotSetForCheckPoint'
          .tr(); // "Correct answer for this check point was not set."
  static String get gameAnswerNotSet => 'FeatureInformation.gameAnswerNotSet'
      .tr(); // "Correct answer was not set."

  // Songbook
  static String get fontSmaller =>
      'FeatureInformation.fontSmaller'.tr(); // "Smaller"
  static String get fontLarger =>
      'FeatureInformation.fontLarger'.tr(); // "Larger"
}
