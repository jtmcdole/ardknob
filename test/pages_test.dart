// Copyright 2016 John McDole <john@mcdole.org>
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'dart:async';
import 'dart:mirrors';

import 'package:ardknob/ardproto.dart';
import 'package:ardknob/display.dart';
import 'package:ardknob/pages.dart';

import 'package:test/test.dart';
import 'package:mockito/mockito.dart';

main() {
  delay() => new Future.value();

  group('Book', () {
    test('add', () {
      var page = new TestPage('page');
      var book = new Book('book', new ArdProtoMock());
      expect(page.book, isNull);
      expect(page.display, isNull);

      book.add(page);
      expect(page.events, [PageEvent.added, book]);
      expect(page.book, book);
      expect(page.display, isNotNull);
      expect(book.length, 1);
      expect(book.active, page);
      page.events.clear();

      book.add(page);
      expect(page.events, [PageEvent.removed, book, PageEvent.added, book]);
      expect(page.book, book);
      expect(book.length, 1);

      var page2 = new TestPage('page2');
      book..add(page2)..add(page);
      expect(book.pages, [page2, page], reason: 're-inserted pages go in back');
      expect(book.active, page);
    });

    test('remove', () {
      var page = new TestPage('page');
      var book = new Book('book', new ArdProtoMock());

      book.add(page);
      expect(book.remove(page), isTrue);
      expect(page.book, isNull);
      expect(page.display, isNull);
      expect(book.length, 0);

      var page2 = new TestPage('page2');
      book..add(page)..add(page2)..add(page); // cheap 'end of list'
      expect(book.remove(page), isTrue);
      expect(book.active, page2);
      expect(book.remove(page), isFalse);
    });

    test('page turns', () async {
      var page1 = new TestPage('page1');
      var page2 = new TestPage('page2');
      var proto = new ArdProtoMock();
      var book = new Book('turn', proto, debug: true, pageKnobId: 2)
        ..add(page1)
        ..add(page2);

      expect(page1.display, isNot(page2.display),
          reason: 'active page has different display');
      expect(book.active, page1);

      page1.events.clear();
      page2.events.clear();

      var right = new KnobAction(2, Direction.right);
      var left = new KnobAction(2, Direction.left);

      proto._knobAction.add(right);
      await delay();
      expect(book.active, page2);
      expect(page1.knobs, isEmpty);
      expect(page2.knobs, isEmpty);

      proto._knobAction.add(right);
      await delay();
      expect(book.active, page1);
      proto._knobAction.add(left);
      await delay();
      expect(book.active, page2);
      proto._knobAction.add(left);
      await delay();
      expect(book.active, page1);

      expect(page1.events, [
        PageEvent.offScreen,
        book,
        PageEvent.onScreen,
        book,
        PageEvent.offScreen,
        book,
        PageEvent.onScreen,
        book,
      ]);
      expect(page2.events, [
        PageEvent.onScreen,
        book,
        PageEvent.offScreen,
        book,
        PageEvent.onScreen,
        book,
        PageEvent.offScreen,
        book,
      ]);
    });

    test('other knobs', () async {
      var page1 = new TestPage('page1');
      var page2 = new TestPage('page2');
      var proto = new ArdProtoMock();
      var book = new Book('turn', proto, debug: true)..add(page1)..add(page2);

      var knob1r = new KnobAction(1, Direction.right);
      var knob0d = new KnobAction(0, Direction.down);
      proto._knobAction..add(knob1r)..add(knob0d)..add(knob1r);

      await delay();
      await delay();
      await delay();

      expect(page1.knobs, [knob1r, knob0d, knob1r]);
      expect(page2.knobs, isEmpty);
    });
  });

  group('Page', () {
    test('displayNone', () {
      var page1 = new TestPage('page1');
      var page2 = new TestPage('page2');
      var proto = new ArdProtoMock();
      var book = new Book('turn', proto, debug: true)..add(page1)..add(page2);

      page2.display.display();
      page2.display.clear();
      page2.display.rectangle(10, 20, 30, 40);
    });
  });
}

class TestPage extends Page {
  TestPage(String name) : super(name);

  List events = [];
  onEvent(event, [data]) {
    events.addAll([event, data]);
  }

  List<KnobAction> knobs = [];
  onKnob(knob) {
    knobs.add(knob);
  }
}

class ArdProtoMock extends Mock implements ArdProto {
  StreamController<KnobAction> _knobAction = new StreamController<KnobAction>();

  /// Stream of actions reported by the arduino.
  Stream<KnobAction> get onAction => _knobAction.stream;

  noSuchMethod(i) => super.noSuchMethod(i);
}
