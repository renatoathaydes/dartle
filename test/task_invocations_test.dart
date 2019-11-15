import 'package:collection/collection.dart';
import 'package:dartle/dartle.dart';
import 'package:dartle/src/task_invocation.dart';
import 'package:test/test.dart';

void noop([_]) {}

final _a = Task(noop, name: 'a', dependsOn: {'b', 'c'});
final _b = Task(noop, name: 'b');
final _c = Task(noop, name: 'c');
final _d = Task(noop, name: 'd', dependsOn: {'a'});

// TaskWithDeps includes transitive dependencies
final _aw = TaskWithDeps(_a, [_bw, _cw]);
final _bw = TaskWithDeps(_b);
final _cw = TaskWithDeps(_c);
final _dw = TaskWithDeps(_d, [_bw, _cw, _aw]);

final taskMap = {
  'a': _aw,
  'b': _bw,
  'c': _cw,
  'd': _dw,
};

void main() {
  group('task invocations can be parsed correctly', () {
    test(
        'single task',
        () => expect(parseInvocation(['a'], taskMap, const Options()),
            [equalsInvocation('a', [])]));
    test(
        'single task with single arg',
        () => expect(parseInvocation(['a', ':b'], taskMap, const Options()), [
              equalsInvocation('a', ['b'])
            ]));
    test(
        'single task with two args',
        () => expect(
                parseInvocation(['a', ':b', ':c'], taskMap, const Options()), [
              equalsInvocation('a', ['b', 'c'])
            ]));
    test(
        'two tasks with no args',
        () => expect(parseInvocation(['a', 'b'], taskMap, const Options()),
            [equalsInvocation('a', []), equalsInvocation('b', [])]));
    test(
        'two tasks, first with arg',
        () => expect(
                parseInvocation(['a', ':X', 'b'], taskMap, const Options()), [
              equalsInvocation('a', ['X']),
              equalsInvocation('b', [])
            ]));
    test(
        'two tasks, both have args',
        () => expect(
                parseInvocation(
                    ['a', ':X', ':Y', 'b', ':Z'], taskMap, const Options()),
                [
                  equalsInvocation('a', ['X', 'Y']),
                  equalsInvocation('b', ['Z']),
                ]));
    test(
        'several tasks with and without args',
        () => expect(
                parseInvocation(
                    ['a', 'b', 'c', ':hello', ':world', 'd', ':final'],
                    taskMap,
                    const Options()),
                [
                  equalsInvocation('a', []),
                  equalsInvocation('b', []),
                  equalsInvocation('c', ['hello', 'world']),
                  equalsInvocation('d', ['final']),
                ]));
  });

  group('task invocation errors', () {
    test('arg without task', () {
      expect(
          () => parseInvocation([':foo'], taskMap, const Options()),
          throwsA(isA<DartleException>().having(
              (e) => e.message,
              'expected message',
              equals(
                  "Invocation problem: Argument should follow a task: ':foo'"))));
    });
    test('non-existing task', () {
      expect(
          () => parseInvocation(['bad-task'], taskMap, const Options()),
          throwsA(isA<DartleException>().having(
              (e) => e.message,
              'expected message',
              equals("Invocation problem: Task 'bad-task' does not exist"))));
    });
    test('arg without task AND non-existing task', () {
      expect(
          () => parseInvocation([':foo', 'bad-task'], taskMap, const Options()),
          throwsA(isA<DartleException>().having(
              (e) => e.message,
              'expected message',
              equals("Several invocation problems found:\n"
                  "  * Argument should follow a task: ':foo'\n"
                  "  * Task 'bad-task' does not exist"))));
    });
  });
}

TaskInvocationMatcher equalsInvocation(String taskName, List<String> args) =>
    TaskInvocationMatcher(taskName, args);

class TaskInvocationMatcher extends Matcher {
  final String taskName;
  final List<String> args;

  TaskInvocationMatcher(this.taskName, this.args);

  Description describe(Description description) {
    return description.add("task '$taskName', args $args");
  }

  @override
  bool matches(item, Map matchState) {
    if (item is TaskInvocation) {
      return item.task.name == taskName &&
          const ListEquality().equals(item.args, args);
    }
    return false;
  }
}
