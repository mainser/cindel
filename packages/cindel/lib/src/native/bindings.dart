import 'dart:ffi';

const _assetId = 'package:cindel/src/native/bindings.dart';

final class CindelNativeBindings {
  const CindelNativeBindings();

  int get abiVersion => _cindelAbiVersion();

  Pointer<Void> open() => _cindelOpen();

  void close(Pointer<Void> handle) => _cindelClose(handle);
}

@Native<Uint32 Function()>(
  symbol: 'cindel_abi_version',
  assetId: _assetId,
  isLeaf: true,
)
external int _cindelAbiVersion();

@Native<Pointer<Void> Function()>(
  symbol: 'cindel_open',
  assetId: _assetId,
  isLeaf: true,
)
external Pointer<Void> _cindelOpen();

@Native<Void Function(Pointer<Void>)>(
  symbol: 'cindel_close',
  assetId: _assetId,
  isLeaf: true,
)
external void _cindelClose(Pointer<Void> handle);
