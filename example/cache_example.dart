import 'package:args/args.dart';
import 'package:dartle/dartle_cache.dart';
import 'package:dartle/src/_log.dart';
import 'package:logging/logging.dart';

Future<void> main(List<String> args) async {
  final cache = DartleCache('dartle-cache');

  final parser = ArgParser()
    ..addOption('log-level',
        abbr: 'l',
        valueHelp: 'one of debug|info|warn',
        allowed: const {'debug', 'info', 'warn'})
    ..addOption('key', abbr: 'k')
    ..addCommand('clean')
    ..addCommand('cache')
    ..addCommand('diff');

  final options = parser.parse(args);

  if (options.wasParsed('log-level')) {
    activateLogging(logLevel(options['log-level']));
  }

  final key = options['key']?.toString() ?? '';

  final cmd = options.command;
  if (cmd != null) {
    switch (cmd.name) {
      case "clean":
        await cache.clean(key: key);
        break;
      case "cache":
        for (final directory in cmd.arguments) {
          print('Caching $directory');
          await cache(dir(directory), key: key);
        }
        print('All done!');
        break;
      case "diff":
        for (final directory in cmd.arguments) {
          print('Checking $directory');
          await for (final change
              in cache.findChanges(dir(directory), key: key)) {
            print('${change.entity} has been ${change.kind.name}');
          }
          print('Done!');
        }
    }
  } else {
    print('ERROR! No command selected.\n${parser.usage}');
  }
}

Level logLevel(value) {
  switch (value) {
    case 'debug':
      return Level.FINE;
    case 'info':
      return Level.INFO;
    case 'warn':
      return Level.WARNING;
    default:
      throw 'Not a log level: $value';
  }
}
