// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'product.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$Product {

 Id get dbId;@Index(unique: true) String get sku;@Index() String get name; String get description;@Index(type: CindelIndexType.words, caseSensitive: false) String get searchText;@Index() String get category;@Index() int get priceCents;@Index() int get stock; int get createdAtMicros;@Index(type: CindelIndexType.multiEntry, caseSensitive: false) List<String> get tags;
/// Create a copy of Product
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProductCopyWith<Product> get copyWith => _$ProductCopyWithImpl<Product>(this as Product, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Product&&(identical(other.dbId, dbId) || other.dbId == dbId)&&(identical(other.sku, sku) || other.sku == sku)&&(identical(other.name, name) || other.name == name)&&(identical(other.description, description) || other.description == description)&&(identical(other.searchText, searchText) || other.searchText == searchText)&&(identical(other.category, category) || other.category == category)&&(identical(other.priceCents, priceCents) || other.priceCents == priceCents)&&(identical(other.stock, stock) || other.stock == stock)&&(identical(other.createdAtMicros, createdAtMicros) || other.createdAtMicros == createdAtMicros)&&const DeepCollectionEquality().equals(other.tags, tags));
}


@override
int get hashCode => Object.hash(runtimeType,dbId,sku,name,description,searchText,category,priceCents,stock,createdAtMicros,const DeepCollectionEquality().hash(tags));

@override
String toString() {
  return 'Product(dbId: $dbId, sku: $sku, name: $name, description: $description, searchText: $searchText, category: $category, priceCents: $priceCents, stock: $stock, createdAtMicros: $createdAtMicros, tags: $tags)';
}


}

/// @nodoc
abstract mixin class $ProductCopyWith<$Res>  {
  factory $ProductCopyWith(Product value, $Res Function(Product) _then) = _$ProductCopyWithImpl;
@useResult
$Res call({
 Id dbId,@Index(unique: true) String sku,@Index() String name, String description,@Index(type: CindelIndexType.words, caseSensitive: false) String searchText,@Index() String category,@Index() int priceCents,@Index() int stock, int createdAtMicros,@Index(type: CindelIndexType.multiEntry, caseSensitive: false) List<String> tags
});




}
/// @nodoc
class _$ProductCopyWithImpl<$Res>
    implements $ProductCopyWith<$Res> {
  _$ProductCopyWithImpl(this._self, this._then);

  final Product _self;
  final $Res Function(Product) _then;

/// Create a copy of Product
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? dbId = null,Object? sku = null,Object? name = null,Object? description = null,Object? searchText = null,Object? category = null,Object? priceCents = null,Object? stock = null,Object? createdAtMicros = null,Object? tags = null,}) {
  return _then(_self.copyWith(
dbId: null == dbId ? _self.dbId : dbId // ignore: cast_nullable_to_non_nullable
as Id,sku: null == sku ? _self.sku : sku // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,searchText: null == searchText ? _self.searchText : searchText // ignore: cast_nullable_to_non_nullable
as String,category: null == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as String,priceCents: null == priceCents ? _self.priceCents : priceCents // ignore: cast_nullable_to_non_nullable
as int,stock: null == stock ? _self.stock : stock // ignore: cast_nullable_to_non_nullable
as int,createdAtMicros: null == createdAtMicros ? _self.createdAtMicros : createdAtMicros // ignore: cast_nullable_to_non_nullable
as int,tags: null == tags ? _self.tags : tags // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}

}


/// Adds pattern-matching-related methods to [Product].
extension ProductPatterns on Product {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Product value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Product() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Product value)  $default,){
final _that = this;
switch (_that) {
case _Product():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Product value)?  $default,){
final _that = this;
switch (_that) {
case _Product() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( Id dbId, @Index(unique: true)  String sku, @Index()  String name,  String description, @Index(type: CindelIndexType.words, caseSensitive: false)  String searchText, @Index()  String category, @Index()  int priceCents, @Index()  int stock,  int createdAtMicros, @Index(type: CindelIndexType.multiEntry, caseSensitive: false)  List<String> tags)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Product() when $default != null:
return $default(_that.dbId,_that.sku,_that.name,_that.description,_that.searchText,_that.category,_that.priceCents,_that.stock,_that.createdAtMicros,_that.tags);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( Id dbId, @Index(unique: true)  String sku, @Index()  String name,  String description, @Index(type: CindelIndexType.words, caseSensitive: false)  String searchText, @Index()  String category, @Index()  int priceCents, @Index()  int stock,  int createdAtMicros, @Index(type: CindelIndexType.multiEntry, caseSensitive: false)  List<String> tags)  $default,) {final _that = this;
switch (_that) {
case _Product():
return $default(_that.dbId,_that.sku,_that.name,_that.description,_that.searchText,_that.category,_that.priceCents,_that.stock,_that.createdAtMicros,_that.tags);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( Id dbId, @Index(unique: true)  String sku, @Index()  String name,  String description, @Index(type: CindelIndexType.words, caseSensitive: false)  String searchText, @Index()  String category, @Index()  int priceCents, @Index()  int stock,  int createdAtMicros, @Index(type: CindelIndexType.multiEntry, caseSensitive: false)  List<String> tags)?  $default,) {final _that = this;
switch (_that) {
case _Product() when $default != null:
return $default(_that.dbId,_that.sku,_that.name,_that.description,_that.searchText,_that.category,_that.priceCents,_that.stock,_that.createdAtMicros,_that.tags);case _:
  return null;

}
}

}

/// @nodoc


class _Product implements Product {
  const _Product({required this.dbId, @Index(unique: true) required this.sku, @Index() required this.name, required this.description, @Index(type: CindelIndexType.words, caseSensitive: false) required this.searchText, @Index() required this.category, @Index() required this.priceCents, @Index() required this.stock, required this.createdAtMicros, @Index(type: CindelIndexType.multiEntry, caseSensitive: false) final  List<String> tags = const <String>[]}): _tags = tags;
  

@override final  Id dbId;
@override@Index(unique: true) final  String sku;
@override@Index() final  String name;
@override final  String description;
@override@Index(type: CindelIndexType.words, caseSensitive: false) final  String searchText;
@override@Index() final  String category;
@override@Index() final  int priceCents;
@override@Index() final  int stock;
@override final  int createdAtMicros;
 final  List<String> _tags;
@override@JsonKey()@Index(type: CindelIndexType.multiEntry, caseSensitive: false) List<String> get tags {
  if (_tags is EqualUnmodifiableListView) return _tags;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_tags);
}


/// Create a copy of Product
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ProductCopyWith<_Product> get copyWith => __$ProductCopyWithImpl<_Product>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Product&&(identical(other.dbId, dbId) || other.dbId == dbId)&&(identical(other.sku, sku) || other.sku == sku)&&(identical(other.name, name) || other.name == name)&&(identical(other.description, description) || other.description == description)&&(identical(other.searchText, searchText) || other.searchText == searchText)&&(identical(other.category, category) || other.category == category)&&(identical(other.priceCents, priceCents) || other.priceCents == priceCents)&&(identical(other.stock, stock) || other.stock == stock)&&(identical(other.createdAtMicros, createdAtMicros) || other.createdAtMicros == createdAtMicros)&&const DeepCollectionEquality().equals(other._tags, _tags));
}


@override
int get hashCode => Object.hash(runtimeType,dbId,sku,name,description,searchText,category,priceCents,stock,createdAtMicros,const DeepCollectionEquality().hash(_tags));

@override
String toString() {
  return 'Product(dbId: $dbId, sku: $sku, name: $name, description: $description, searchText: $searchText, category: $category, priceCents: $priceCents, stock: $stock, createdAtMicros: $createdAtMicros, tags: $tags)';
}


}

/// @nodoc
abstract mixin class _$ProductCopyWith<$Res> implements $ProductCopyWith<$Res> {
  factory _$ProductCopyWith(_Product value, $Res Function(_Product) _then) = __$ProductCopyWithImpl;
@override @useResult
$Res call({
 Id dbId,@Index(unique: true) String sku,@Index() String name, String description,@Index(type: CindelIndexType.words, caseSensitive: false) String searchText,@Index() String category,@Index() int priceCents,@Index() int stock, int createdAtMicros,@Index(type: CindelIndexType.multiEntry, caseSensitive: false) List<String> tags
});




}
/// @nodoc
class __$ProductCopyWithImpl<$Res>
    implements _$ProductCopyWith<$Res> {
  __$ProductCopyWithImpl(this._self, this._then);

  final _Product _self;
  final $Res Function(_Product) _then;

/// Create a copy of Product
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? dbId = null,Object? sku = null,Object? name = null,Object? description = null,Object? searchText = null,Object? category = null,Object? priceCents = null,Object? stock = null,Object? createdAtMicros = null,Object? tags = null,}) {
  return _then(_Product(
dbId: null == dbId ? _self.dbId : dbId // ignore: cast_nullable_to_non_nullable
as Id,sku: null == sku ? _self.sku : sku // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,searchText: null == searchText ? _self.searchText : searchText // ignore: cast_nullable_to_non_nullable
as String,category: null == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as String,priceCents: null == priceCents ? _self.priceCents : priceCents // ignore: cast_nullable_to_non_nullable
as int,stock: null == stock ? _self.stock : stock // ignore: cast_nullable_to_non_nullable
as int,createdAtMicros: null == createdAtMicros ? _self.createdAtMicros : createdAtMicros // ignore: cast_nullable_to_non_nullable
as int,tags: null == tags ? _self._tags : tags // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}


}

// dart format on
