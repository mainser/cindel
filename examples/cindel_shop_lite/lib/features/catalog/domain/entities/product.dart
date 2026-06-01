import 'package:cindel/cindel.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'product.freezed.dart';
part 'product.g.dart';

/// Product document stored in the local Cindel catalog collection.
///
/// This uses Freezed's primary factory style while Cindel generates the schema,
/// serializers, typed collection accessors, and query builders from the same
/// class.
@freezed
@Collection(name: 'products')
abstract class Product with _$Product {
  const factory Product({
    required Id dbId,
    @Index(unique: true) required String sku,
    @Index() required String name,
    required String description,
    @Index(type: CindelIndexType.words, caseSensitive: false)
    required String searchText,
    @Index() required String category,
    @Index() required int priceCents,
    @Index() required int stock,
    required int createdAtMicros,
    @Index(type: CindelIndexType.multiEntry, caseSensitive: false)
    @Default(<String>[])
    List<String> tags,
  }) = _Product;
}
