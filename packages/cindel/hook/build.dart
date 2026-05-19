import 'package:hooks/hooks.dart';
import 'package:native_toolchain_rust/native_toolchain_rust.dart';

const _rustBuilder = RustBuilder(
  assetName: 'src/native/bindings.dart',
  cratePath: 'native',
);

void main(List<String> args) async {
  await build(args, (input, output) async {
    await _rustBuilder.run(input: input, output: output);
  });
}
