class PrinterCapabilities {
  const PrinterCapabilities({
    this.cutter = false,
    this.paperWidth,
    this.statusReporting = false,
    this.bluetooth = false,
    this.network = false,
    this.usb = false,
    this.rawEscPos = false,
    this.epsonSdk = false,
  });
  final bool cutter,
      statusReporting,
      bluetooth,
      network,
      usb,
      rawEscPos,
      epsonSdk;

  /// Printable paper width in millimeters, unknown until hardware is selected.
  final int? paperWidth;
}
