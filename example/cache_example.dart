import 'package:args/args.dart';
import 'package:dartle/dartle_cache.dart';
import 'package:dartle/dartle_dart.dart';
import 'package:dartle/src/_log.dart';
import 'package:io/ansi.dart' as ansi;
import 'package:logging/logging.dart';

final log = Logger('dartle-cache');

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
  } else {
    activateLogging(Level.INFO);
  }

  log.info(const ColoredLogMessage('Dartle Cache Example', LogColor.magenta));

  final key = options['key']?.toString() ?? '';

  final cmd = options.command;
  if (cmd != null) {
    switch (cmd.name) {
      case "clean":
        logger.info('Cleaning cache');
        await cache.clean(key: key);
        break;
      case "cache":
        for (final directory in cmd.arguments) {
          logger.info('Caching $directory');
          await cache(dir(directory), key: key);
        }
        break;
      case "diff":
        for (final directory in cmd.arguments) {
          logger.info('Checking $directory');
          await for (final change
              in cache.findChanges(dir(directory), key: key)) {
            log.severe(ColoredLogMessage(
                '${change.path} has been ${change.kind.name}',
                colorFor(change.kind)));
          }
        }
    }
    log.severe(AnsiMessage(const [
      AnsiMessagePart.code(ansi.styleBold),
      AnsiMessagePart.text('All done!')
    ]));
  } else {
    log.severe('ERROR! No command selected.\n\n'
        'Usage:\n  cache_example [-options] <clean|cache|diff> dir'
        'Options:\n${parser.usage}');
  }
}

LogColor colorFor(ChangeKind kind) {
  switch (kind) {
    case ChangeKind.added:
      return LogColor.green;
    case ChangeKind.deleted:
      return LogColor.red;
    case ChangeKind.modified:
      return LogColor.blue;
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
