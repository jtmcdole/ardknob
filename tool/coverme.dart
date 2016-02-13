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

/// Collect coverage for files
import 'dart:async';
import 'dart:io';

import 'package:ansicolor/ansicolor.dart';
import 'package:coverage/coverage.dart';
import 'package:path/path.dart' as p;

Directory current = Directory.current;

main(List<String> args) async {
  var path = p.join('test', 'all_tests.dart');
  var hits = await runAndCollect(path, timeout: const Duration(seconds: 10));
  var hitMap = createHitmap(hits['coverage']);

  //  print(hits);
  var root = p.absolute(p.normalize('../'));
  var resolver = new Resolver(packageRoot: root);
  var loader = new Loader();
  String output = await new AnsiPrintFormatter(resolver, loader,
      summary: args.contains('-s')).format(hitMap, reportOn: ['lib']);
  print(output);
}

/// Converts the given hitmap to a pretty-print format and appends the result
/// to env.output.
///
/// Returns a [Future] that completes as soon as all map entries have been
/// emitted.
class AnsiPrintFormatter implements Formatter {
  final Resolver resolver;
  final Loader loader;
  final AnsiPen filePen = new AnsiPen()
    ..blue(bg: true)
    ..white(bold: true);
  final AnsiPen zero = new AnsiPen()
    ..red(bg: true, bold: true)
    ..white(bold: true);
  final AnsiPen more = new AnsiPen()..green(bold: true);
  final bool summary;

  AnsiPrintFormatter(this.resolver, this.loader, {this.summary: false});

  Future<String> format(Map hitmap,
      {List<String> reportOn, bool pathFilter(String path)}) async {
    var absPaths =
        reportOn.map((path) => new File(path).absolute.path).toList();
    pathFilter = (path) => absPaths.any((i) => path.startsWith(i));

    var buf = new StringBuffer();
    for (var key in hitmap.keys) {
      var v = hitmap[key];
      var source = resolver.resolve(key);
      if (source == null) {
        continue;
      }

      if (!pathFilter(source)) {
        continue;
      }

      var lines = await loader.load(source);
      if (lines == null) {
        continue;
      }
      int covered = 0;
      int uncovered = 0;

      var outLines = [];
      for (var line = 1; line <= lines.length; line++) {
        var prefix = _prefix;
        var count = v[line];
        if (count is num) {
          prefix = count.toString().padLeft(_prefix.length);
          count == 0 ? uncovered++ : covered++;
          prefix = count == 0 ? zero(prefix) : more(prefix);
        }
        outLines.add('$prefix|${lines[line-1]}');
      }
      buf.write(filePen(source.replaceFirst(current.path, '')));
      num coverage = (covered * 100) / (covered + uncovered);
      var pen = coverage < 80 ? zero : more;
      buf.write(pen(' coverage: ${coverage.toStringAsFixed(2)}%'));
      buf.write(' ');
      buf.writeln(stars(coverage));
      if (!summary) outLines.forEach(buf.writeln);
    }

    return buf.toString();
  }

  final AnsiPen gold = new AnsiPen()..xterm(214);
  final AnsiPen goldBold = new AnsiPen()..xterm(220);

  String stars(num score) {
    if (score < 30) return gold("☆☆☆☆☆");
    if (score < 50) return gold("★☆☆☆☆");
    if (score < 60) return gold("★★☆☆☆");
    if (score < 75) return gold("★★★☆☆");
    if (score < 90) return gold("★★★★☆");
    if (score > 98) return goldBold("★★★★★");
    return gold("★★★★★");
  }

  static const _prefix = '       ';
}
