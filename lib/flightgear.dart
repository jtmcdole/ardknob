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
class Properties {
  /// String separator used between properties sent from FlightGear.
  String out_separator;

  /// String separator used between properties sent from ArdKnob.
  String in_separator;

  /// All properties.
  Map<String, Property> properties;

  /// Properties meant to be sent to FlightGear
  Map<String, Property> inputs;

  /// Properties sent from FlightGear.
  Map<String, Property> outputs;

  Properties(String generic) {
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
              type = text;
              break;
          }
        }
        if (type == null) type = 'int';
        nodes.add(new Property(name, node, type));
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
    }
    input = input.isEmpty ? [] : input.first.children;
    input = parseChunks(input);

    // Find all the input elements in the output section, because we want to
    // re-use them and allow the user to read back their write.
    for (var chunk in input) {
      var out = outputs[chunk.node];
      inputs[chunk.node] = (out ?? chunk).._writeable = true;
    }

    properties = new Map<String, Property>.from(outputs)..addAll(inputs);
  }

  void parse(List<int> data) {
    var update = UTF8.decode(data);
    update = update.split(out_separator);
    if (update.length != outputs.values.length) {
      print("err... update doesn't contain all properties ($update)");
      return;
    }
    for (var prop in outputs.values) {
      var foo = update.removeAt(0);
      if (prop.type == 'int') {
        foo = int.parse(foo, onError: (s) {
          print('error parsing update($s) for ${prop.node}');
          return 0;
        });
      } else if (prop.type == 'float') {
        foo = num.parse(foo, (s) {
          print('error parsing update($s) for ${prop.node}');
          return 0.0;
        });
      } else if (prop.type == 'bool') {
        foo = foo == 'true' || foo == '1';
      }

      if (foo != prop.value) {
        prop._value = foo;
        print("${prop.node} updated: $foo");
        prop._streamctl.add(prop);
      }
    }
  }
}

class Property {
  final String node;
  final String name;
  final String type;

  dynamic get value => _value;
  void set value(dynamic value) {
    if (!writeable) throw new StateError('$node is not marked as writeable');
    if (type == 'int' && value is! int)
      throw new StateError('$node is integer');
    if (type == 'float' && value is! num) throw new StateError('$node is num');
    if (type == 'bool' && value is! bool) throw new StateError('$node is bool');
    _value = value;
  }

  dynamic _value;

  /// Can this property be written to.
  bool get writeable => _writeable;
  bool _writeable = false;

  final _streamctl;
  Stream<Property> get stream => _streamctl.stream;

  Property(this.name, this.node, this.type)
      : _streamctl = new StreamController<Property>.broadcast();

  String toString() => "Prop($name, $node, $type)";
}
