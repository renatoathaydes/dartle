# Dartle

A simple build system (or task runner, really) written in Dart.
 
Dartle is designed to integrate well with [pub](https://dart.dev/tools/pub/cmd) and Dart's own
[build system](https://github.com/dart-lang/build), but help with automation tasks not covered by other tools.

It is inspired by [Gradle](https://gradle.org/) and, loosely, [Make](https://www.gnu.org/software/make/).

## How to use

#### Add `dartle` to your `dev_dependencies`:

_pubspec.yaml_

```yaml
dev_dependencies:
  dartle:
```

#### Write a dartle build file

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

In **dev mode**, use `dart` to run the build file directly:

```bash
dart dartle.dart
```

> Notice that all `dev_dependencies` can be used in your build! And all Dart tools work with it, 
> including the Observatory and debugger, after all this is just plain Dart!

Once you're done making changes to the build file (at least for a while), run it with `dartle` instead:

1. Activate `dartle` (only first time)

```bash
pub global activate dartle
```

2. Run the build

```bash
dartle
```

This will execute the default tasks in the build file, `dartle.dart`, which should be located in the working directory,
after compiling it to native using 
[dart2native](https://medium.com/dartlang/dart2native-a76c815e6baf)
(if available, otherwise it will use `dart --snapshot`) whenever necessary (i.e. every time a change is made to 
the build file or `pubspec.yaml`).

### Selecting tasks

In the examples above, the `defaultTasks` ran because no argument was provided to Dartle.

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

> Notice that the `dartle` executable will cache resources to make builds run faster.
> It uses the `.dartle_tool/` directory, in the working directory, to manage the cache.
> **You should not commit the `.dartle_tool/` directory into source control**.

To provide arguments to a task, provide the argument immediately following the task invocation, prefixing it with `:`:

```bash
dartle hello :Joe
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
