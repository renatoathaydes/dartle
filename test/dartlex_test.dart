@TestOn('!browser')
import 'dart:async';
import 'dart:io';

import 'package:dartle/dartle.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'test_utils.dart';

const logDateRegex = '\\d{4}-\\d{2}-\\d{2} \\d{2}.\\d{2}.\\d{2}\\.\\d+';
const infoLogPrefixRegex = '$logDateRegex - dartle\\[main \\d+\\] - INFO -';

void main() {
  group('dartlex', () {
    test('can execute simple build', () async {
      final projectDir =
          await _createTestProjectAndCompileDartlex('compiles_itself', '''
            import 'package:dartle/dartle.dart';
      
            final allTasks = [Task(hello)];
            main(List<String> args) async => run(args, tasks: allTasks.toSet());
            Future<void> hello(_) async => print('hello');
      ''');
      final proc = Process.start(
          p.join(projectDir.absolute.path, 'dartlex'), const ['hello'],
          workingDirectory: projectDir.path, runInShell: true);

      final result = await startProcess(proc, 'dartlex');

      expect(result.exitCode, equals(0), reason: result.toString());
      expect(result.stdout, hasLength(equals(5)));
      expect(result.stdout[0],
          matches('$infoLogPrefixRegex Detected changes in dartle.dart.*'));
      expect(
          result.stdout[1],
          matches(
              '$infoLogPrefixRegex Executing 1 task out of a total of 1 task.*'));
      expect(
          result.stdout[2],
          matches(
              '$logDateRegex - dartle\\[main \\d+\\] - INFO - Running task \'hello\''));
      expect(result.stdout[3], matches('hello'));
      expect(result.stdout[4], matches('✔ Build succeeded in .*'));
      expect(result.stderr, equals([]));
    });

    test('can re-compile itself after changes', () async {
      final helloDartle = (String helloTask) => '''
      import 'package:dartle/dartle.dart';
      
      final allTasks = [Task(hello)];
      main(List<String> args) async => run(args, tasks: allTasks.toSet());
      Future<void> hello(_) async => $helloTask
      ''';

      final projectDir = await _createTestProjectAndCompileDartlex(
          'mini_project', helloDartle('print("hello");'));
      final proc = Process.start(
          p.join(projectDir.absolute.path, 'dartlex'), const ['hello'],
          workingDirectory: projectDir.path, runInShell: true);

      final result = await startProcess(proc, 'dartlex');

      expect(result.exitCode, equals(0), reason: result.toString());
      expect(result.stdout, hasLength(equals(5)));
      expect(result.stdout[3], equals('hello'));
      expect(result.stderr, equals([]));

      // some OS's like to keep file change time resolution in the seconds
      await Future.delayed(Duration(seconds: 1));

      await File(p.join(projectDir.path, 'dartle.dart')).writeAsString(
          helloDartle('print("bye");'),
          mode: FileMode.writeOnly,
          flush: true);

      final proc2 = Process.start(p.join(projectDir.absolute.path, 'dartlex'),
          const ['-l', 'info', 'hello'],
          workingDirectory: projectDir.path, runInShell: true);
      final result2 = await startProcess(proc2, 'dartlex');
      expect(result2.exitCode, equals(0), reason: result2.stdout.toString());
      expect(result2.stdout, hasLength(equals(5)));
      expect(result2.stdout[3], equals('bye'));
      expect(result2.stderr, equals([]));
    });
  });
}

Future<Directory> _createTestProjectAndCompileDartlex(
    String testProject, String dartleScript) async {
  final dir = Directory(p.join('test', 'test_builds', testProject));
  await dir.create();
  addTearDown(() => dir.deleteSync(recursive: true));
  final dartleFile = File(p.join(dir.path, 'dartle.dart'));
  await dartleFile.writeAsString(dartleScript, flush: true);
  await createDartExe(dartleFile, File(p.join(dir.path, 'dartlex')));
  return dir;
}
