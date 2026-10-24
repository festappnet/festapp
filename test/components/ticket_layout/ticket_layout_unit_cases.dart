import 'package:flutter_test/flutter_test.dart';

import 'ticket_image_palette_cases.dart' as suite0;
import 'ticket_layout_saver_cases.dart' as suite1;

import 'ticket_group_resize_cases.dart' as ticket_group_resize;

// Scoped groups share one engine; process-global fixtures stay isolated.
void main() {
  group('ticket_image_palette', suite0.main);
  group('ticket_layout_saver', suite1.main);
  group('ticket_group_resize', ticket_group_resize.main);
}
