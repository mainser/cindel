library cindel_generator;

import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

import 'src/cindel_generator.dart';

export 'src/cindel_generator.dart';

/// Creates the Cindel source_gen builder.
Builder cindelBuilder(BuilderOptions options) {
  return SharedPartBuilder(const [CindelGenerator()], 'cindel');
}
