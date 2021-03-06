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

/// A simple screen paging library.
library pages;

import 'dart:async';

import 'package:ardknob/ardproto.dart';
import 'package:ardknob/display.dart';

import 'package:logging/logging.dart';

/// Events passed to [Page.onEvent] dealing with different page actions.
enum PageEvent {
  /// This [Page] has been added to a new [Book] (passed as data).
  added,

  /// This [Page] has been removed from the [Book] (passed as data).
  removed,

  /// This [Page] is now the active on-screen page.
  onScreen,

  /// This [Page] has been taken off-screen.
  offScreen,
}

/// Individual page to be displayed and interact with arduino evnets.
abstract class Page {
  final String name;

  /// Which book we are associated with.
  Book book;

  /// The current display this page is associated with.
  Display get display => _display;
  Display _display;

  Page(this.name);

  /// Handles different events generated by the [book].
  onEvent(PageEvent event, data);

  /// Handles physical actions on the device.
  ///
  /// Generally these actions only flow to the page after [PageEvent.onScreen]
  /// and before [PageEvent.offScreen].
  onKnob(KnobAction action);

  String toString() => "Page($name, $book)";
}

/// A [Page] container.
///
/// Flips pages, routes [PageEvent] and [KnobAction] to the active page.
///
/// ```
///   ┌──────────┐       ┌──────────┐
/// L │          │  L/R  │          │ R
/// ╔>│  page 1  │ <═══> │  page 2  │<╗
/// ║ │          │       │          │ ║
/// ║ └──────────┘       └──────────┘ ║
/// ╚═════════════════════════════════╝
/// ```
class Book {
  /// The arduino this book communicates with.
  final ArdProto proto;

  final String name;

  /// Which knob flips pages on [Direction.left] and [Direction.right].
  final int pageKnobId;

  /// Normal display through which the active page can render.
  final Display _display;

  /// No-op display through which non-active pages can flip off.
  final Display _displayNone;

  final Logger log = new Logger('Book');

  /// All of the pages in this book.
  List<Page> get pages => new List.from(_pages);
  List<Page> _pages;

  Book(this.name, ArdProto proto, {Display display, this.pageKnobId})
      : this.proto = proto,
        _pages = <Page>[],
        _display = display ?? new Display(proto),
        _displayNone = new DisplayNone(proto) {
    proto.onAction.listen(_onKnob);
  }

  /// Adds a page to the end of this book.
  ///
  /// If this page is in any book, it is first removed from that book.
  void add(Page page) {
    if (page.book != null) {
      // Re-adding the page to the end; ignore updates.
      if (_active == page) _active = null;
      page.book.remove(page);
    }
    page.book = this;
    _pages.add(page);
    if (_active == null) _active = page;
    page._display = _active == page ? _display : _displayNone;
    page.onEvent(PageEvent.added, this);
    if (_active == page) page.onEvent(PageEvent.onScreen, this);
    log.info("added $page");
  }

  /// Removes a page from this book, if it is inserted.
  bool remove(Page page) {
    log.info("removing $page");
    int idx = _pages.indexOf(page);
    if (idx == -1) return false;

    page._display = null;
    if (_active == page) page.onEvent(PageEvent.offScreen, this);

    _pages.removeAt(idx);
    page.onEvent(PageEvent.removed, this);
    page.book = null;
    if (_active == page) {
      if (_pages.isEmpty) {
        _active = null;
        return true;
      }
      // last element wraps around, else move right.
      _active = _pages[idx % _pages.length];
      _active.onEvent(PageEvent.onScreen, this);
    }
    return true;
  }

  /// Number of pages in this book.
  int get length => _pages.length;

  String toString() => "Book($name, $length)";

  /// Currently active page.
  Page get active => _active;
  Page _active;

  /// Handles all actions from the arduino and sends most to the current [Page].
  _onKnob(KnobAction knob) {
    log.info('$knob');

    if (_active == null) return;

    // If the knob is our page turner, handle page rotation and return.
    if (knob.id == pageKnobId) {
      switch (knob.direction) {
        case Direction.left:
          log.info('page turn left');
          turn(-1);
          return;
        case Direction.right:
          log.info('page turn right');
          turn(1);
          return;
        default:
          break;
      }
    }

    // Else, pass to the active page.
    _active.onKnob(knob);
  }

  /// Changes the active page by [pages] in either direction.
  bool turn([int pages = 1]) {
    var cur = _active;
    var idx = _pages.indexOf(cur);
    var next = _pages[(idx + pages) % _pages.length];
    if (cur == next) return false;

    cur._display = _displayNone;
    cur.onEvent(PageEvent.offScreen, this);
    next._display = _display;
    _active = next;
    next.onEvent(PageEvent.onScreen, this);
    return true;
  }
}

/// A display that performs no operations.
class DisplayNone implements Display {
  /// The arduino this non-operative display would talk to, if it cared.
  final ArdProto proto;

  final Logger log = new Logger('DisplayNone');

  DisplayNone(this.proto);

  noSuchMethod(invoke) {
    log.finer('${invoke.memberName}(${invoke.positionalArguments}, '
        '${invoke.namedArguments}) called');
    if (invoke.isMethod) return new Future.value(false);
  }
}
