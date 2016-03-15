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

import 'package:logging/logging.dart';
import 'package:quiver/testing/async.dart';
import 'package:serial_port/serial_port.dart';
import 'package:test/test.dart';
import 'package:mockito/mockito.dart';

main() {
  var libMirror = currentMirrorSystem().findLibrary(#ardproto);

  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((LogRecord rec) {
    print('${rec.level.name}: ${rec.time}: ${rec.message}');
  });

  group('ArdProto', () {
    var port;
    var proto;
    var inst;
    var waitQ;
    var ackQ;

    getSym(String sym) => MirrorSystem.getSymbol(sym, libMirror);

    setUp(() {
      port = new MockSerialPort();
      proto = new ArdProto(port);
      inst = reflect(proto);
      waitQ = inst.getField(getSym('_waitQueue')).reflectee;
      ackQ = inst.getField(getSym('_ackQueue')).reflectee;
    });

    test('appends valid fletcher16 checksum', () async {
      proto.write([1, 1, 2, 3]);
      var cap = verify(port.write(captureAny)).captured;
      expect(cap.length, 1);
      expect(cap[0], isList);
      expect(ArdProto.fletcher16(cap[0], cap[0].length), equals(0),
          reason: 'ArdProto appends the fletcher 16 check bytes that sum to '
              'zero on the receiving end');
    });

    test('throws an error when overflowed', () async {
      try {
        await proto.write(new List(ArdProto.maxPacketSize - 3));
        fail('maxPacketSize didn\'t throw');
      } catch (e) {
        expect(e, isArgumentError);
      }
    });

    test('sends knob action updates', () async {
      var stream = proto.onAction;
      enc(id, dir) => ((id & 0x1F) << 3) | (dir.index & 0x7);
      port._host
        ..add([enc(1, Direction.left), 0x13])
        ..add([enc(2, Direction.right)])
        ..add([0x13])
        ..add([enc(3, Direction.down), 0x13])
        ..add([enc(0, Direction.up), 0x13]);

      var actions;
      try {
        actions =
            await stream.take(4).timeout(const Duration(seconds: 1)).toList();
      } catch (e) {
        fail('failed to receive 4 actions');
      }
      expect(actions[0].id, 1, reason: 'id = 1');
      expect(actions[0].direction, Direction.left, reason: 'knob.left');
      expect(actions[1].id, 2, reason: 'id = 2');
      expect(actions[1].direction, Direction.right, reason: 'knob.right');
      expect(actions[2].id, 3, reason: 'id = 3');
      expect(actions[2].direction, Direction.down, reason: 'knob.down');
      expect(actions[3].id, 0, reason: 'id = 0');
      expect(actions[3].direction, Direction.up, reason: 'knob.up');
    });

    test('queues up work to prevent overflows', () {
      expect(waitQ, isList);
      expect(waitQ, isEmpty);
      proto.write(new List<int>.filled(ArdProto.maxPacketSize - 4, 1));
      expect(proto.bytesOut, equals(ArdProto.maxPacketSize));
      proto.write([1]);
      expect(waitQ, isNotEmpty);
      expect(waitQ.length, 1);
    });

    test('close', () async {
      var futs = [
        proto.write(new List<int>.filled(ArdProto.maxPacketSize - 4, 1)),
        proto.write(new List<int>.filled(ArdProto.maxPacketSize - 4, 1))
      ];
      expect(waitQ.length, 1);
      expect(ackQ.length, 1);

      await proto.close();

      expect(waitQ, isEmpty);
      expect(ackQ, isEmpty);
      expect(await futs[0], isFalse);
      expect(await futs[1], isFalse);
    });

    test('acks', () async {
      // Setup one to flow through, followed by queueing up two more.
      var futs = [
        proto.write(new List<int>.filled(ArdProto.maxPacketSize - 4, 1)),
        proto.write([2]),
        proto.write([3]),
      ];

      port._host..add([0, 1])..add([1, 2])..add([2, 3]);

      futs = await Future.wait(futs);
      expect(futs, [true, true, true]);
    });

    test('odd acks', () async {
      // change ack for fun and profit.
      int ack = 0x100; // 256 rollover.
      inst.setField(getSym('_ack'), ack);

      var futs = [
        proto.write([1]),
        proto.write([2]),
        proto.write([3])
      ];

      // Skip the first one with valid second and non-existant last one.
      port._host..add([1, 2])..add([2, 1]);

      futs = await Future.wait(futs);
      expect(futs, [false, true, false]);
    });

    test('error handling', () {
      return new FakeAsync().run((fake) {
        // NOTE: Must re-create these in the zone for futures to work.
        port = new MockSerialPort();
        proto = new ArdProto(port);
        inst = reflect(proto);
        waitQ = inst.getField(getSym('_waitQueue')).reflectee;
        ackQ = inst.getField(getSym('_ackQueue')).reflectee;
        var futs = [
          proto.write([1]),
          proto.write([2]),
          proto.write(new List<int>.filled(ArdProto.maxPacketSize - 4, 3)),
        ];
        var errorFut;
        errorFut = inst.getField(getSym('_errorHoldoff')).reflectee;
        expect(errorFut, isNull);

        port._host.add([0xFC, 0xFF]);
        fake.elapse(const Duration(milliseconds: 1));

        errorFut = inst.getField(getSym('_errorHoldoff')).reflectee;
        expect(errorFut, isNotNull);
        expect(waitQ, isNotEmpty);
        expect(ackQ, isEmpty);

        fake.elapse(const Duration(milliseconds: 98));
        port._host.add([0xFC, 0xFF]);
        expect(waitQ, isNotEmpty);

        fake.elapse(const Duration(milliseconds: 150));
        expect(waitQ, isEmpty);
        expect(ackQ.length, 1);

        port._host.add([2, 3]);
        Future.wait(futs).then((futs) {
          expect(futs, [false, false, true]);
        });
        fake.elapse(const Duration(milliseconds: 1));
      });
    });
  });

  test('KnobAction', () {
    var action = new KnobAction(10, Direction.down);
    expect(action.isButton, isTrue);
    expect(action.isRotation, isFalse);
    action = action.toString();
    expect(new RegExp(r'Knob\d+\(Direction\.down\)').hasMatch(action), isTrue);

    action = new KnobAction(10, Direction.right);
    expect(action.isButton, isFalse);
    expect(action.isRotation, isTrue);
  });
}

class MockSerialPort extends Mock implements SerialPort {
  StreamController _host = new StreamController();
  Stream<List<int>> get onRead => _host.stream;

  Future close() => new Future.value();
}
