class ApiException implements Exception {
  const ApiException({required this.message, this.statusCode, this.cause});

  final String message;
  final int? statusCode;
  final Object? cause;

  @override
  String toString() {
    final String status = statusCode == null ? '' : ' ($statusCode)';
    return 'ApiException$status: $message';
  }
}
