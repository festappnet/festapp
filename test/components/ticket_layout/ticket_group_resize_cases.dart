import 'dart:convert';
import 'dart:io';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/ticket_layout/models/ticket_layout.dart';
import 'package:fstapp/components/ticket_layout/ticket_layout_controller.dart';

void main() {
  TicketTemplate fixture() => TicketTemplate.fromJson(jsonDecode(
      File('test/fixtures/ticket_layout/resolve.json')
          .readAsStringSync())['template']);

  test('decimal gallery QR boxes stay square through repeated JSON roundtrips',
      () {
    final raw =
        fixture().elements.firstWhere((e) => e.binding == 'qr').toJson();
    raw['box'] = {
      'x': 445.0393700787402,
      'y': 119.05511811023622,
      'width': 79.37007874015745,
      'height': 79.3700787401575
    };
    var element = TicketElement.fromJson(raw);
    final canonical = element.toJson();
    for (var i = 0; i < 5; i++) {
      expect(element.box.width, element.box.height);
      expect(
          element.toJson()['box']['width'], element.toJson()['box']['height']);
      element = TicketElement.fromJson(element.toJson());
      expect(element.toJson(), canonical);
    }
    raw['box']['height'] = 85.0;
    final nonsquare = TicketElement.fromJson(raw);
    expect(nonsquare.box.width, isNot(nonsquare.box.height));
  });

  test('group scaling changes boxes, spacing and fonts in one undo step', () {
    final c = TicketLayoutController(fixture());
    addTearDown(c.dispose);
    c.selectAll(c.document.elements.map((e) => e.id));
    final before = c.document;
    final bounds = c.selectionBounds!;
    c.beginGesture();
    c.resize(Offset(-bounds.width * .05, -bounds.height * .05));
    c.endGesture();
    final qr = c.document.elements.firstWhere((e) => e.binding == 'qr');
    expect(qr.box.width, qr.box.height);
    expect(qr.box.width, greaterThanOrEqualTo(60));
    final text =
        before.elements.firstWhere((e) => !['qr', 'logo'].contains(e.binding));
    final after = c.document.elements.firstWhere((e) => e.id == text.id);
    expect(after.fontSize, lessThan(text.fontSize));
    expect(after.box.width, lessThan(text.box.width));
    c.undo();
    expect(c.document.toJson(), before.toJson());
    c.redo();
    expect(
        c.document.elements.firstWhere((e) => e.id == text.id).box, after.box);
  });

  test('group scaling preserves locked elements and clamps extreme shrinking',
      () {
    final c = TicketLayoutController(fixture());
    addTearDown(c.dispose);
    final locked = c.document.elements.firstWhere((e) => e.binding != 'qr');
    c.change(locked.copyWith(locked: true));
    c.selectAll(c.document.elements.map((e) => e.id));
    c.resize(const Offset(-10000, -10000));
    expect(c.document.elements.firstWhere((e) => e.id == locked.id).box,
        locked.box);
    final qr = c.document.elements.firstWhere((e) => e.binding == 'qr');
    expect(qr.box.width, qr.box.height);
    expect(qr.box.width, greaterThanOrEqualTo(60));
    for (final e in c.document.elements) {
      expect(e.fontSize, greaterThanOrEqualTo(e.minFontSize));
    }
  });
}
