import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

void main() {
  const int sampleRate = 44100;
  const double duration = 0.42;
  final int samples = (sampleRate * duration).round();
  final BytesBuilder pcm = BytesBuilder();
  for (int i = 0; i < samples; i++) {
    final double t = i / sampleRate;
    final double envelope = pow(1 - i / samples, 2).toDouble();
    final double tone =
        sin(2 * pi * 659.25 * t) * 0.55 + sin(2 * pi * 987.77 * t) * 0.25;
    final int value = (tone * envelope * 14000).round().clamp(-32768, 32767);
    pcm.add(<int>[value & 0xff, (value >> 8) & 0xff]);
  }
  final Uint8List audio = pcm.takeBytes();
  final ByteData header = ByteData(44)
    ..setUint32(0, 0x52494646, Endian.big)
    ..setUint32(4, 36 + audio.length, Endian.little)
    ..setUint32(8, 0x57415645, Endian.big)
    ..setUint32(12, 0x666d7420, Endian.big)
    ..setUint32(16, 16, Endian.little)
    ..setUint16(20, 1, Endian.little)
    ..setUint16(22, 1, Endian.little)
    ..setUint32(24, sampleRate, Endian.little)
    ..setUint32(28, sampleRate * 2, Endian.little)
    ..setUint16(32, 2, Endian.little)
    ..setUint16(34, 16, Endian.little)
    ..setUint32(36, 0x64617461, Endian.big)
    ..setUint32(40, audio.length, Endian.little);
  final Directory projectRoot = File.fromUri(Platform.script).parent.parent;
  final File output = File(
    '${projectRoot.path}${Platform.pathSeparator}assets${Platform.pathSeparator}sounds${Platform.pathSeparator}new_order.wav',
  );
  output.parent.createSync(recursive: true);
  output.writeAsBytesSync(<int>[...header.buffer.asUint8List(), ...audio]);
}
