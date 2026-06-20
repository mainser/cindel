import 'dart:async';

import 'backup.dart';

CindelBackupCompression get defaultCindelBackupCompression =>
    CindelBackupCompression.none;

Stream<List<int>> encodeBackupBytes(
  Stream<List<int>> input,
  CindelBackupCompression compression,
) {
  return switch (compression) {
    CindelBackupCompression.none => input,
    CindelBackupCompression.gzip => throw UnsupportedError(
      'Gzip backup compression is not available on this platform.',
    ),
  };
}

Stream<List<int>> decodeBackupBytes(
  Stream<List<int>> input,
  CindelBackupCompression compression,
) {
  return switch (compression) {
    CindelBackupCompression.none => input,
    CindelBackupCompression.gzip => throw UnsupportedError(
      'Gzip backup compression is not available on this platform.',
    ),
  };
}
