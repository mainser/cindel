// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'catalog_query.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$CatalogQuery {

 String get searchText; String get category; bool get inStockOnly; CatalogSort get sort;
/// Create a copy of CatalogQuery
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CatalogQueryCopyWith<CatalogQuery> get copyWith => _$CatalogQueryCopyWithImpl<CatalogQuery>(this as CatalogQuery, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CatalogQuery&&(identical(other.searchText, searchText) || other.searchText == searchText)&&(identical(other.category, category) || other.category == category)&&(identical(other.inStockOnly, inStockOnly) || other.inStockOnly == inStockOnly)&&(identical(other.sort, sort) || other.sort == sort));
}


@override
int get hashCode => Object.hash(runtimeType,searchText,category,inStockOnly,sort);

@override
String toString() {
  return 'CatalogQuery(searchText: $searchText, category: $category, inStockOnly: $inStockOnly, sort: $sort)';
}


}

/// @nodoc
abstract mixin class $CatalogQueryCopyWith<$Res>  {
  factory $CatalogQueryCopyWith(CatalogQuery value, $Res Function(CatalogQuery) _then) = _$CatalogQueryCopyWithImpl;
@useResult
$Res call({
 String searchText, String category, bool inStockOnly, CatalogSort sort
});




}
/// @nodoc
class _$CatalogQueryCopyWithImpl<$Res>
    implements $CatalogQueryCopyWith<$Res> {
  _$CatalogQueryCopyWithImpl(this._self, this._then);

  final CatalogQuery _self;
  final $Res Function(CatalogQuery) _then;

/// Create a copy of CatalogQuery
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? searchText = null,Object? category = null,Object? inStockOnly = null,Object? sort = null,}) {
  return _then(_self.copyWith(
searchText: null == searchText ? _self.searchText : searchText // ignore: cast_nullable_to_non_nullable
as String,category: null == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as String,inStockOnly: null == inStockOnly ? _self.inStockOnly : inStockOnly // ignore: cast_nullable_to_non_nullable
as bool,sort: null == sort ? _self.sort : sort // ignore: cast_nullable_to_non_nullable
as CatalogSort,
  ));
}

}


/// Adds pattern-matching-related methods to [CatalogQuery].
extension CatalogQueryPatterns on CatalogQuery {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _CatalogQuery value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _CatalogQuery() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _CatalogQuery value)  $default,){
final _that = this;
switch (_that) {
case _CatalogQuery():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _CatalogQuery value)?  $default,){
final _that = this;
switch (_that) {
case _CatalogQuery() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String searchText,  String category,  bool inStockOnly,  CatalogSort sort)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _CatalogQuery() when $default != null:
return $default(_that.searchText,_that.category,_that.inStockOnly,_that.sort);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String searchText,  String category,  bool inStockOnly,  CatalogSort sort)  $default,) {final _that = this;
switch (_that) {
case _CatalogQuery():
return $default(_that.searchText,_that.category,_that.inStockOnly,_that.sort);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String searchText,  String category,  bool inStockOnly,  CatalogSort sort)?  $default,) {final _that = this;
switch (_that) {
case _CatalogQuery() when $default != null:
return $default(_that.searchText,_that.category,_that.inStockOnly,_that.sort);case _:
  return null;

}
}

}

/// @nodoc


class _CatalogQuery implements CatalogQuery {
  const _CatalogQuery({this.searchText = '', this.category = 'All', this.inStockOnly = false, this.sort = CatalogSort.newest});
  

@override@JsonKey() final  String searchText;
@override@JsonKey() final  String category;
@override@JsonKey() final  bool inStockOnly;
@override@JsonKey() final  CatalogSort sort;

/// Create a copy of CatalogQuery
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$CatalogQueryCopyWith<_CatalogQuery> get copyWith => __$CatalogQueryCopyWithImpl<_CatalogQuery>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _CatalogQuery&&(identical(other.searchText, searchText) || other.searchText == searchText)&&(identical(other.category, category) || other.category == category)&&(identical(other.inStockOnly, inStockOnly) || other.inStockOnly == inStockOnly)&&(identical(other.sort, sort) || other.sort == sort));
}


@override
int get hashCode => Object.hash(runtimeType,searchText,category,inStockOnly,sort);

@override
String toString() {
  return 'CatalogQuery(searchText: $searchText, category: $category, inStockOnly: $inStockOnly, sort: $sort)';
}


}

/// @nodoc
abstract mixin class _$CatalogQueryCopyWith<$Res> implements $CatalogQueryCopyWith<$Res> {
  factory _$CatalogQueryCopyWith(_CatalogQuery value, $Res Function(_CatalogQuery) _then) = __$CatalogQueryCopyWithImpl;
@override @useResult
$Res call({
 String searchText, String category, bool inStockOnly, CatalogSort sort
});




}
/// @nodoc
class __$CatalogQueryCopyWithImpl<$Res>
    implements _$CatalogQueryCopyWith<$Res> {
  __$CatalogQueryCopyWithImpl(this._self, this._then);

  final _CatalogQuery _self;
  final $Res Function(_CatalogQuery) _then;

/// Create a copy of CatalogQuery
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? searchText = null,Object? category = null,Object? inStockOnly = null,Object? sort = null,}) {
  return _then(_CatalogQuery(
searchText: null == searchText ? _self.searchText : searchText // ignore: cast_nullable_to_non_nullable
as String,category: null == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as String,inStockOnly: null == inStockOnly ? _self.inStockOnly : inStockOnly // ignore: cast_nullable_to_non_nullable
as bool,sort: null == sort ? _self.sort : sort // ignore: cast_nullable_to_non_nullable
as CatalogSort,
  ));
}


}

// dart format on
