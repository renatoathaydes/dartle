import 'package:dartle/dartle.dart';
import 'package:test/test.dart';

helloTask() => null;

void main() {
  group('Task name', () {
    test('can be inferred from function', () {
      expect(Task(helloTask).name, equals('helloTask'));
    });
  });
}
