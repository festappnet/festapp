import 'dart:convert';
import 'package:venue_layout_core/venue_layout_core.dart';

void main() =>
    print(jsonEncode({'protocol': layoutProtocol, 'limits': layoutLimits}));
