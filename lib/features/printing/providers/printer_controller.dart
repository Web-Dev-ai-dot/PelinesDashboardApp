import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/printer_settings.dart';
import 'printing_providers.dart';

final printerControllerProvider = AsyncNotifierProvider.autoDispose
    .family<PrinterController, PrinterSettings, String>(PrinterController.new);

class PrinterController extends AsyncNotifier<PrinterSettings> {
  PrinterController(this.locationId);
  final String locationId;
  @override
  Future<PrinterSettings> build() async =>
      (await ref.watch(printingRuntimeProvider.future)).settings
          .read(locationId);
  Future<void> save(PrinterSettings settings) async {
    if (settings.locationId != locationId) {
      throw ArgumentError('Location mismatch.');
    }
    final runtime = await ref.read(printingRuntimeProvider.future);
    await runtime.saveSettings(settings);
    state = AsyncData(settings);
    runtime.queue.kick();
  }
}
