import 'dart:convert' show utf8;
import 'dart:io';
import 'dart:typed_data' show Uint8List;

import 'package:convert/convert.dart' show AccumulatorSink;
import 'package:crypto/crypto.dart' show Digest, sha1;

Digest hash(String text) => hashBytes(utf8.encode(text));

Digest hashBytes(List<int> bytes) => sha1.convert(bytes);

const _bufferLength = 4096;

Future<Digest> hashFile(File file) async {
  final sink = AccumulatorSink<Digest>();
  final converter = sha1.startChunkedConversion(sink);
  final fileHandle = await file.open(mode: FileMode.read);
  try {
    final buffer = Uint8List(_bufferLength);
    var isLast = false;
    while (!isLast) {
      final count = await fileHandle.readInto(buffer);
      isLast = count < _bufferLength;
      converter.addSlice(buffer, 0, count, isLast);
    }
    converter.close();
    return sink.events.single;
  } finally {
    await fileHandle.close();
  }
}

Digest hashAll(Iterable<List<int>> items) {
  final sink = AccumulatorSink<Digest>();
  final converter = sha1.startChunkedConversion(sink);
  for (final item in items) {
    converter.add(item);
  }
  converter.close();
  return sink.events.single;
}
