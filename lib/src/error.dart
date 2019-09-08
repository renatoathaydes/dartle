/// Indicates a fatal error during a dartle build.
class DartleException implements Exception {
  final String message;
  final int exitCode;

  DartleException({this.message = '', this.exitCode = 1});

  @override
  String toString() => 'DartException{message=$message, exitCode=$exitCode}';
}
