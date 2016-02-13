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

/// A simple display driver written on top of [ArdProto].
library display;

import 'dart:async';
import 'package:ardknob/ardproto.dart';

class Display {
  final ArdProto proto;

  Display(this.proto);

  /// Updates the physical display with the offscreen buffer.
  Future<bool> display() => proto.write(0);

  /// Clears the offscreen buffer.
  Future<bool> clear() => proto.write(1);

  /// Fills the offscreen buffer with a color.
  Future<bool> fillDisplay(int color) => proto.write(1, _s2b(color));

  /// Moves the curosr to a new (x, y) location for certain display calls.
  Future<bool> cursor(int x, int y) => proto.write(2, _s2b(x)..addAll(_s2b(y)));

  /// Changes the text size for any future calls to [text].
  Future<bool> textSize(int size) => proto.write(3, _s2b(size));

  /// Changes the foreground, and optionally background colors for any future
  /// calls to [text].
  Future<bool> textColor(int fg, [int bg]) => (bg != null)
      ? proto.write(4, _s2b(fg)..addAll(_s2b(bg)))
      : proto.write(4, _s2b(fg));

  /// Renders text to the [cursor] location at [textSize] and with colors set by
  /// [textColor].
  Future<bool> text(String text) => proto.write(5, text.codeUnits);

  /// Draw a line from (x, y) to (x1, y1) with color.
  Future<bool> line(int x0, int y0, int x1, int y1, int color) => proto.write(
      6,
      _s2b(x0)
        ..addAll(_s2b(y0))
        ..addAll(_s2b(x1))
        ..addAll(_s2b(y1))
        ..addAll(_s2b(color)));

  /// Draw a triangle between three points with color.
  Future<bool> triangle(
          int x0, int y0, int x1, int y1, int x2, int y2, int color,
          {bool fill: false}) =>
      proto.write(
          fill ? 8 : 7,
          _s2b(x0)
            ..addAll(_s2b(y0))
            ..addAll(_s2b(x1))
            ..addAll(_s2b(y1))
            ..addAll(_s2b(x2))
            ..addAll(_s2b(y2))
            ..addAll(_s2b(color)));

  Future<bool> rectangle(int x, int y, int width, int height, int color,
          {bool fill: false, int radius}) =>
      proto.write(
          (fill ? 10 : 9) + ((radius != null) ? 2 : 0),
          _s2b(x)
            ..addAll(_s2b(y))
            ..addAll(_s2b(width))
            ..addAll(_s2b(height))
            ..addAll(radius != null ? _s2b(radius) : const <int>[])
            ..addAll(_s2b(color)));

  Future<bool> circle(int x, int y, int radius, int color,
          {bool fill: false}) =>
      proto.write(fill ? 13 : 14,
          _s2b(x)..addAll(_s2b(y))..addAll(_s2b(radius))..addAll(_s2b(color)));

  /// Draw normal or xmb bitmap (1 bit, 8 pixels per byte.)
  ///
  /// This will break up large bitmaps in to multiple batches of grouped
  /// scanlines. The future returned completes with the success of all work.
  Future<bool> bitmap(
      int x, int y, int width, int height, int color, Iterable<int> bytes,
      {int background, bool xmb: false}) {
    // num pixels wide / 8 pixels per byte.
    int scan = (width / 8).ceil();

    // either 49 or 47 bytes for per-packet data (sucks).
    int linesPer =
        (ArdProto.maxDataLength - ((background == null) ? 10 : 12)) ~/ scan;
    var work = [];
    for (int i = 0; i < height; i += linesPer) {
      var h = (height - i).clamp(0, linesPer);
      var fut = proto.write(
          (background == null ? 15 : 16) + (xmb ? 2 : 0),
          _s2b(x)
            ..addAll(_s2b(y + i))
            ..addAll(_s2b(width))
            ..addAll(_s2b(h))
            ..addAll(_s2b(color))
            ..addAll(background == null ? const <int>[] : _s2b(background))
            ..addAll(bytes.skip(scan * i).take(h * scan)));
      work.add(fut);
    }
    return Future.wait(work).then((work) => work.every((e) => e == true));
  }

  // Return network order bytes for the 16 bits in [short]
  List<int> _s2b(int short) => [(short >> 8) & 0xFF, short & 0xFF];
}
