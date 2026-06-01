import 'package:cindel/cindel.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'product.freezed.dart';
part 'product.g.dart';

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
