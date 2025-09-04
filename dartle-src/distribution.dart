import 'dart:io' show Platform;

import 'package:dartle/dartle.dart';

const tarFile = 'build/dartle.tar.gz';
final _executable = 'build/bin/dartle${Platform.isWindows ? '.exe' : ''}';
final tarContents = files(['README.md', 'LICENSE', _executable]);

final distributionTask = Task(
  distribution,
  description: 'Create binary executable distribution.',
  runCondition: RunOnChanges(inputs: tarContents, outputs: file(tarFile)),
);

Future<void> distribution(_) => tar(
  tarContents,
  destination: tarFile,
  destinationPath: (p) => p == _executable ? 'bin/dartle' : p,
);
