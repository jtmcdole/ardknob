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

    parseChunks(chunks) {
      var nodes = [];
      for (var chunk in chunks) {
        if (chunk is! xml.XmlElement) continue;
        if (chunk.name.local != 'chunk') continue;

        var node, name, type;
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
        nodes.add(new Property(name, node, type ?? PropertyType.int));
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
    input = parseChunks(input);

    // Find all the input elements in the output section, because we want to
    // re-use them and allow the user to read back their write.
    for (var chunk in input) {
      var out = outputs[chunk.node];
      inputs[chunk.node] = (out ?? chunk)
        .._writeable = true
        .._onEdit = _onEdit;
    }

    properties = new Map<String, Property>.from(outputs)..addAll(inputs);
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
      log.warning('update does not contain all properties ($update)');
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
enum PropertyType { bool, int, float }

/// Reprsents on node in the [FlightGear property tree](http://wiki.flightgear.org/Property_tree).
class Property {
  /// The path in the tree to a given property.
  final String node;

  /// A string only meant for human edification,
  final String name;

  /// The variable type for value in transmission.
  final PropertyType type;

  final Logger log = new Logger('Property');

  /// Value of this property, either written to by ArdKnob clients or received
  /// by FlightGear transmission.
  dynamic get value => _value;
  void set value(dynamic value) {
    if (!writeable) throw new StateError('$node is not marked as writeable');
    if (type == PropertyType.int && value is! int)
      throw new StateError('$node is integer');
    if (type == PropertyType.float && value is! num)
      throw new StateError('$node is num');
    if (type == PropertyType.bool && value is! bool)
      throw new StateError('$node is bool');
    _value = value;
    assert(_onEdit != null);
    _onEdit(this);
  }

  /// When the user edits this value, this callback can be made.i
  /// Cheaper than a stream...
  Function _onEdit;

  /// Internal update driven by FlightGear.
  void _update(value) {
    if (type == PropertyType.int) {
      value = int.parse(value, onError: (s) {
        log.warning('$this: error parsing update($s)');
        return 0;
      });
    } else if (type == PropertyType.float) {
      value = num.parse(value, (s) {
        log.warning('$this: error parsing update($s)');
        return 0.0;
      });
    } else if (type == PropertyType.bool) {
      value = value == 'true' || value == '1';
    }

    if (value != _value) {
      _value = value;
      log.info('$this updated');
      _streamOutput.add(this);
    }
  }

  dynamic _value;

  /// Is this property writeable?
  bool get writeable => _writeable;
  bool _writeable = false;

  final StreamController<Property> _streamOutput;

  /// A stream of update events only when [value] changes due to transmission
  /// from FlightGear.
  Stream<Property> get stream => _streamOutput.stream;

  Property(this.name, this.node, this.type)
      : _streamOutput = new StreamController<Property>.broadcast();

  String toString() => 'Prop($name, $node, $type, $value)';
}
