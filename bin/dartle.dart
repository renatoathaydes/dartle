import 'dart:io';
import 'dart:isolate';

import 'package:dartle/dartle_cache.dart';

void main(List<String> args) async {
  final buildFile = File('dartle.dart').absolute;
  if (await buildFile.exists()) {
    final cache = DartleCache(args);
    final cachedFile = await cache.loadDartSnapshot(buildFile);
    final exitPort = ReceivePort();
    await Isolate.spawnUri(cachedFile.absolute.uri, args, null,
        debugName: 'dartle-runner', onExit: exitPort.sendPort);
    await exitPort.first;
  } else {
    print('Error: No dartle.dart file provided.');
    exit(4);
  }
}
