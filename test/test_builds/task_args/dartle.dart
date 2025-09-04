import 'package:collection/collection.dart';
import 'package:dartle/dartle.dart';

void main(List<String> args) {
  run(
    args,
    tasks: {
      Task(
        (List<String> args) async {
          if (args.isEmpty) throw Exception('Args is empty');
          print('Args: ${args.join(' ')}');
        },
        name: 'requiresArgs',
        argsValidator: const AcceptAnyArgs(),
      ),
      Task(
        (List<String> args) async {
          print('ok');
        },
        name: 'noArgs',
        argsValidator: const DoNotAcceptArgs(),
      ),
      Task(
        (List<String> args) async {
          print('Args Sum: ${args.map(int.parse).sum}');
        },
        name: 'numberArgs',
        argsValidator: const OnlyNumberArgs(),
      ),
    },
  );
}

class OnlyNumberArgs implements ArgsValidator {
  const OnlyNumberArgs();

  @override
  String helpMessage() => 'only number arguments allowed';

  @override
  bool validate(List<String> args) =>
      args.every((arg) => int.tryParse(arg) != null);
}
