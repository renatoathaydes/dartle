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

```bash
dart dartle.dart
```

To run specific task(s), give them as arguments:

```bash
dart dartle.dart hello bye
```

Output:

```
Running task: hello
Hello!
Running task: bye
Bye!
```
