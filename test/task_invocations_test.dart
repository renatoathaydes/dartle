import 'package:collection/collection.dart';
import 'package:dartle/dartle.dart';
import 'package:dartle/src/task_invocation.dart';
import 'package:test/test.dart';

void noop([_]) {}

final _a = Task(noop,
    name: 'a', dependsOn: {'b', 'c'}, argsValidator: const AcceptAnyArgs());
final _b = Task(noop, name: 'b', argsValidator: const AcceptAnyArgs());
final _c = Task(noop,
    name: 'c', argsValidator: const ArgsCount.range(min: 2, max: 3));
final _d = Task(noop,
    name: 'd', dependsOn: {'a'}, argsValidator: const ArgsCount.count(1));

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
    test('task requires one arg but gets none', () {
      expect(
          () => parseInvocation(['d'], taskMap, const Options()),
          throwsA(isA<DartleException>().having(
              (e) => e.message,
              'expected message',
              equals("Invocation problem: Invalid arguments for task 'd': [] - "
                  "exactly 1 argument is expected"))));
    });
    test('task requires one arg but gets two', () {
      expect(
          () => parseInvocation(['d', ':x', ':z'], taskMap, const Options()),
          throwsA(isA<DartleException>().having(
              (e) => e.message,
              'expected message',
              equals(
                  "Invocation problem: Invalid arguments for task 'd': [x, z] - "
                  "exactly 1 argument is expected"))));
    });
    test('task requires 2..3 arg but gets none', () {
      expect(
          () => parseInvocation(['c'], taskMap, const Options()),
          throwsA(isA<DartleException>().having(
              (e) => e.message,
              'expected message',
              equals("Invocation problem: Invalid arguments for task 'c': [] - "
                  "between 2 and 3 arguments expected"))));
    });
    test('task requires 2..3 arg but gets four', () {
      expect(
          () => parseInvocation(
              ['c', ':1', ':2', ':3', ':4'], taskMap, const Options()),
          throwsA(isA<DartleException>().having(
              (e) => e.message,
              'expected message',
              equals(
                  "Invocation problem: Invalid arguments for task 'c': [1, 2, 3, 4] - "
                  "between 2 and 3 arguments expected"))));
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
