class BleFraming {
  static const int sof = 0x5B; // '['
  static const int eof = 0x5D; // ']'
  static const int esc = 0x5C; // '\'

  /// Encodes a command and payload into a framed byte array
  static List<int> encodeFrame(int cmd, List<int> data) {
    if (data.length > 15) {
      throw Exception("Payload too long (max 15 bytes)");
    }

    int len = data.length;
    int cs = cmd ^ len;
    for (int byte in data) {
      cs ^= byte;
    }

    final List<int> frame = [sof];

    // Escape every body byte uniformly — cmd, len, data and checksum alike — so
    // the decoder (which unescapes uniformly from the byte after SOF) can never
    // mistake a body byte that happens to equal SOF/EOF/ESC for a delimiter.
    for (final int byte in [cmd, len, ...data, cs]) {
      if (byte == sof || byte == eof || byte == esc) {
        frame.add(esc);
      }
      frame.add(byte);
    }

    frame.add(eof);
    return frame;
  }

  /// Decodes a stream of bytes.
  /// Returns complete valid frames as [cmd, len, data...],
  /// and updates the buffer with any remaining partial bytes.
  static List<List<int>> decodeFrames(List<int> buffer) {
    final validFrames = <List<int>>[];

    while (buffer.isNotEmpty) {
      final start = buffer.indexOf(sof);
      if (start < 0) {
        buffer.clear();
        break;
      }

      if (start > 0) {
        buffer.removeRange(0, start);
      }

      final unescaped = <int>[];
      var escapeNext = false;
      int? eofIndex;
      var restarted = false;

      for (var index = 1; index < buffer.length; index++) {
        final byte = buffer[index];

        if (escapeNext) {
          unescaped.add(byte);
          escapeNext = false;
          continue;
        }

        if (byte == esc) {
          escapeNext = true;
          continue;
        }

        if (byte == sof) {
          buffer.removeRange(0, index);
          restarted = true;
          break;
        }

        if (byte == eof) {
          eofIndex = index;
          break;
        }

        unescaped.add(byte);
      }

      if (restarted) continue;
      if (eofIndex == null) break;

      if (_isValidUnescapedFrame(unescaped)) {
        final cmd = unescaped[0];
        final len = unescaped[1];
        validFrames.add([cmd, len, ...unescaped.sublist(2, 2 + len)]);
      }

      buffer.removeRange(0, eofIndex + 1);
    }

    return validFrames;
  }

  static bool _isValidUnescapedFrame(List<int> frame) {
    if (frame.length < 3) return false;

    final cmd = frame[0];
    final len = frame[1];
    if (len > 15 || frame.length != 3 + len) return false;

    final data = frame.sublist(2, 2 + len);
    final receivedChecksum = frame[2 + len];
    var calculatedChecksum = cmd ^ len;

    for (final byte in data) {
      calculatedChecksum ^= byte;
    }

    return calculatedChecksum == receivedChecksum;
  }
}
