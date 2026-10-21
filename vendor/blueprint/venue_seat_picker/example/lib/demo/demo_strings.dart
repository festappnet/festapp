import 'package:flutter/widgets.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';

/// The demo selects Czech; the reusable catalog belongs to the package.
String demoText(String text) =>
    const VenueLayoutLocalizations(Locale('cs')).text(text);
