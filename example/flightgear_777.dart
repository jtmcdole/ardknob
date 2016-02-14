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

import 'dart:convert';
import 'dart:io';

import 'package:ardknob/ardproto.dart';
import 'package:ardknob/flightgear.dart';

import 'package:logging/logging.dart';
import 'package:serial_port/serial_port.dart';

DateTime _start = new DateTime.now();

Logger log = new Logger('main');

main(List<String> args) async {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((LogRecord rec) {
    print('${new DateTime.now().difference(_start)}: ${rec.level.name}: '
        '${rec.message}');
  });

  log.info("start");
  var port = args.isEmpty ? "COM3" : args.first;
  port = new SerialPort(port, baudrate: 115200);

  try {
    await port.open();
  } catch (e) {
    print("Error($e) listening to $port: ${e.stackTrace}");
    exit(-1);
  }
  log.info("$port");

  var proto = new ArdProto(port);
  log.info("$proto");

  var xml = await new File('example/ardknob_777.xml').readAsString();
  var props = new PropertyTree(xml);
  var bank = props['instrumentation/afds/inputs/bank-limit-switch'];
  var atl = props['instrumentation/afds/inputs/at-armed'];
  var atr = props['instrumentation/afds/inputs/at-armed[1]'];
  proto.onAction.listen((KnobAction action) {
    log.info(action);
    if (action.id == 0) {
      atl.value = action.direction == Direction.left ? 0 : 1;
    }
    if (action.id == 1) {
      atr.value = action.direction == Direction.left ? 0 : 1;
    }
    if (action.id == 2) {
      var val = bank.value;
      val += (action.direction == Direction.left) ? -1 : 1;
      bank.value = val;
    }
  });

  var send = await RawDatagramSocket.bind(InternetAddress.ANY_IP_V4, 1236);
  props.onUpdate.listen((update) {
    log.info('sending: $update to 1235');
    send.send(UTF8.encode(update), InternetAddress.LOOPBACK_IP_V4, 1235);
  });

  var sock = await RawDatagramSocket.bind(InternetAddress.ANY_IP_V4, 1234);
  await for (var event in sock) {
    //print(event);
    if (event == RawSocketEvent.READ) {
      Datagram dg = sock.receive();
      props.parse(dg.data);
    }
  }
}
