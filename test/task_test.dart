import 'package:dartle/dartle.dart';
import 'package:test/test.dart';

void noop(_) {}

final _a = Task(noop, name: 'a', dependsOn: {'b', 'c'});
final _b = Task(noop, name: 'b');
final _c = Task(noop, name: 'c');
final _d = Task(noop, name: 'd', dependsOn: {'a'});

// TaskWithDeps includes transitive dependencies
final _aw = TaskWithDeps(_a, [_bw, _cw]);
final _bw = TaskWithDeps(_b);
final _cw = TaskWithDeps(_c);
final _dw = TaskWithDeps(_d, [_bw, _cw, _aw]);

void main() {
  group('TaskWithDeps', () {
    test('can be created from simple tasks', () {
      var taskMap = createTaskMap([_a, _b, _c]);
      expect(taskMap, equals({'a': _aw, 'b': _bw, 'c': _cw}));

      taskMap = createTaskMap([_a, _b, _c, _d]);
      expect(taskMap, equals({'a': _aw, 'b': _bw, 'c': _cw, 'd': _dw}));
    });

    test('sorts correctly', () {
      var tasks = [_dw, _bw, _aw];
      tasks.sort();
      expect(tasks.map((t) => t.name), orderedEquals(['b', 'a', 'd']));

      tasks = [_aw, _dw, _bw];
      tasks.sort();
      expect(tasks.map((t) => t.name), orderedEquals(['b', 'a', 'd']));

      tasks = [_bw, _aw];
      tasks.sort();
      expect(tasks.map((t) => t.name), orderedEquals(['b', 'a']));

      tasks = [_cw, _aw];
      tasks.sort();
      expect(tasks.map((t) => t.name), orderedEquals(['c', 'a']));
    });

    test('detects direct dependency cycles', () {
      final e = Task(noop, name: 'e', dependsOn: {'f'});
      final f = Task(noop, name: 'f', dependsOn: {'e'});

      expect(
          () => createTaskMap([e, f]),
          throwsA(isA<DartleException>().having(
              (e) => e.message,
              'error message',
              equals('Task dependency cycle detected: [e -> f -> e]'))));
    });

    test('detects indirect dependency cycles', () {
      final e = Task(noop, name: 'e', dependsOn: {'f'});
      final f = Task(noop, name: 'f', dependsOn: {'g'});
      final g = Task(noop, name: 'g', dependsOn: {'h'});
      final h = Task(noop, name: 'h', dependsOn: {'e'});

      expect(
          () => createTaskMap([e, g, h, f]),
          throwsA(isA<DartleException>().having(
              (e) => e.message,
              'error message',
              equals('Task dependency cycle detected: '
                  '[e -> f -> g -> h -> e]'))));
    });

    test('cannot depend on non-declared dependency', () {
      var task = Task(noop, name: 't', dependsOn: {'g'});

      expect(
          () => createTaskMap([task]),
          throwsA(isA<DartleException>().having(
              (e) => e.message,
              'error message',
              equals("Task with name 'g' does not exist "
                  '(dependency path: [t -> g])'))));
    });
  });

  group('Tasks', () {
    test('can run in order of their dependencies', () async {
      var tasksInOrder = await getInOrderOfExecution(
          [_aw].map((t) => TaskInvocation(t)).toList());
      expect(
          tasksInOrder.map((t) => t.invocations.map((i) => i.name)),
          equals([
            ['b', 'c'],
            ['a']
          ]));

      tasksInOrder = await getInOrderOfExecution(
          [_aw, _bw, _cw, _dw].map((t) => TaskInvocation(t)).toList());
      expect(
          tasksInOrder.map((t) => t.invocations.map((i) => i.name)),
          equals([
            ['b', 'c'],
            ['a'],
            ['d']
          ]));

      tasksInOrder = await getInOrderOfExecution(
          [_dw].map((t) => TaskInvocation(t)).toList());
      expect(
          tasksInOrder.map((t) => t.invocations.map((i) => i.name)),
          equals([
            ['b', 'c'],
            ['a'],
            ['d']
          ]));
    });

    test('maintains provided order if no dependency between tasks', () async {
      var tasksInOrder = await getInOrderOfExecution(
          [_cw, _bw, _aw].map((t) => TaskInvocation(t)).toList());
      expect(
          tasksInOrder.map((t) => t.invocations.map((i) => i.name)),
          equals([
            ['c', 'b'],
            ['a']
          ]));

      tasksInOrder = await getInOrderOfExecution(
          [_aw, _cw, _bw, _dw].map((t) => TaskInvocation(t)).toList());
      expect(
          tasksInOrder.map((t) => t.invocations.map((i) => i.name)),
          equals([
            ['c', 'b'],
            ['a'],
            ['d']
          ]));
    });

    test('task in different phases are not executed in parallel', () async {
      final t1 = TaskWithDeps(Task(noop, name: 't1', phase: TaskPhase.setup));
      final t2 = TaskWithDeps(Task(noop, name: 't2', phase: TaskPhase.build));
      final t3 =
          TaskWithDeps(Task(noop, name: 't3', phase: TaskPhase.build), [t1]);
      final t4 = TaskWithDeps(
          Task(noop, name: 't4', phase: TaskPhase.build), [t1, t2, t3]);
      final t5 =
          TaskWithDeps(Task(noop, name: 't5', phase: TaskPhase.tearDown));
      var tasksInOrder = await getInOrderOfExecution(
          [t1, t2, t3, t4, t5].map((t) => TaskInvocation(t)).toList());
      expect(tasksInOrder, hasLength(4));
      // setup phase: all tasks run in parallel due to no deps between them
      expect(tasksInOrder[0].tasks.map((e) => e.task).toList(), equals([t1]));
      // build phase: first runs tasks without deps in same phase
      expect(
          tasksInOrder[1].tasks.map((e) => e.task).toList(), equals([t2, t3]));
      // build phase: next tasks due to deps
      expect(tasksInOrder[2].tasks.map((e) => e.task).toList(), equals([t4]));
      // teardown phase:
      expect(tasksInOrder[3].tasks.map((e) => e.task).toList(), equals([t5]));
    });
  });

  group('Task Verification', () {
    final fooTask = Task(noop,
        name: 'foo',
        runCondition:
            RunOnChanges(inputs: file('in.txt'), outputs: file('out.txt')));
    final barTask = Task(noop,
        name: 'bar',
        phase: TaskPhase.tearDown,
        runCondition:
            RunOnChanges(inputs: file('out.txt'), outputs: file('out2.txt')));
    final zortTask = Task(noop,
        name: 'zort',
        runCondition: RunOnChanges(inputs: dir('in'), outputs: dir('out')));
    final blahTask = Task(noop,
        name: 'blah',
        runCondition: RunOnChanges(inputs: dir('out'), outputs: dir('out2')));
    final deleteTask = Task(noop,
        phase: TaskPhase.setup,
        name: 'delete',
        runCondition: RunToDelete(files(['out.txt', 'in.txt'])));
    final deleteTaskBad = Task(noop,
        name: 'deleteBad',
        runCondition: RunToDelete(entities([
          'out2.txt',
        ], [
          DirectoryEntry(path: 'out')
        ])));

    test(
        'if a task outputs are used as inputs for other task, '
        'the other task must depend on it (files and dirs)', () {
      expect(
          () async => await verifyTaskInputsAndOutputsConsistency({
                'foo': TaskWithDeps(fooTask),
                'bar': TaskWithDeps(barTask),
                'zort': TaskWithDeps(zortTask),
                'blah': TaskWithDeps(blahTask),
              }),
          throwsA(isA<DartleException>().having(
              (e) => e.message,
              'message',
              equals(
                  'The following tasks have implicit dependencies due to their'
                  " inputs depending on other tasks' outputs:\n"
                  "  * Task 'bar' must dependOn 'foo' (clashing outputs: {out.txt}).\n"
                  "  * Task 'blah' must dependOn 'zort' (clashing outputs: {out}).\n\n"
                  'Please add the dependencies explicitly.\n'))));
    });

    test(
        'if a cleaning task affects other task, '
        'an error occurs when they run on the same phase', () {
      expect(
          () async => await verifyTaskInputsAndOutputsConsistency({
                'zort': TaskWithDeps(zortTask),
                'bar': TaskWithDeps(barTask),
                'deleteBad': TaskWithDeps(deleteTaskBad),
              }),
          throwsA(isA<DartleException>().having(
              (e) => e.message,
              'message',
              equals(
                  "The following tasks delete inputs or outputs of another task that "
                  "does not run on a later phase, hence could corrupt those tasks "
                  "execution:\n"
                  "  * Task 'deleteBad' (phase 'build') deletes outputs "
                  "of 'zort' (phase 'build'): {out}.\n\n"
                  "Please change the task phases so that deletion tasks run on "
                  "earlier phases (typically 'setup') than other tasks.\n"))));
    });

    test('no error occurs if tasks ins/outs are unrelated', () async {
      await verifyTaskInputsAndOutputsConsistency({
        'foo': TaskWithDeps(fooTask),
        'blah': TaskWithDeps(blahTask),
      });
    });

    test('no error occurs if tasks have common ins/outs but dependency exists',
        () async {
      await verifyTaskInputsAndOutputsConsistency({
        'foo': TaskWithDeps(fooTask),
        'bar': TaskWithDeps(barTask, [TaskWithDeps(fooTask)]),
      });
    });

    test(
        'no error occurs if the deletion task runs on an earlier phase than others',
        () async {
      final result = await verifyTaskInputsAndOutputsConsistency({
        'foo': TaskWithDeps(fooTask),
        'bar': TaskWithDeps(barTask, [TaskWithDeps(fooTask)]),
        'delete': TaskWithDeps(deleteTask),
        'deleteBad': TaskWithDeps(deleteTaskBad),
      });
      expect(
          result,
          equals(const {
            'foo': ['delete'],
            'bar': ['delete', 'deleteBad']
          }));
    });
  });

  group('Task Phase Verification', () {
    final setup1 =
        TaskWithDeps(Task(noop, name: 'setup1', phase: TaskPhase.setup));
    final setup2 = TaskWithDeps(
        Task(noop, name: 'setup2', phase: TaskPhase.setup), [setup1]);
    final build1 =
        TaskWithDeps(Task(noop, name: 'build1', phase: TaskPhase.build));
    final build2 = TaskWithDeps(
        Task(noop, name: 'build2', phase: TaskPhase.build),
        [setup1, setup2, build1]);
    final teardown1 =
        TaskWithDeps(Task(noop, name: 'teardown1', phase: TaskPhase.tearDown));
    final teardown2 = TaskWithDeps(
        Task(noop, name: 'teardown2', phase: TaskPhase.tearDown),
        [setup1, build1, teardown1]);

    final phasesTaskMap =
        createTaskMap([setup1, setup2, build1, build2, teardown1, teardown2]);

    test('tasks can depend on other tasks in the same or earlier phases', () {
      verifyTaskPhasesConsistency(phasesTaskMap);
    });

    test('tasks cannot depend on other tasks in a later phase than themselves',
        () {
      expect(
          () => verifyTaskPhasesConsistency({
                ...phasesTaskMap,
                'foo': TaskWithDeps(
                    Task(noop, name: 'foo', phase: TaskPhase.setup), [build1]),
                'bar': TaskWithDeps(
                    Task(noop, name: 'bar', phase: TaskPhase.build),
                    [teardown1]),
              }),
          throwsA(isA<DartleException>().having(
              (e) => e.message,
              'error message',
              equals(
                  'The following tasks have dependency on tasks which are in an incompatible build phase:\n'
                  "  * Task 'foo' in phase 'setup' cannot depend on 'build1' in phase 'build'.\n"
                  "  * Task 'bar' in phase 'build' cannot depend on 'teardown1' in phase 'tearDown'.\n"))));
    });
  });
}
