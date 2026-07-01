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

    List<int> frame = [sof, cmd, len];
    
    // Add escaped data
    for (int byte in data) {
      if (byte == sof || byte == eof || byte == esc) {
        frame.add(esc);
      }
      frame.add(byte);
    }

    // Add escaped checksum
    if (cs == sof || cs == eof || cs == esc) {
      frame.add(esc);
    }
    frame.add(cs);
    
    frame.add(eof);
    return frame;
  }

  /// Decodes a stream of bytes. 
  /// Returns a list of complete valid frames (as raw unescaped payloads [cmd, len, data...]), 
  /// and updates the buffer with any remaining partial bytes.
  static List<List<int>> decodeFrames(List<int> buffer) {
    List<List<int>> validFrames = [];
    int i = 0;
    
    while (i < buffer.length) {
      // Find SOF
      if (buffer[i] != sof) {
        i++;
        continue;
      }
      
      // We found SOF, try to parse a frame
      List<int> unescaped = [];
      bool escapeNext = false;
      int j = i + 1;
      bool foundEof = false;

      while (j < buffer.length) {
        int byte = buffer[j];
        if (escapeNext) {
          unescaped.add(byte);
          escapeNext = false;
        } else if (byte == esc) {
          escapeNext = true;
        } else if (byte == eof) {
          foundEof = true;
          break;
        } else if (byte == sof) {
          // Unexpected SOF, restart parsing from here
          break;
        } else {
          unescaped.add(byte);
        }
        j++;
      }

      if (foundEof) {
        // Validate frame structure
        if (unescaped.length >= 3) {
          int cmd = unescaped[0];
          int len = unescaped[1];
          // length of unescaped is: cmd(1) + len(1) + data(len) + cs(1) = 3 + len
          if (unescaped.length == 3 + len) {
            int dataEnd = 2 + len;
            List<int> data = unescaped.sublist(2, dataEnd);
            int receivedCs = unescaped[dataEnd];
            
            int calcCs = cmd ^ len;
            for (int b in data) {
              calcCs ^= b;
            }
            
            if (calcCs == receivedCs) {
              validFrames.add([cmd, len, ...data]);
            }
          }
        }
        // Consume up to j
        buffer.removeRange(0, j + 1);
        i = 0; // restart search from beginning of modified buffer
      } else {
        // Incomplete frame, wait for more data
        break;
      }
    }
    
    // Clean up garbage before the first SOF if no complete frame was found
    if (validFrames.isEmpty && buffer.isNotEmpty) {
      int firstSof = buffer.indexOf(sof);
      if (firstSof > 0) {
        buffer.removeRange(0, firstSof);
      } else if (firstSof == -1) {
        buffer.clear();
      }
    }

    return validFrames;
  }
}
