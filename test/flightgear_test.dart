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
        <type>string</type>
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
        expect(prop, isNotNull);
        expect(prop.properties.length, 5);
        expect(prop.outputs.length, 4);
        expect(prop.inputs.length, 2);

        expect(prop.outputs.keys, ['foo', 'bar', 'baz', 'qux']);
        expect(prop.inputs.keys, ['foo', 'zoo']);
        expect(prop.inputs['foo'], same(prop.outputs['foo']));
        expect(prop.inputs['foo'].writeable, isTrue);
        expect(prop.outputs['bar'].writeable, isFalse);

        int count = 0;
        prop.outputs['foo'].stream.listen((val) {
          expect(val, same(prop.outputs['foo']));
          count++;
        });
        prop.parse(UTF8.encode('1;testing;1234;123.1234'));
        expect(prop.outputs['foo'].value, isTrue);
        expect(prop.outputs['bar'].value, 'testing');
        expect(prop.outputs['baz'].value, 1234);
        expect(prop.outputs['qux'].value, 123.1234);

        await new Future.value();
        expect(count, 1, reason: 'async stream update for foo');

        prop.parse(UTF8.encode('1;testing;1234;123.1234'));
        await new Future.value();
        expect(count, 1, reason: 'async stream update only on change');

        prop.parse(UTF8.encode('t;codefu;asdf;asdf'));
        expect(prop.outputs['foo'].value, isFalse);
        expect(prop.outputs['bar'].value, 'codefu');
        expect(prop.outputs['baz'].value, 0);
        expect(prop.outputs['qux'].value, 0.0);

        await new Future.value();
        expect(count, 2, reason: 'async stream update even with error');

        // todo: write testing
      });
    });
  });
}
