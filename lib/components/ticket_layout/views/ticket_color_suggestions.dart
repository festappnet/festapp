import 'package:flutter/widgets.dart';
import '../ticket_layout_strings.dart';

/// Localization adapter shared by ticket color consumers. Controls and palettes
/// live exclusively in venue_seat_picker/editor_ui.dart.
String ticketEditorColorLabel(BuildContext context, String label) =>
    switch (label) {
      'Opacity' =>
        Localizations.localeOf(context).languageCode == 'cs' ? 'Krytí' : label,
      'Cancel' => TicketLayoutStrings.cancel,
      'Apply' => TicketLayoutStrings.apply,
      'Used colors' => TicketLayoutStrings.usedColors,
      'From artwork' => TicketLayoutStrings.imageColors,
      'Artwork colors' => TicketLayoutStrings.imageColors,
      'Image colors' => TicketLayoutStrings.imageColors,
      'Basic colors' => TicketLayoutStrings.basicColors,
      'Swap colors' => TicketLayoutStrings.swapColors,
      _ => label,
    };
