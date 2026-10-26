import 'dart:typed_data';
import 'package:venue_seat_picker/editor_ui.dart';

/// Retained domain names delegate to the canonical editor palette algorithm.
List<String> ticketImagePalette(Uint8List rgba, {int limit = 5}) =>
    editorImagePalette(rgba, limit: limit);
List<String> ticketArtworkSuggestions(Uint8List rgba) =>
    editorArtworkSuggestions(rgba);
