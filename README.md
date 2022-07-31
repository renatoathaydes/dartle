# Dartle

![Dartle CI](https://github.com/renatoathaydes/dartle/workflows/Dartle%20CI/badge.svg)
[![pub package](https://img.shields.io/pub/v/dartle.svg)](https://pub.dev/packages/dartle)

A simple task runner written in Dart.

The goal with Dartle is to define a (sometimes large) number of tasks where only a few of them
are actually explicitly invoked by a human.

Dartle makes sure that every task that _needs to run_, but no others, actually run when you ask it to run
one or more tasks.

For example, Dartle's own build has the following tasks (as shown by running `dartle --show-tasks`):
 
```
  generateDartSources ---> format       ---> analyzeCode ---> test ---> build
                           checkImports                                      
                           runPubGet                                         

```

> Note: Tasks on the same _column_ may run in parallel.

When you invoke, say, `dartle analyzeCode`, Dartle will make sure that the
`analyseCode` task will run, but also that all its dependencies, `generateDartSources`,
`format`, `checkImports` and `runPubGet` will run first as long as their `runCondition`
requires them to run. If any of these tasks doesn't need to run, it is automatically
skipped.

Dartle has several `RunCondition`s to determine when a task is up-to-date or needs to run:

- `RunOnChanges` - run task if any inputs/outputs changed since last run.
- `RunAtMostEvery` - run task at most every T, where T is a period of time.
- `RunToDelete` - run task if any of its outputs _exists_.

There are also combiners like `AndCondition` and `OrCondition` (and you can define your own conditions).

For example, the `runPubGet` task runs if `pubspec.yaml` changes OR if it has not been run for
one week.

## How to use

#### Add `dartle` to your `dev_dependencies`:

```bash
dart pub add -d dartle
```

#### Write a dartle build file

> A basic `dartle.dart` file can be automatically generated by invoking `dartle`
> on a directory where `dartle.dart` does not exist yet.

_dartle.dart_

```dart
import 'package:dartle/dartle.dart';

final allTasks = [
  Task(hello, argsValidator: const ArgsCount.range(min: 0, max: 1)),
  Task(bye, dependsOn: const {'hello'}),
  Task(clean),
];

main(List<String> args) async =>
    run(args, tasks: allTasks.toSet(), defaultTasks: {allTasks[0]});

/// To pass an argument to a task, use a ':' prefix, e.g.:
/// dartle hello :joe
hello(List<String> args) =>
    print("Hello ${args.isEmpty ? 'World' : args[0]}!");

/// If no arguments are expected, use `_` as the function parameter.
bye(_) => print("Bye!");

clean(_) => deleteOutputs(allTasks);
```

#### Run your build!

In **dev mode** (while you're setting up your build), use `dart` to run the build file directly:

```bash
dart dartle.dart <tasks>
```

> Notice that all `dev_dependencies` can be used in your build! And all Dart tools work with it, 
> including the Observatory and debugger, after all this is just plain Dart!

Once you're done with the basics of your build, it is recommended to install Dartle for faster
performance.

To install Dartle:

```bash
dart pub global activate dartle
```

Now, you can run your build with the `dartle` command:

```bash
dartle <tasks>
```

> `dartle` automatically re-compiles the `dartle.dart` script into an executable if necessary
> to make builds run so fast they feel instant!

### Selecting tasks

If no task is explicitly invoked, Dartle runs the `defaultTasks` defined in the build, or does nothing if none was defined.

To run specific task(s), give them as arguments when invoking `dartle`:

```bash
dartle hello bye
```

Output:

```
2020-02-06 20:53:26.917795 - dartle[main] - INFO - Executing 2 tasks out of a total of 4 tasks: 2 tasks selected, 0 due to dependencies
2020-02-06 20:53:26.918155 - dartle[main] - INFO - Running task 'hello'
Hello World!
2020-02-06 20:53:26.918440 - dartle[main] - INFO - Running task 'bye'
Bye!
✔ Build succeeded in 3 ms
```

> Notice that Dartle will cache resources to make builds run faster.
> It uses the `.dartle_tool/` directory, in the working directory, to manage the cache.
> **You should not commit the `.dartle_tool/` directory into source control**.

To provide arguments to a task, provide the argument immediately following the task invocation, prefixing it with `:`:

```bash
./dartlex hello :Joe
```

Prints:

```
2020-02-06 20:55:00.502056 - dartle[main] - INFO - Executing 1 task out of a total of 4 tasks: 1 task selected, 0 due to dependencies
2020-02-06 20:55:00.502270 - dartle[main] - INFO - Running task 'hello'
Hello Joe!
✔ Build succeeded in 1 ms
```

### Declaring tasks

The preferred way to declare a task is by wrapping a top-level function, as shown in the example above.

Basically:

```dart
import 'package:dartle/dartle.dart';

final allTasks = {Task(hello)};

main(List<String> args) async => run(args, tasks: allTasks);

hello(_) => print("Hello Dartle!");
```

This allows the task to run in parallel with other tasks on different `Isolate`s (potentially on different CPU cores).

If that's not important, a lambda can be used, but in such case the task's name must be provided explicitly (because
lambdas have no name):

```dart
import 'package:dartle/dartle.dart';

final allTasks = {Task((_) => print("Hello Dartle!"), name: 'hello')};

main(List<String> args) async => run(args, tasks: allTasks);
```

A Task's function should only take arguments if it declares an `ArgsValidator`, as shown in the example:

```dart
Task(hello, argsValidator: const ArgsCount.range(min: 0, max: 1))

...

hello(List<String> args) => ...
```

A Task will not be executed if its `argsValidator` is not satisfied (Dartle will fail the build if that happens).

### Task dependencies and run conditions

A Task can depend on other task(s), so that whenever it runs, its dependencies also run
(as long as they are not up-to-date).

In the example above, the `bye` task depends on the `hello` task:

```dart
Task(bye, dependsOn: const {'hello'})
```

This means that whenever `bye` runs, `hello` runs first.

> Notice that tasks that have no dependencies between themselves can run _at the same time_ -
> either on the same `Isolate` or in separate `Isolates` (use the `-p` flag to indicate that tasks may
> run in different `Isolate`s when possible, i.e. when their action is a top-level function and there's no dependencies
> with the other tasks).

A task may be skipped if it's up-to-date according to its `RunCondition`. The example Dart file demonstrates that:

```dart
Task(encodeBase64,
  description: 'Encodes input.txt in base64, writing to output.txt',
  runCondition: RunOnChanges(
    inputs: file('input.txt'),
    outputs: file('output.txt'),
  ))
```

The above task only runs if at least one of these conditions is true:

* `output.txt` does not yet exist.
* either `input.txt` or `output.txt` changed since last time this task ran.
* the `-f` or `--force-tasks` flag is used.

If a `RunCondition` is not provided, the task is always considered out-of-date.

> To force all tasks to run, use the `-z` or `--reset-cache` flag.

### Help

For more help, run `dartle -h`. Proper documentation is going to be available soon! 

## Prior Art

Dartle is inspired by [Gradle](https://gradle.org/) and, loosely,
[Make](https://www.gnu.org/software/make/) and [Apache Ant](https://ant.apache.org/).
