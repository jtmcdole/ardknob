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

import 'package:ardknob/ardproto.dart';
import 'package:ardknob/display.dart';

import 'package:test/test.dart';
import 'package:mockito/mockito.dart';

main() {
  group('Display', () {
    var disp;
    var proto;

    group('Display', () {
      setUp(() {
        proto = new ArdProtoMock();
        disp = new Display(proto);
      });

      test('display()', () async {
        disp.display();
        verify(proto.write([0]));
      });

      test('clear()', () async {
        disp.clear();
        verify(proto.write([1]));
      });

      test('fillDisplay()', () async {
        disp.fillDisplay(123);
        verify(proto.write([1, 0, 123]));
      });

      test('cursor()', () async {
        disp.cursor(10, 20);
        verify(proto.write([2, 0, 10, 0, 20]));
      });

      test('textSize()', () async {
        disp.textSize(20);
        verify(proto.write([3, 0, 20]));
      });

      test('textColor()', () async {
        disp.textColor(10);
        verify(proto.write([4, 0, 10]));

        disp.textColor(10, 20);
        verify(proto.write([4, 0, 10, 0, 20]));
      });

      test('text()', () async {
        disp.text('jtmcdole');
        verify(proto.write([5]..addAll('jtmcdole'.codeUnits)));
      });

      test('line()', () async {
        disp.line(10, 20, 30, 40, 50);
        verify(proto.write([6, 0, 10, 0, 20, 0, 30, 0, 40, 0, 50]));
      });

      test('triangle()', () async {
        disp.triangle(10, 20, 30, 40, 50, 60, 70);
        verify(
            proto.write([7, 0, 10, 0, 20, 0, 30, 0, 40, 0, 50, 0, 60, 0, 70]));
      });

      test('rectangle()', () async {
        disp.rectangle(10, 20, 30, 40, 1);
        verify(proto.write([9, 0, 10, 0, 20, 0, 30, 0, 40, 0, 1]));

        disp.rectangle(10, 20, 30, 40, 1, fill: true);
        verify(proto.write([10, 0, 10, 0, 20, 0, 30, 0, 40, 0, 1]));

        disp.rectangle(10, 20, 30, 40, 1, fill: true, radius: 20);
        verify(proto.write([12, 0, 10, 0, 20, 0, 30, 0, 40, 0, 20, 0, 1]));

        disp.rectangle(10, 20, 30, 40, 1, radius: 20);
        verify(proto.write([11, 0, 10, 0, 20, 0, 30, 0, 40, 0, 20, 0, 1]));
      });

      test('circle()', () async {
        disp.circle(10, 20, 30, 40);
        verify(proto.write([14, 0, 10, 0, 20, 0, 30, 0, 40]));

        disp.circle(10, 20, 30, 40, fill: true);
        verify(proto.write([13, 0, 10, 0, 20, 0, 30, 0, 40]));
      });

      test('bitmap()', () {
        int height = 15;
        int width = 20;
        var bits =
            new List<int>.generate(height * (width / 8).ceil(), (i) => i);
        when(proto.write(any)).thenReturn(new Future.value(true));

        disp.bitmap(5, 10, width, height, 48879, bits);
        verify(proto
            .write([15, 0, 5, 0, 10, 0, 20, 0, 15, 0xbe, 0xef]..addAll(bits)));

        disp.bitmap(5, 10, width, height, 48879, bits, background: 123);
        verify(proto.write(
            [16, 0, 5, 0, 10, 0, 20, 0, 15, 0xbe, 0xef, 0, 123]..addAll(bits)));

        disp.bitmap(5, 10, width, height, 48879, bits,
            background: 123, xmb: true);
        verify(proto.write(
            [18, 0, 5, 0, 10, 0, 20, 0, 15, 0xbe, 0xef, 0, 123]..addAll(bits)));

        disp.bitmap(5, 10, width, height, 48879, bits, xmb: true);
        verify(proto
            .write([17, 0, 5, 0, 10, 0, 20, 0, 15, 0xbe, 0xef]..addAll(bits)));

        disp.bitmap(5, 10, width, height, 48879, bits, xmb: true);
        verify(proto
            .write([17, 0, 5, 0, 10, 0, 20, 0, 15, 0xbe, 0xef]..addAll(bits)));

        reset(proto);
        when(proto.write(any)).thenReturn(new Future.value(true));

        height = 20;
        width = 20;
        bits = new List<int>.generate(height * (width / 8).ceil(), (i) => i);
        disp.bitmap(5, 10, width, height, 48879, bits, xmb: true);
        verifyInOrder([
          proto.write([17, 0, 5, 0, 10, 0, 20, 0, 16, 0xbe, 0xef]
            ..addAll(bits.take(16 * 3))),
          proto.write([17, 0, 5, 0, 26, 0, 20, 0, 4, 0xbe, 0xef]
            ..addAll(bits.skip(16 * 3))),
        ]);
      });
    });
  });
}

class ArdProtoMock extends Mock implements ArdProto {}
