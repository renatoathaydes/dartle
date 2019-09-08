# Dartle

A simple build system written in Dart.
 
Dartle is designed to integrate well with [pub](https://dart.dev/tools/pub/cmd) and Dart's own
[build system](https://github.com/dart-lang/build), but help with automation tasks not covered by other tools.

It is inspired by [Gradle](https://gradle.org/).

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

final allTasks = [Task(hello), Task(bye)];

main(List<String> args) async =>
    run(args, tasks: allTasks, defaultTasks: allTasks.sublist(0, 1));

hello() async {
  print("Hello!");
}

bye() async {
  print("Bye!");
}
```

#### Run your build!

##### Option 1: using dartle

You can use the `dartle` executable directly, which will snapshot your `dartle.dart` file
and potentially run it faster.

First, activate it with `pub`:

```bash
pub global activate dartle
```

Now, simply run `dartle` (it will execute the `dartle.dart` file found in the working directory):

```bash
dartle
```

To run specific task(s), give them as arguments:

```bash
dartle hello bye
```

Output:

```
Running task: hello
Hello!
Running task: bye
Bye!
```

Notice that the `dartle` executable will cache resources to make builds run faster.
It uses the `.dartle_tool/` directory, in the working directory, to manage the cache.
**You should not commit this directory into source control** as it caches resources based on their
absolute paths.

##### Option 2: using dart

As `dartle.dart` files are simple Dart files, you can also execute them with `dart`, of course:

```bash
dart dartle.dart
```

To run specific task(s), give them as arguments:

```bash
dart dartle.dart hello bye
```
