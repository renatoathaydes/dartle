import 'package:dartle/dartle.dart';

const _executable = 'build/bin/dartle';
const tarFile = 'build/dartle.tar.gz';
final tarContents = files(const ['README.md', 'LICENSE', _executable]);

final distributionTask = Task(distribution,
    description: 'Create binary executable distribution.',
    runCondition: RunOnChanges(inputs: tarContents, outputs: file(tarFile)));

Future<void> distribution(_) => tar(tarContents,
    destination: tarFile,
    destinationPath: (p) => p == _executable ? 'bin/dartle' : p);
