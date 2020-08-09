/// Indicates a fatal error during a dartle build.
class DartleException implements Exception {
  final String message;
  final int exitCode;

  DartleException({required this.message, this.exitCode = 1});

  @override
  String toString() => 'DartleException{message=$message, exitCode=$exitCode}';
}
