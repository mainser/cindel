import 'dart:async';
import 'dart:io';

import 'backup.dart';

CindelBackupCompression get defaultCindelBackupCompression =>
    CindelBackupCompression.gzip;

Stream<List<int>> encodeBackupBytes(
  Stream<List<int>> input,
  CindelBackupCompression compression,
) {
  return switch (compression) {
    CindelBackupCompression.none => input,
    CindelBackupCompression.gzip => gzip.encoder.bind(input),
  };
}

Stream<List<int>> decodeBackupBytes(
  Stream<List<int>> input,
  CindelBackupCompression compression,
) {
  return switch (compression) {
    CindelBackupCompression.none => input,
    CindelBackupCompression.gzip => gzip.decoder.bind(input),
  };
}
