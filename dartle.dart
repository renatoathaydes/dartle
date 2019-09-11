import 'dart:io';

import 'package:dartle/dartle.dart';
import 'package:path/path.dart' show extension;

final libDir =
    FileCollection.dir('lib', fileFilter: (f) => extension(f.path) == '.dart');

void main(List<String> args) => run(args, tasks: [
      Task(test),
      Task(checkImports, description: 'Checks dart file imports are allowed'),
    ]);

test() async {
  await exec(Process.start('pub', ['run', 'test', '-p', 'vm']));
}

checkImports() async {
  await for (final file in libDir.files) {
    final illegalImports = (await file.readAsLines()).where(
        (line) => line.contains(RegExp("^import\\s+['\"]package:dartle")));
    if (illegalImports.isNotEmpty) {
      throw DartleException(
          message: 'File ${file.path} contains '
              'an import to the dartle package: ${illegalImports}');
    }
  }
}
