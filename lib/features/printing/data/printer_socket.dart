import 'dart:async';
import 'dart:io';

import '../models/network_printer_endpoint.dart';

abstract interface class PrinterSocket {
  void add(List<int> bytes);
  Future<void> flush();
  Future<void> close();
  void destroy();
}

abstract interface class PrinterSocketConnector {
  Future<PrinterSocket> connect(
    NetworkPrinterEndpoint endpoint,
    Duration timeout,
  );
}

class DartPrinterSocketConnector implements PrinterSocketConnector {
  const DartPrinterSocketConnector();
  @override
  Future<PrinterSocket> connect(
    NetworkPrinterEndpoint endpoint,
    Duration timeout,
  ) async => _DartPrinterSocket(
    await Socket.connect(endpoint.host, endpoint.port, timeout: timeout),
  );
}

class _DartPrinterSocket implements PrinterSocket {
  _DartPrinterSocket(this.socket) {
    // Listen immediately so asynchronous remote errors cannot escape the adapter.
    // Status bytes are deliberately ignored in V1, never interpreted as success.
    socket.listen(
      (_) {},
      onError: (Object error) {
        _error = error;
      },
      onDone: () {
        _ended = true;
      },
    );
    unawaited(
      socket.done.then<void>(
        (_) {},
        onError: (Object error) {
          _error = error;
        },
      ),
    );
  }
  final Socket socket;
  Object? _error;
  bool _ended = false;
  void _check() {
    if (_error != null || _ended) {
      throw const SocketException('Printer connection closed');
    }
  }

  @override
  void add(List<int> bytes) {
    _check();
    socket.add(bytes);
  }

  @override
  Future<void> flush() async {
    _check();
    await socket.flush();
    _check();
  }

  @override
  Future<void> close() async {
    await socket.close();
    if (_error != null) throw _error!;
  }

  @override
  void destroy() => socket.destroy();
}
