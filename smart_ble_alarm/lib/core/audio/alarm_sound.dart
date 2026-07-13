import 'dart:math';
import 'dart:typed_data';

/// Synthesizes a short, seamlessly-loopable alarm tone as an in-memory WAV
/// (16-bit PCM, mono, 44.1 kHz). Generated at runtime so the app ships no binary
/// audio asset — the Dedicated Clock loops these bytes through `audioplayers`.
///
/// Cadence: a 0.4 s 880 Hz beep followed by 0.2 s of silence, so looping yields
/// the classic "beep … beep …" of an alarm. The tone uses a whole number of
/// cycles and a 5 ms fade in/out so the loop boundary has no click.
Uint8List buildAlarmToneWav() {
  const int sampleRate = 44100;
  const double toneFreq = 880; // A5 — bright but not shrill
  const double toneSeconds = 0.4;
  const double silenceSeconds = 0.2;

  final int toneSamples = (sampleRate * toneSeconds).round();
  final int silenceSamples = (sampleRate * silenceSeconds).round();
  final int fade = (sampleRate * 0.005).round(); // 5 ms de-click ramp
  final int total = toneSamples + silenceSamples;

  final samples = Int16List(total);
  for (int i = 0; i < toneSamples; i++) {
    double amp = 0.6;
    if (i < fade) {
      amp *= i / fade;
    } else if (i > toneSamples - fade) {
      amp *= (toneSamples - i) / fade;
    }
    final double v = sin(2 * pi * toneFreq * i / sampleRate) * amp;
    samples[i] = (v * 32767).round();
  }
  // Trailing samples stay zero (silence).

  return _wrapWav(samples, sampleRate);
}

/// Wraps signed 16-bit mono PCM in a minimal canonical WAV container.
Uint8List _wrapWav(Int16List samples, int sampleRate) {
  const int channels = 1;
  const int bitsPerSample = 16;
  final int byteRate = sampleRate * channels * (bitsPerSample ~/ 8);
  final int blockAlign = channels * (bitsPerSample ~/ 8);
  final int dataBytes = samples.length * 2;

  final builder = BytesBuilder();
  void ascii(String s) => builder.add(s.codeUnits);
  void u32(int v) => builder.add(
    (ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List(),
  );
  void u16(int v) => builder.add(
    (ByteData(2)..setUint16(0, v, Endian.little)).buffer.asUint8List(),
  );

  // RIFF chunk descriptor.
  ascii('RIFF');
  u32(36 + dataBytes); // file size minus the first 8 bytes
  ascii('WAVE');
  // fmt sub-chunk.
  ascii('fmt ');
  u32(16); // PCM fmt chunk size
  u16(1); // audio format 1 = PCM
  u16(channels);
  u32(sampleRate);
  u32(byteRate);
  u16(blockAlign);
  u16(bitsPerSample);
  // data sub-chunk.
  ascii('data');
  u32(dataBytes);
  final pcm = ByteData(dataBytes);
  for (int i = 0; i < samples.length; i++) {
    pcm.setInt16(i * 2, samples[i], Endian.little);
  }
  builder.add(pcm.buffer.asUint8List());

  return builder.toBytes();
}
