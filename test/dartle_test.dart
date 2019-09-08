@TestOn('!browser')
import 'package:dartle/dartle.dart';
import 'package:test/test.dart';
import 'package:test_process/test_process.dart';

helloTask() => null;

void main() {
  group('Task name', () {
    test('can be inferred from function', () {
      expect(Task(helloTask).name, equals('helloTask'));
    });
    test('can be defined explicitly', () {
      expect(Task(helloTask, name: 'foo').name, equals('foo'));
    });
    test('cannot be inferred from lambda', () {
      expect(() => Task(() {}).name, throwsArgumentError);
    });
  });
  group('Task execution', () {
    test('logs expected output', () async {
      var proc =
          await TestProcess.start('dart', ['example/dartle.dart', 'hello']);
      await expectLater(proc.stdout, emits(contains('Running task: hello')));
      await expectLater(proc.stdout, emits('Hello!'));
      await proc.shouldExit(0);

      proc = await TestProcess.start('dart', ['example/dartle.dart', 'bye']);
      await expectLater(proc.stdout, emits(contains('Running task: bye')));
      await expectLater(proc.stdout, emits('Bye!'));
      await proc.shouldExit(0);
    });
  });
}
