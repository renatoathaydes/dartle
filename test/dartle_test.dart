@TestOn('!browser')
import 'package:dartle/dartle.dart';
import 'package:test/test.dart';

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
}
