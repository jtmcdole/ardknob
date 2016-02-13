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

/// **ArdProto**
///
/// Implementation a very simple protocol with small 64 byte framed commands and
/// asynchronous event posting. The basic packet layout includes:
///
/// * 1-byte `size` field, includes entire packets. Max 64 bytes.
/// * 1-byte `user ack` field, to be returned with each successful command.
/// * 1-byte `command` field.
/// * X-5 bytes of repeated `data`, max 59 bytes
/// * 2-byte Fletcher-16 checksum fields that should equal to zero on recieving side.
///
/// ```
///       0 1 2 3 4 5 6 7 0 1 2 3 4 5 6 7
///      ┌─┼─┼─┼─┼─┼─┼─┼─┼─┼─┼─┼─┼─┼─┼─┼─┐
///      │     size      │    user ack   │
///      ├─┼─┼─┼─┼─┼─┼─┼─┼─┼─┼─┼─┼─┼─┼─┼─┤
///      │    command    │    data0      │
///      ├─┼─┼─┼─┼─┼─┼─┼─┼─┼─┼─┼─┼─┼─┼─┼─┤
///      │                               │
///      │       ... data(size - 5)      │
///      │                               │
///      ├─┼─┼─┼─┼─┼─┼─┼─┼─┼─┼─┼─┼─┼─┼─┼─┤
///      │  flch16-sum2  │  flch16-sum1  │
///      └─┼─┼─┼─┼─┼─┼─┼─┼─┼─┼─┼─┼─┼─┼─┼─┘
///       0 1 2 3 4 5 6 7 0 1 2 3 4 5 6 7
/// ```
library ardproto;

import 'dart:async';

import 'package:logging/logging.dart';
import 'package:serial_port/serial_port.dart';

/// Arduino serial protocol handler.
class ArdProto {
  /// Maximum size of any one data packet, including any overhead.
  static const int maxPacketSize = 64;

  /// Overhead used for size, command, ackknowldgement, and fletch16 bytes.
  static const int packetOverhead = 5;

  /// Maximum size of optional data passed to [write].
  static const int maxDataLength = maxPacketSize - packetOverhead;

  /// Communications port with the arduino.
  final SerialPort port;

  final Logger log = new Logger('ArdProto');

  /// Monotonically increasing counter of which the lower 8 bits is sent
  /// to the arduino to handle ACK'ing.
  int _ack = 0;

  int _bytesOut = 0;

  /// Number of non-acknowldged, outstanding bytes.
  ///
  /// This gates the number of packets that can be concurrently sent without
  /// delay. Any packet going above this is queued, in order.
  int get bytesOut => _bytesOut;

  /// Commands waiting to be acknowldged.
  List<_Work> _ackQueue = <_Work>[];

  /// Commands waiting to be sent.
  List<_Work> _waitQueue = <_Work>[];

  StreamController<KnobAction> _knobAction = new StreamController<KnobAction>();

  /// Stream of actions reported by the arduino.
  Stream<KnobAction> get onAction => _knobAction.stream;

  StreamSubscription<List<int>> _sub;

  Stopwatch _watch;

  Future _errorHoldoff;

  ArdProto(this.port) : _watch = new Stopwatch()..start() {
    _startReading();
  }

  /// Writes a command and optional data to the [port].
  ///
  /// Completes the returned [Future] with success of this command.
  Future<bool> write(int command, [List<int> data = const <int>[]]) {
    if (data.length > maxDataLength)
      return new Future.error(new ArgumentError('Oversized $command write: '
          '${data.length + packetOverhead} > $maxPacketSize'));
    data = [data.length + 5, (_ack++ & 0xFF), command]..addAll(data);
    int sum = fletcher16(data, data.length);
    int f0 = sum & 0xFF;
    int f1 = (sum >> 8) & 0xFF;

    int c0 = 255 - ((f0 + f1) % 0xFF);
    int c1 = 255 - ((f0 + c0) % 0xFF);
    data..add(c0)..add(c1);

    var work = new _Work(data, new Completer())..sent = _watch.elapsed;
    if (_errorHoldoff != null || // don't break the rules.
        _waitQueue.isNotEmpty || // don't skip in line.
        data.length + _bytesOut > maxPacketSize) {
      _waitQueue.add(work);
    } else {
      _sendWork(work);
    }
    return work.completer.future;
  }

  /// Closes the protocol.
  ///
  /// This will clear all remaining work and shutdown then [onAction] stream.
  ///
  /// Returns a future which completes when all work is done.
  Future close() async {
    log.info('closing');
    for (var work in _ackQueue..addAll(_waitQueue)) {
      log.info('  outstanding work: $work');
      work.completer.complete(false);
    }
    log.info('clearing queues');
    _ackQueue.clear();
    _waitQueue.clear();
    _bytesOut = 0;
    _errorHoldoff = null;
    log.info('closing knob controller');
    _knobAction.close();
    log.info('canceling serial');
    await _sub.cancel();
  }

  /// Sends one chunk of work and accounts for it.
  _sendWork(_Work work) {
    _bytesOut += work.size;
    _ackQueue.add(work);
    log.finest(() {
      var dump =
          work.bytes.map((e) => '${e < 0x10 ? 0 : ''}${e.toRadixString(16)}');
      return 'data: ${dump.join(' ')}';
    });
    port.write(work.bytes);
  }

  /// Sends as much work from the [_waitQueue] as can be handled.
  _sendQueuedWork() {
    // send more work if we can!
    while (_waitQueue.isNotEmpty) {
      if (_waitQueue.first.size + _bytesOut <= maxPacketSize) {
        var work = _waitQueue.removeAt(0);
        _sendWork(work);
        continue;
      }
      break;
    }
  }

  /// Starts consuming data from the [port] for processing.
  _startReading() {
    var input = <int>[];
    _sub = port.onRead.listen((bytes) {
      input.addAll(bytes);
      var now = _watch.elapsed;
      while (input.length > 1) {
        int ack = input.removeAt(0);
        int cmd = input.removeAt(0);

        if (cmd == 0xFF) {
          log.warning('Error received: ${cmd.toRadixString(16)} '
              '${ack.toRadixString(16)}');
          var fut;
          fut = new Future.delayed(const Duration(milliseconds: 100), () {
            log.warning('error handler fired');
            // There was a later error message that pushed us back.
            if (fut != _errorHoldoff) return;
            _errorHoldoff = null;
            log.warning('holdoff done');
            _sendQueuedWork();
          });
          _errorHoldoff = fut;

          // kill outstanding acks.
          for (var work in _ackQueue) {
            log.warning('dead command: $work'
                'duration: ${now - work.sent}');
            work.completer.complete(false);
            _bytesOut -= work.size;
          }
          _ackQueue.clear();
          continue;
        }

        // Knob actions - Done before ACK check due to the fact that the ack is
        // invalid - but no other command uses 0x13.
        if (cmd == 0x13) {
          _knobAction.add(
              new KnobAction((ack >> 3) & 0x1F, Direction.values[ack & 0x3]));
          continue;
        }

        // Acknowldgement Check - first any unacked commands...
        while (_ackQueue.isNotEmpty &&
            ((_ackQueue.first.ack & 0xFF) != ack ||
                _ackQueue.first.command != cmd)) {
          var work = _ackQueue.removeAt(0);
          log.warning('un-acked command: $work '
              'duration: ${now - work.sent}');
          work.completer.complete(false);
          _bytesOut -= work.size;
        }

        // Sanity check, we should be getting ack's that we sent!
        if (_ackQueue.isEmpty) {
          log.warning('unknown ack: $ack cmd: $cmd');
          continue;
        }

        // ipsofacto this is the work.
        var work = _ackQueue.removeAt(0);
        _bytesOut -= work.size;
        log.info('completed command: $work '
            'duration: ${now - work.sent}');
        work.completer.complete(true);

        // send more work if we can!
        _sendQueuedWork();
      }
    });
  }

  /// Calculates the Fletcher 16bit checksum over the first [length] bytes
  /// of [data].
  static int fletcher16(List<int> data, int length) {
    int sum1 = 0xB5, sum2 = 0xC3;
    for (int i = 0; i < length; i++) {
      sum1 = (sum1 + data[i]) % 255;
      sum2 = (sum2 + sum1) % 255;
    }
    return (sum2 << 8) | sum1;
  }
}

/// Direction of [Knob] turn or [Button] press.
enum Direction { left, right, down, up }

/// Actions returned from the arduino board.
class KnobAction {
  final int id;
  final Direction direction;

  KnobAction(this.id, this.direction);

  String toString() => 'Knob$id($direction)';
}

/// Records commands either written and waiting for acknowldgement or those
/// queued for sending.
class _Work {
  final List<int> bytes;
  final Completer completer;
  Duration sent;

  int get size => bytes[0];
  int get ack => bytes[1];
  int get command => bytes[2];

  _Work(this.bytes, this.completer);

  String toString() => 'work{cmd:$command ack:$ack size:$size}';
}
