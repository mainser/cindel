import 'package:hooks/hooks.dart';
import 'package:native_toolchain_rust/native_toolchain_rust.dart';

const _buildNativeAssetsDefine = 'build_native_assets';

const _rustBuilder = RustBuilder(
  assetName: 'src/native/bindings.dart',
  cratePath: 'native',
);

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!_shouldBuildNativeAssets(input)) {
      return;
    }
    await _rustBuilder.run(input: input, output: output);
  });
}

bool _shouldBuildNativeAssets(BuildInput input) {
  final value = input.userDefines[_buildNativeAssetsDefine];
  return value == true || value == 'true' || value == '1';
}
