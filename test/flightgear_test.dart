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

import 'package:ardknob/flightgear.dart';

import 'package:test/test.dart';

main() {
  group('Properties', () {
    group('constructor', () {
      test('throws on invalid data', () {
        expectBoom(meth, reason) {
          try {
            meth();
            fail(reason);
          } catch (e) {}
        }
        expectBoom(() => new Properties(null), 'null xml should blow up');
        expectBoom(() => new Properties(''), 'empty string should blow up');
        expectBoom(() => new Properties('this is junk'),
            'empty string should blow up');
        expectBoom(() => new Properties('''
              <foo>
                <bar>baz</bar>
              </foo>'''), 'missing elements');
        expectBoom(() => new Properties('''
              <PropertyList>
                <generic>
                  <output>
                    <chunk>
                      <type>string</type>
                    </chunk>
                  </output>
                </generic>
              </PropertyList>'''), 'invalid type');
      });
      test('works with empty properties', () {
        var prop = new Properties('''
            <PropertyList>
              <generic>
              </generic>
            </PropertyList>''');
        expect(prop, isNotNull);
        expect(prop.properties, isEmpty);
      });
      test('works with output / input properties', () async {
        var prop = new Properties('''
<PropertyList>
  <generic>
    <output>
      <line_separator>newline</line_separator>
      <var_separator>;</var_separator>
      <chunk>
        <name>Foo</name>
        <node>foo</node>
        <type>bool</type>
      </chunk>
      <chunk>
        <name>Bar</name>
        <node>bar</node>
        <type>int</type>
      </chunk>
    </output>
    <input>
      <line_separator>newline</line_separator>
      <var_separator>/</var_separator>
      <chunk>
        <name>Zoo</name>
        <node>zoo</node>
      </chunk>
      <chunk>
        <name>Foo</name>
        <node>foo</node>
        <type>bool</type>
      </chunk>
    </input>
  </generic>
</PropertyList>''');
        expect(prop, isNotNull);
        expect(prop.properties.length, 3);
        expect(prop.outputs.length, 2);
        expect(prop.inputs.length, 2);

        expect(prop.outputs.keys, ['foo', 'bar']);
        expect(prop.inputs.keys, ['zoo', 'foo']);
        expect(prop.properties.keys, ['foo', 'bar', 'zoo']);
        expect(prop.inputs['foo'], same(prop.outputs['foo']));
        expect(prop['foo'].writeable, isTrue);
        expect(prop['bar'].writeable, isFalse);
      });
    });
    test('parse()', () async {
      var prop = new Properties('''
<PropertyList>
  <generic>
    <output>
      <line_separator>newline</line_separator>
      <var_separator>;</var_separator>
      <chunk>
        <name>Foo</name>
        <node>foo</node>
        <type>bool</type>
      </chunk>
      <chunk>
        <name>Bar</name>
        <node>bar</node>
      </chunk>
      <chunk>
        <name>Baz</name>
        <node>baz</node>
        <type>int</type>
      </chunk>
      <chunk>
        <name>Qux</name>
        <node>qux</node>
        <type>float</type>
      </chunk>
    </output>
    <input>
      <line_separator>newline</line_separator>
      <var_separator>/</var_separator>
      <chunk>
        <name>Foo</name>
        <node>foo</node>
        <type>bool</type>
      </chunk>
      <chunk>
        <name>Zoo</name>
        <node>zoo</node>
      </chunk>
    </input>
  </generic>
</PropertyList>''');
      int count = 0;
      prop.outputs['foo'].stream.listen((val) {
        expect(val, same(prop.outputs['foo']));
        count++;
      });
      prop.parse(UTF8.encode('1;2;1234;123.1234'));
      expect(prop['foo'].value, isTrue);
      expect(prop['bar'].value, 2);
      expect(prop['baz'].value, 1234);
      expect(prop['qux'].value, 123.1234);

      await new Future.value();
      expect(count, 1, reason: 'async stream update for foo');

      prop.parse(UTF8.encode('1;testing;1234;123.1234'));
      await new Future.value();
      expect(count, 1, reason: 'async stream update only on change');

      prop.parse(UTF8.encode('t;codefu;asdf;asdf'));
      expect(prop['foo'].value, isFalse);
      expect(prop['bar'].value, 0);
      expect(prop['baz'].value, 0);
      expect(prop['qux'].value, 0.0);

      await new Future.value();
      expect(count, 2, reason: 'async stream update even with error');

      // Nothing changes if we get bad data
      prop.parse(UTF8.encode(';;'));
      await new Future.value();

      expect(count, 2, reason: 'async stream update even with error');
      expect(prop['foo'].value, isFalse);
      expect(prop['bar'].value, 0);
      expect(prop['baz'].value, 0);
      expect(prop['qux'].value, 0.0);
    });
  });
  group('Property', () {
    test('throws when non-writable', () async {
      var prop = new Properties('''
<PropertyList>
  <generic>
    <output>
      <var_separator>;</var_separator>
      <chunk>
        <name>Foo</name>
        <node>foo</node>
        <type>bool</type>
      </chunk>
    </output>
  </generic>
</PropertyList>''');

      try {
        prop['foo'].value = 'blah';
        fail('read only values throw on write');
      } on StateError catch (e) {}
    });
    test('accepts only proper values', () async {
      var prop = new Properties('''
<PropertyList>
  <generic>
    <input>
      <var_separator>;</var_separator>
      <chunk>
        <name>Foo</name>
        <node>foo</node>
        <type>bool</type>
      </chunk>
      <chunk>
        <name>Bar</name>
        <node>bar</node>
      </chunk>
      <chunk>
        <name>Baz</name>
        <node>baz</node>
        <type>float</type>
      </chunk>
    </input>
  </generic>
</PropertyList>''');

      try {
        prop['foo'].value = true;
        expect(prop['foo'].value, isTrue);
        prop['foo'].value = 'blah';
        fail('bool expects a boolean');
      } on StateError catch (e) {}
      try {
        prop['bar'].value = 42;
        expect(prop['bar'].value, 42);
        prop['bar'].value = 1.1;
        fail('int expects an integer');
      } on StateError catch (e) {}
      try {
        prop['baz'].value = 32.0;
        expect(prop['baz'].value, 32.0);
        prop['baz'].value = true;
        fail('float expects a num');
      } on StateError catch (e) {}
      print(prop['baz']);
    });
  });
}
