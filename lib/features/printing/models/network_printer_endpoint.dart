/// Manual TCP endpoint. URLs, credentials, paths and inline ports are rejected.
/// V1 supports IPv4 literals and ASCII DNS names with a separate port.
class NetworkPrinterEndpoint {
  const NetworkPrinterEndpoint._(this.host, this.port);
  final String host;
  final int port;

  factory NetworkPrinterEndpoint.parse(String host, int port) {
    final value = host.trim().toLowerCase();
    if (port < 1 || port > 65535 || !_validHost(value)) {
      throw const FormatException('Invalid printer address');
    }
    return NetworkPrinterEndpoint._(value, port);
  }

  static bool _validHost(String host) {
    if (host.isEmpty || host.length > 253) return false;
    // V1 accepts IPv4 and DNS names. IPv6 can be added with explicit parsing.
    if (RegExp(r'^[0-9.]+$').hasMatch(host)) {
      final parts = host.split('.');
      return parts.length == 4 &&
          parts.every((p) {
            final n = int.tryParse(p);
            return p.isNotEmpty &&
                p.length <= 3 &&
                n != null &&
                n <= 255 &&
                (p.length == 1 || !p.startsWith('0'));
          });
    }
    return host
        .split('.')
        .every(
          (part) =>
              part.length <= 63 &&
              RegExp(r'^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$').hasMatch(part),
        );
  }

  String printerId(String locationId) =>
      'network:${Uri.encodeComponent(locationId)}:$host:$port';
}
