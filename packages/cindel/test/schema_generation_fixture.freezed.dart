// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'schema_generation_fixture.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$FreezedPrimaryUser {

 Id get dbId; String get email;@Index(unique: true) String get username;@Enumerated(CindelEnumType.ordinal) UserStatus get status; bool get active;@ignore String? get transientNote;
/// Create a copy of FreezedPrimaryUser
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FreezedPrimaryUserCopyWith<FreezedPrimaryUser> get copyWith => _$FreezedPrimaryUserCopyWithImpl<FreezedPrimaryUser>(this as FreezedPrimaryUser, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FreezedPrimaryUser&&(identical(other.dbId, dbId) || other.dbId == dbId)&&(identical(other.email, email) || other.email == email)&&(identical(other.username, username) || other.username == username)&&(identical(other.status, status) || other.status == status)&&(identical(other.active, active) || other.active == active)&&(identical(other.transientNote, transientNote) || other.transientNote == transientNote));
}


@override
int get hashCode => Object.hash(runtimeType,dbId,email,username,status,active,transientNote);

@override
String toString() {
  return 'FreezedPrimaryUser(dbId: $dbId, email: $email, username: $username, status: $status, active: $active, transientNote: $transientNote)';
}


}

/// @nodoc
abstract mixin class $FreezedPrimaryUserCopyWith<$Res>  {
  factory $FreezedPrimaryUserCopyWith(FreezedPrimaryUser value, $Res Function(FreezedPrimaryUser) _then) = _$FreezedPrimaryUserCopyWithImpl;
@useResult
$Res call({
 Id dbId, String email,@Index(unique: true) String username,@Enumerated(CindelEnumType.ordinal) UserStatus status, bool active,@ignore String? transientNote
});




}
/// @nodoc
class _$FreezedPrimaryUserCopyWithImpl<$Res>
    implements $FreezedPrimaryUserCopyWith<$Res> {
  _$FreezedPrimaryUserCopyWithImpl(this._self, this._then);

  final FreezedPrimaryUser _self;
  final $Res Function(FreezedPrimaryUser) _then;

/// Create a copy of FreezedPrimaryUser
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? dbId = null,Object? email = null,Object? username = null,Object? status = null,Object? active = null,Object? transientNote = freezed,}) {
  return _then(_self.copyWith(
dbId: null == dbId ? _self.dbId : dbId // ignore: cast_nullable_to_non_nullable
as Id,email: null == email ? _self.email : email // ignore: cast_nullable_to_non_nullable
as String,username: null == username ? _self.username : username // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as UserStatus,active: null == active ? _self.active : active // ignore: cast_nullable_to_non_nullable
as bool,transientNote: freezed == transientNote ? _self.transientNote : transientNote // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [FreezedPrimaryUser].
extension FreezedPrimaryUserPatterns on FreezedPrimaryUser {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _FreezedPrimaryUser value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _FreezedPrimaryUser() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _FreezedPrimaryUser value)  $default,){
final _that = this;
switch (_that) {
case _FreezedPrimaryUser():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _FreezedPrimaryUser value)?  $default,){
final _that = this;
switch (_that) {
case _FreezedPrimaryUser() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( Id dbId,  String email, @Index(unique: true)  String username, @Enumerated(CindelEnumType.ordinal)  UserStatus status,  bool active, @ignore  String? transientNote)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _FreezedPrimaryUser() when $default != null:
return $default(_that.dbId,_that.email,_that.username,_that.status,_that.active,_that.transientNote);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( Id dbId,  String email, @Index(unique: true)  String username, @Enumerated(CindelEnumType.ordinal)  UserStatus status,  bool active, @ignore  String? transientNote)  $default,) {final _that = this;
switch (_that) {
case _FreezedPrimaryUser():
return $default(_that.dbId,_that.email,_that.username,_that.status,_that.active,_that.transientNote);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( Id dbId,  String email, @Index(unique: true)  String username, @Enumerated(CindelEnumType.ordinal)  UserStatus status,  bool active, @ignore  String? transientNote)?  $default,) {final _that = this;
switch (_that) {
case _FreezedPrimaryUser() when $default != null:
return $default(_that.dbId,_that.email,_that.username,_that.status,_that.active,_that.transientNote);case _:
  return null;

}
}

}

/// @nodoc


class _FreezedPrimaryUser implements FreezedPrimaryUser {
  const _FreezedPrimaryUser({required this.dbId, required this.email, @Index(unique: true) required this.username, @Enumerated(CindelEnumType.ordinal) required this.status, this.active = true, @ignore this.transientNote});
  

@override final  Id dbId;
@override final  String email;
@override@Index(unique: true) final  String username;
@override@Enumerated(CindelEnumType.ordinal) final  UserStatus status;
@override@JsonKey() final  bool active;
@override@ignore final  String? transientNote;

/// Create a copy of FreezedPrimaryUser
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$FreezedPrimaryUserCopyWith<_FreezedPrimaryUser> get copyWith => __$FreezedPrimaryUserCopyWithImpl<_FreezedPrimaryUser>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _FreezedPrimaryUser&&(identical(other.dbId, dbId) || other.dbId == dbId)&&(identical(other.email, email) || other.email == email)&&(identical(other.username, username) || other.username == username)&&(identical(other.status, status) || other.status == status)&&(identical(other.active, active) || other.active == active)&&(identical(other.transientNote, transientNote) || other.transientNote == transientNote));
}


@override
int get hashCode => Object.hash(runtimeType,dbId,email,username,status,active,transientNote);

@override
String toString() {
  return 'FreezedPrimaryUser(dbId: $dbId, email: $email, username: $username, status: $status, active: $active, transientNote: $transientNote)';
}


}

/// @nodoc
abstract mixin class _$FreezedPrimaryUserCopyWith<$Res> implements $FreezedPrimaryUserCopyWith<$Res> {
  factory _$FreezedPrimaryUserCopyWith(_FreezedPrimaryUser value, $Res Function(_FreezedPrimaryUser) _then) = __$FreezedPrimaryUserCopyWithImpl;
@override @useResult
$Res call({
 Id dbId, String email,@Index(unique: true) String username,@Enumerated(CindelEnumType.ordinal) UserStatus status, bool active,@ignore String? transientNote
});




}
/// @nodoc
class __$FreezedPrimaryUserCopyWithImpl<$Res>
    implements _$FreezedPrimaryUserCopyWith<$Res> {
  __$FreezedPrimaryUserCopyWithImpl(this._self, this._then);

  final _FreezedPrimaryUser _self;
  final $Res Function(_FreezedPrimaryUser) _then;

/// Create a copy of FreezedPrimaryUser
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? dbId = null,Object? email = null,Object? username = null,Object? status = null,Object? active = null,Object? transientNote = freezed,}) {
  return _then(_FreezedPrimaryUser(
dbId: null == dbId ? _self.dbId : dbId // ignore: cast_nullable_to_non_nullable
as Id,email: null == email ? _self.email : email // ignore: cast_nullable_to_non_nullable
as String,username: null == username ? _self.username : username // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as UserStatus,active: null == active ? _self.active : active // ignore: cast_nullable_to_non_nullable
as bool,transientNote: freezed == transientNote ? _self.transientNote : transientNote // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
