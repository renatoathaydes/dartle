final _functionNamePatttern = RegExp('[a-zA-Z_0-9]+');

class Task {
  final String name;
  final String description;
  final Function() action;

  Task(this.action, {this.description = '', String name})
      : this.name = _resolveName(action, name);

  static String _resolveName(Function() action, String name) {
    if (name == null || name.isEmpty) {
      final funName = "$action";
      final firstQuote = funName.indexOf("'");
      if (firstQuote > 0) {
        final match =
            _functionNamePatttern.firstMatch(funName.substring(firstQuote + 1));
        if (match != null) {
          return match.group(0);
        }
      }

      throw ArgumentError('Task name cannot be inferred. Either give the task '
          'a name explicitly or use a top-level function as its action');
    }
    return name;
  }

  @override
  String toString() => 'Task{name: $name}';
}
