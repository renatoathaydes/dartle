import 'package:dartle/dartle.dart';

void main(List<String> args) async {
  await runSafely(args, false, (stopWatch, options) async {
    activateLogging(options.logLevel, colorfulLog: options.colorfulLog);
    await runDartlex(args);
  });
}
