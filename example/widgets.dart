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
import 'dart:convert';
import 'dart:io';

import 'package:ardknob/ardproto.dart';
import 'package:ardknob/display.dart';
import 'package:ardknob/flightgear.dart';
import 'package:ardknob/pages.dart';

import 'package:logging/logging.dart';
import 'package:serial_port/serial_port.dart';

Stopwatch _start = new Stopwatch()..start();

Logger log = new Logger('main');

main(List<String> args) async {
  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen((LogRecord rec) {
    print('${_start.elapsed}: ${rec.level.name}: [${rec.loggerName}] '
        '${rec.message}');
  });

  var port = args.isEmpty ? "COM3" : args.first;
  port = new SerialPort(port, baudrate: 115200);

  try {
    await port.open();
  } catch (e) {
    print("Error($e) listening to $port: ${e.stackTrace}");
    exit(-1);
  }

  var xml = await new File('example/ardknob_777.xml').readAsString();
  var props = new PropertyTree(xml);

  var proto = new ArdProto(port);
  var display = new Display(proto);

  await new Future.delayed(const Duration(milliseconds: 150), () {});

  display.clear();
  display.textSize(2);
  new Book('777', proto, pageKnobId: 2, display: display)
    ..add(new NavRadioPage('NAV1', props['nav1-actual'], props['nav1-standby'],
        props['nav1-radial']))
    ..add(new NavRadioPage('NAV2', props['nav2-actual'], props['nav2-standby'],
        props['nav2-radial']))
    ..add(new SpeedPage(props['target-speed'], props['auto-throttle index'],
        props['auto-throttle-left'], props['auto-throttle-right']))
    ..add(new AltitudePage(props['altitude-ft']));

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

abstract class WidgetPage extends Page {
  List get widgets;

  WidgetPage(String name) : super(name);

  bool draw() {
    var dirty = false;
    for (var widget in widgets) {
      dirty = widget.draw(display) || dirty;
    }
    if (dirty) display.display();
    return dirty;
  }

  onEvent(PageEvent event, var data) {
    if (event == PageEvent.onScreen) {
      display.clear();
      for (var widget in widgets) widget.dirty = true;
      draw();
    }
  }
}

class NavRadioPage extends WidgetPage {
  final Logger log;
  final List widgets;
  final List props;
  int _selected = 1;

  NavRadioPage(String name, Property actual, Property standby, Property radial)
      : widgets = [],
        props = [],
        log = new Logger('$name-radio'),
        super('$name-radios') {
    var nav1 =
        new RadioWidget(0, 0, name: name, frequency: actual.value ?? 0.0);
    var nav1sb = new RadioWidget(0, 16,
        name: '$name-SB', frequency: standby.value ?? 0.0)..isSelected = true;
    var nav1rad =
        new RadialWidget(0, 32, name: 'Radial', radial: radial.value ?? 0);

    var workfn;
    doWork() async {
      if (workfn != null) return;
      workfn = new Future.delayed(const Duration(milliseconds: 100), () {});
      await workfn;
      workfn = null;
      draw();
    }

    actual.stream.listen((prop) {
      log.info('update to ${prop.value}');
      nav1.value = prop.value;
      doWork();
    });
    standby.stream.listen((prop) {
      log.info('update to ${prop.value}');
      nav1sb.value = prop.value;
      doWork();
    });
    radial.stream.listen((prop) {
      log.info('update to ${prop.value}');
      nav1rad.value = prop.value;
      doWork();
    });

    widgets.addAll([nav1, nav1sb, nav1rad]);
    props.addAll([actual, standby, radial]);
  }

  onKnob(KnobAction knob) {
    var rad = widgets[_selected];
    var prop = props[_selected];

    log.info(knob);
    if (knob.id == 0) {
      if (knob.direction == Direction.left) {
        prop.value = rad.adjust(-1);
      } else if (knob.direction == Direction.right) {
        prop.value = rad.adjust(1);
      } else if (knob.direction == Direction.down) {
        _selected = _selected == 1 ? 2 : 1;
        rad.isSelected = false;
        rad = widgets[_selected]..isSelected = true;
      }
    }
    if (knob.id == 1) {
      if (knob.direction == Direction.left) {
        rad.shift(1);
      } else if (knob.direction == Direction.right) {
        rad.shift(-1);
      } else if (knob.direction == Direction.down && _selected == 1) {
        var swap = widgets[0].value;
        props[0].value = widgets[0].value = widgets[1].value;
        props[1].value = widgets[1].value = swap;
      }
    }
    draw();
  }
}

class AltitudePage extends WidgetPage {
  final List widgets;
  final List props;
  final AltitudeWidget altitude;

  int _selected = 0;
  int _button = 0;

  List<String> switchNames = <String>["FOO", "BAR", "BAZ", "CODEFU"];

  AltitudePage(Property altitude)
      : widgets = [],
        props = [],
        this.altitude = new AltitudeWidget(0, 0, name: 'alt'),
        super('altitude') {
    widgets
      ..add(this.altitude)
      ..add(new SwitchWidget(0, 16, name: switchNames.first));
    widgets[_selected].isSelected = true;
    props.add(altitude);

    var workfn;
    doWork() async {
      if (workfn != null) return;
      workfn = new Future.delayed(const Duration(milliseconds: 100), () {});
      await workfn;
      workfn = null;
      draw();
    }

    altitude.stream.listen((prop) {
      log.info('update to ${prop.value}');
      this.altitude.value = prop.value;
      doWork();
    });
  }

  onKnob(KnobAction knob) {
    var sel = widgets[_selected];
    if (knob.id == 0) {
      if (sel is AdjustableWidget) {
        var prop = props[_selected];
        if (knob.direction == Direction.left) {
          prop.value = altitude.adjust(-1);
        } else if (knob.direction == Direction.right) {
          prop.value = altitude.adjust(1);
        } else if (knob.direction == Direction.down) {
          altitude.shift(1);
        }
      } else if (sel is SwitchWidget) {
        if (knob.direction == Direction.left) {
          sel.name = switchNames[--_button % switchNames.length];
        } else if (knob.direction == Direction.right) {
          sel.name = switchNames[++_button % switchNames.length];
        } else if (knob.direction == Direction.down) {
          sel.flip();
        }
      }
    }
    if (knob.id == 1) {
      if (knob.direction == Direction.left ||
          knob.direction == Direction.right) {
        sel.isSelected = false;
        _selected = _selected == 0 ? 1 : 0;
        widgets[_selected].isSelected = true;
      }
    }
    draw();
  }
}

class SpeedPage extends WidgetPage {
  final List widgets;
  final List props;
  final SpeedWidget speed;
  final SwitchWidget atArmed;
  final SwitchWidget atLeft;
  final SwitchWidget atRight;

  int _selected = 0;
  int _button = 0;

  SpeedPage(Property speed, Property atArmed, Property atLeft, Property atRight)
      : widgets = [],
        props = [],
        this.speed = new SpeedWidget(48, 0, name: 'speed'),
        this.atArmed = new SwitchWidget(15, 16, name: 'AT-ARM', states: [0, 5]),
        this.atLeft = new SwitchWidget(0, 38, name: 'ATL'),
        this.atRight = new SwitchWidget(64, 38, name: 'ATR'),
        super('speed') {
    widgets.addAll([this.speed, this.atArmed, this.atLeft, this.atRight]);
    widgets[_selected].isSelected = true;
    props.addAll([speed, atArmed, atLeft, atRight]);

    var workfn;
    doWork() async {
      if (workfn != null) return;
      workfn = new Future.delayed(const Duration(milliseconds: 100), () {});
      await workfn;
      workfn = null;
      draw();
    }

    streamIt(prop, value) {
      prop.stream.listen((prop) {
        log.info('update to ${prop.value}');
        value.value = prop.value;
        doWork();
      });
    }
    streamIt(speed, this.speed);
    streamIt(atArmed, this.atArmed);
    streamIt(atRight, this.atRight);
    streamIt(atLeft, this.atLeft);
  }

  onKnob(KnobAction knob) {
    var sel = widgets[_selected];
    var prop = props[_selected];

    if (knob.id == 0) {
      if (knob.isRotation && sel == speed) {
        prop.value = sel.adjust(knob.direction == Direction.left ? -1 : 1);
      }
    } else if (knob.id == 1) {
      if (knob.isRotation) {
        sel.isSelected = false;
        _selected =
            (knob.direction == Direction.left ? --_selected : ++_selected) %
                widgets.length;
        sel = widgets[_selected]..isSelected = true;
      } else if (knob.direction == Direction.down) {
        if (_selected == 0) {
          // Let down on speed also flip AT-ARMED
          prop = props[1];
          sel = widgets[1];
        }
        prop.value = (sel..flip()).state;
      }
    }
    draw();
  }
}

abstract class Widget {
  int x;
  int y;

  Widget();
  Widget.at(this.x, this.y);

  bool dirty = true;
  bool draw(Display display) => false;
}

abstract class SelectableWidget extends Widget {
  bool get isSelected => _selected;
  void set isSelected(bool selected) {
    dirty = true;
    _selected = selected;
  }

  bool _selected = false;
}

class TextLabel extends Widget {
  String text;
  TextLabel(int x, int y, this.text) : super.at(x, y);

  @override
  bool draw(display) {
    if (!dirty) return false;

    display.textColor(1, 0);
    display.cursor(x, y);
    display.text(text);
    return true;
  }
}

/// Control the render and editing of a specific radio frequency.
class RadioWidget extends AdjustableWidget<RadioFrequency> {
  RadioWidget(int x, int y, {name: '', num frequency: 111.10})
      : super(x, y, name: name) {
    _value = new RadioFrequency()..value = frequency;
  }
}

/// Control the render and editing of a specific radial value (1 to 360).
class RadialWidget extends AdjustableWidget<Radial> {
  RadialWidget(int x, int y, {name: '', num radial: 80})
      : super(x, y, name: name) {
    _value = new Radial()..value = radial;
  }
}

class AltitudeWidget extends AdjustableWidget<Altitude> {
  AltitudeWidget(int x, int y, {name: '', num altitude: 10000})
      : super(x, y, name: name) {
    _value = new Altitude()..value = altitude;
  }
}

class SpeedWidget extends AdjustableWidget<PaddedInt> {
  SpeedWidget(int x, int y, {name: '', int speed: 200})
      : super(x, y, name: name) {
    _value = new PaddedInt()..value = speed;
  }
}

abstract class AdjustableWidget<T extends AdjustableValue>
    extends SelectableWidget {
  String name;

  T _value;

  void set value(value) {
    dirty = true;
    _value.value = value;
  }

  int get value => _value.value;

  AdjustableWidget(int x, int y, {this.name: ''}) {
    this.x = x;
    this.y = y;
  }

  adjust(int amount) {
    dirty = true;
    return _value.adjust(amount);
  }

  shift(int amount) {
    dirty = true;
    _value.shift(amount);
  }

  @override
  bool draw(display) {
    if (!dirty) return false;
    var string = _value.toString();
    log.info("$name: redraw: '$string'");
    display.textColor(1, 0);
    display.cursor(x, y);
    display.text(string);
    if (name.isNotEmpty) {
      display.textSize(1);
      display.text(' ');
      display.text(name);
      display.textSize(2);
    }
    if (isSelected) {
      var offset = _value.offset;
      display.textColor(1);
      display.cursor(x + (offset * 12), y + 2);
      display.text('_');
    }
    dirty = false;
    return true;
  }
}

abstract class AdjustableValue<T extends num> implements Function {
  final List<T> increments;
  final List<num> offsets;
  final num max;
  final num min;

  T value;

  T call([T newValue]) {
    if (newValue != null) {
      value = newValue;
    }
    return value;
  }

  int get digitIndex => _digitIndex;
  int _digitIndex = 0;

  int get offset => offsets[digitIndex];

  AdjustableValue(
      {this.increments: const [1],
      this.offsets: const [0],
      this.max: double.INFINITY,
      this.min: double.NEGATIVE_INFINITY}) {
    assert(increments.length == offsets.length);
  }

  T adjust(T amount) {
    amount = value + (increments[digitIndex] * amount);
    if (amount >= min && amount <= max) value = amount;
    return value;
  }

  /// Shifts the [digitIndex] by [amount], wrapping around in either direction.
  shift(int amount) {
    _digitIndex = (digitIndex + amount) % increments.length;
  }
}

class RadioFrequency extends AdjustableValue<num> {
  num get frequency => value;
  set frequency(num value) => this.value = value;

  @override
  num adjust(num amount) {
    amount = (value * 100).round() + (increments[digitIndex] * amount);
    amount /= 100;
    if (amount >= min && amount <= max) value = amount;
    value = (value * 1000).toInt() / 1000;
    return value;
  }

  RadioFrequency()
      : super(
            max: 999.99,
            min: 0,
            increments: const [1, 10, 100, 1000, 10000],
            offsets: const [5, 4, /* 3 = . */ 2, 1, 0]);

  String toString() => value.toStringAsFixed(2).padLeft(6);
}

class Radial extends AdjustableValue<int> {
  int get radial => value;

  Radial() : super(increments: const [1, 10], offsets: const [2, 1]);

  /// Changes the radial by the [digitIndex] magnitude, [amount] times with
  /// wrapping around after 360.
  adjust(num amount) {
    super.adjust(amount);
    // Keep in the range: 1..360
    if (value < 1 || value > 360) value = ((value - 1) % 360) + 1;
    return value;
  }

  String toString() => '$radial'.padLeft(3);
}

class Altitude extends AdjustableValue<int> {
  int get altitude => value; // we want 1 to 360

  Altitude()
      : super(
            increments: const [100, 1000],
            offsets: const [2, 1],
            min: 0,
            max: 60000);

  String toString() => '$value'.padLeft(5);
}

/// Generic int value
class PaddedInt extends AdjustableValue<int> {
  final int pad;

  PaddedInt({int pad: 3})
      : this.pad = pad,
        super(increments: [1], offsets: [pad - 1], min: 0, max: 60000);

  String toString() => '$value'.padLeft(pad);
}

class Switch {
  final Logger log = new Logger('Switch');

  bool get value => _value;
  bool _value;

  bool flip([bool value]) {
    _value = (value ?? !_value);
    return _value;
  }
}

class SwitchWidget extends SelectableWidget with Switch {
  int get width => _width;
  int _width;
  int _lastDrawWidth;

  int get height => _height;
  int _height;

  String get name => _name;
  set name(String name) {
    dirty = true;
    this._name = name;
    _width = (name.length + 2) * 12 + 2;
  }

  String _name;

  /// Two position list containing user defined values that are returned via
  /// [state] depending on the [value].
  List states;

  /// User defined state of this switch.
  get state => states[_value == false ? 0 : 1];

  set value(val) {
    dirty = true;
    _value = val == true || (val is num && val > 0);
  }

  bool flip([bool value]) {
    dirty = true;
    return super.flip(value);
  }

  SwitchWidget(int x, int y,
      {String name: '', bool value: false, this.states: const [0, 1]})
      : _height = 16 + 2 {
    _value = value;
    this.name = name;
    _lastDrawWidth = width;
    this.x = x;
    this.y = y;
  }

  @override
  bool draw(display) {
    if (!dirty) return false;
    log.info("$name: redraw : $state $isSelected");
    // clear the area of the switch
    display.rectangle(x, y, _lastDrawWidth, height, 0, fill: true, radius: 0);
    _lastDrawWidth = width;
    // render the border of the switch; it is filled if the switch is on.
    display.rectangle(x, y, width, height, 1, fill: value, radius: 3);
    display.textSize(2);
    display.textColor(value ? 0 : 1);
    display.cursor(x + 1, y + 2);
    display.text(isSelected ? '[$name]' : ' $name');
    dirty = false;
    return true;
  }
}
