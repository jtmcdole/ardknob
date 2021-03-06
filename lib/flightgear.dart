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

/// A library for parsing FlightGear generic xml protocol files and manage the
/// the properties enumerated in them.
library flightgear;

import 'dart:async';
import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:xml/xml.dart' as xml;

/// FlightGear properties tree, implemented as a map.
///
/// Make sure protocol file is in FGROOT/Protocol/ and run flightgear with:
///
///     --generic=socket,out,5,localhost,1234,udp,ardknod
///     --generic=socket,in,5,localhost,1235,udp,ardknod
///
/// NOTE: simgear SGSocket does not support bi directional udp - which makes
/// since as we'd both be listening and sending on the same socket (locally).
/// To get around this, we don't care about sockets here - callers need to
/// create the bidirectional nature and pass data in / send data out from this
/// single property set.
class PropertyTree {
  final Logger log = new Logger('PropertyTree');

  /// String separator used between properties sent from FlightGear.
  String out_separator;

  /// String separator used between properties sent from ArdKnob.
  String in_separator;

  /// String separator between lines...
  String in_line;

  /// All properties parsed from the generic protocol.
  Map<String, Property> properties;

  /// Properties meant to be sent to FlightGear
  Map<String, Property> inputs;

  /// Properties sent from FlightGear.
  Map<String, Property> outputs;

  /// A stream of updates to send back to FlightGear,
  Stream<String> get onUpdate => _updates.stream;

  final StreamController<String> _updates;

  /// Parses the [FlightGear Generic Protocol](http://wiki.flightgear.org/Generic_protocol)
  /// passed in as an xml string.
  PropertyTree(String generic)
      : _updates = new StreamController<String>.broadcast(sync: true) {
    var doc = xml.parse(generic);
    var gen =
        doc.findElements('PropertyList').first.findElements('generic').first;
    var output = gen.findElements('output');
    if (!output.isEmpty) {
      var sep = output.first.findElements('var_separator');
      out_separator = sep.isEmpty ? '' : sep.first.text;
    }
    output = output.isEmpty ? [] : output.first.children;

    parseChunks(chunks, {bool write: false}) {
      var nodes = [];
      for (var chunk in chunks) {
        if (chunk is! xml.XmlElement) continue;
        if (chunk.name.local != 'chunk') continue;

        var node, name, type;
        var attributes = new Map.fromIterable(chunk.attributes,
            key: (a) => a.name.local, value: (a) => a.value);
        for (var child in chunk.children) {
          if (child is! xml.XmlElement) continue;
          var text = child.text;
          switch (child.name.local) {
            case 'name':
              name = text;
              break;
            case 'node':
              node = text;
              break;
            case 'type':
              switch (text) {
                case 'int':
                  type = PropertyType.int;
                  break;
                case 'float':
                  type = PropertyType.float;
                  break;
                case 'bool':
                  type = PropertyType.bool;
                  break;
                default:
                  throw new UnimplementedError('$text is not implemented yet');
              }
              break;
          }
        }
        var prop = new Property(
            name, node, type ?? PropertyType.int, attributes,
            writeable: write);
        nodes.add(prop);
      }
      return nodes;
    }

    outputs = new Map<String, Property>.fromIterable(parseChunks(output),
        key: (item) => item.node);

    inputs = new Map<String, Property>();
    var input = gen.findElements('input');
    if (!input.isEmpty) {
      var sep = input.first.findElements('var_separator');
      in_separator = sep.isEmpty ? '' : sep.first.text;
      sep = input.first.findElements('line_separator');
      if (sep.isNotEmpty && sep.first.text == 'newline') {
        in_line = '\n';
      } else {
        in_line = '';
      }
    }
    input = input.isEmpty ? [] : input.first.children;
    input = parseChunks(input, write: true);

    // Find all the input elements in the output section, because we want to
    // re-use them and allow the user to read back their write.
    for (var chunk in input) {
      inputs[chunk.node] = chunk.._onEdit = _onEdit;
      if (outputs.containsKey(chunk.node)) {
        outputs[chunk.node] = chunk;
      }
    }

    properties = new Map<String, Property>.from(outputs)..addAll(inputs);

    // Add mappings for easier 'name' lookup.
    properties.addAll(new Map.fromIterable(
        properties.values.where((item) => item.name != null),
        key: (item) => item.name));
  }

  /// Guards multiple properties being edited by the same task.
  Future _writeWhen;

  /// Signals [onUpdates] when properties have been modified by the user.
  _onEdit(Property prop) {
    _writeWhen = _writeWhen ??
        new Future.microtask(() {
          // note: set to null first in case stream listeners make more
          // modifications - they need to be queued up.
          _writeWhen = null;
          _updates.add(inputMessage);
        });
  }

  /// Parse a line of data sent from FlightGear and update the [outputs]
  ///
  /// Changes to a [Property]'s state will be signaled through its broadcast
  /// [Property.stream].
  void parse(List<int> data) {
    var update = UTF8.decode(data);
    update = update.split(out_separator);
    if (update.length != outputs.values.length) {
      log.warning('update does not match expected properties. '
          'update: $update '
          'expected: ${outputs.values}');
      return;
    }
    for (var prop in outputs.values) prop._update(update.removeAt(0));
  }

  /// Generate an update message to send to FlightGear.
  String get inputMessage {
    var msg = inputs.values.map((e) => e.value).join(in_separator);
    return '$msg$in_line';
  }

  /// Looks up any [Property] by its [Property.node].
  operator [](String node) => properties[node];

  /// Looks up any [Property] by its [Property.node].
  operator []=(String node, value) => properties[node].value = value;
}

/// Data type representation of a given property in the protocol.
enum PropertyType { bool, int, float, string }

/// Reprsents on node in the [FlightGear property tree](http://wiki.flightgear.org/Property_tree).
abstract class Property {
  /// The path in the tree to a given property.
  final String node;

  /// A string only meant for human edification,
  final String name;

  /// The variable type for value in transmission.
  final PropertyType type;

  /// A map of attributes for this propery
  final Map<String, String> attributes;

  final Logger log = new Logger('Property');

  /// Value of this property, either written to by ArdKnob clients or received
  /// by FlightGear transmission.
  get value => _value;

  /// Are [value] updates from Flightgear ignored for [debounceDuration] after
  /// user edits. Defaults to true for [writeable] properties.
  bool get debounce => _debounce;
  set debounce(bool debounce) {
    if (debounce != _debounce) {
      _debounce = debounce;
      _debouncer = null;
    }
  }

  bool _debounce;

  /// The last delayed future before updates from Flightgear are allowed.
  Future _debouncer;

  /// The amount of time to ignore property updates from Flightgear after user
  /// updates to [value] and [debouce] is true.
  Duration debounceDuration = new Duration(seconds: 1);

  void set value(dynamic value) {
    if (!writeable) throw new StateError('$node is not marked as writeable');
    _value = value;
    if (_onEdit != null) _onEdit(this);
    if (debounce) {
      var me;
      me = _debouncer = new Future.delayed(debounceDuration, () {
        if (me == _debouncer) {
          log.fine('debounce done $name');
          _debouncer = null;
        }
      });
    }
  }

  /// When the user edits this value, this callback can be made.i
  /// Cheaper than a stream...
  Function _onEdit;

  dynamic _value;

  /// Was this property found in the <Input> section and thus user editable.
  final bool writeable;

  final StreamController<Property> _streamOutput;

  /// A stream of update events only when [value] changes due to transmission
  /// from FlightGear.
  Stream<Property> get stream => _streamOutput.stream;

  factory Property(String name, String node, PropertyType type,
      Map<String, String> attributes,
      {bool writeable: false}) {
    var ret;
    switch (type) {
      case PropertyType.int:
        ret = new IntProperty._(name, node, type, attributes, writeable);
        break;
      case PropertyType.float:
        ret = new NumProperty._(name, node, type, attributes, writeable);
        break;
      case PropertyType.bool:
        ret = new BoolProperty._(name, node, type, attributes, writeable);
        break;
      default:
        throw new UnimplementedError('$type not implemented');
    }
    return ret.._debounce = writeable;
  }

  Property._(this.name, this.node, this.type, this.attributes, this.writeable)
      : _streamOutput = new StreamController<Property>.broadcast();

  /// Internal update driven by FlightGear.
  void _update(value) {
    if (value != _value) {
      if (_debouncer != null) {
        log.info('$this = $value debounced');
        return;
      }
      _value = value;
      log.info('$this updated');
      _streamOutput.add(this);
    }
  }
}

class IntProperty extends Property {
  /// An optional minimum value.
  num min;

  /// An optional maximum value.
  num max;

  IntProperty._(name, node, type, att, bool writeable)
      : super._(name, node, type, att, writeable) {
    if (attributes.containsKey('min')) {
      min = int.parse(attributes['min']);
    }
    min ??= double.NEGATIVE_INFINITY;

    if (attributes.containsKey('max')) {
      max = int.parse(attributes['max']);
    }
    max ??= double.INFINITY;
  }

  void set value(value) {
    if (value is! int) throw new StateError('$node: $value is! integer');
    super.value = value.clamp(min, max);
  }

  void _update(value) {
    value = int.parse(value, onError: (s) {
      log.warning('$this: error parsing update($s)');
      return 0;
    });
    super._update(value);
  }

  String toString() => 'IntProp($name, $node, $value, $attributes)';
}

class NumProperty extends Property {
  NumProperty._(name, node, type, att, bool writeable)
      : super._(name, node, type, att, writeable);

  void set value(value) {
    if (value is! num) throw new StateError('$node: $value is! num');
    super.value = value;
  }

  void _update(value) {
    value = num.parse(value, (s) {
      log.warning('$this: error parsing update($s)');
      return 0.0;
    });
    super._update(value);
  }

  String toString() => 'NumProp($name, $node, $value, $attributes)';
}

class BoolProperty extends Property {
  BoolProperty._(name, node, type, att, bool writeable)
      : super._(name, node, type, att, writeable);

  void set value(value) {
    if (value is! bool) throw new StateError('$node: $value is! bool');
    super.value = value;
  }

  void _update(value) {
    value = value == 'true' || value == '1';
    super._update(value);
  }

  String toString() => 'BoolProp($name, $node, $value, $attributes)';
}
