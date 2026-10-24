import 'package:cindel/cindel.dart';

part 'type_compatibility_fixture.g.dart';

enum ProbeEnum { first, second }

enum ProbeStringEnum {
  first('uno'),
  second('dos');

  const ProbeStringEnum(this.code);
  final String code;
}

enum ProbeintEnum {
  first(11),
  second(22);

  const ProbeintEnum(this.code);
  final int code;
}

enum ProbedoubleEnum {
  first(1.5),
  second(2.5);

  const ProbedoubleEnum(this.code);
  final double code;
}

enum ProbeboolEnum {
  first(false),
  second(true);

  const ProbeboolEnum(this.code);
  final bool code;
}

@embedded
class ProbeLeaf {
  String? label;
}

@Collection(name: 'c00')
class Modelc00 {
  Id dbId = autoIncrement;

  late bool value;
}

@embedded
class Payloadc00 {
  late bool value;
}

@Collection(name: 'c00_envelope')
class Envelopec00 {
  Id dbId = autoIncrement;
  late Payloadc00 value;
}

@Collection(name: 'c01')
class Modelc01 {
  Id dbId = autoIncrement;

  late bool? value;
}

@embedded
class Payloadc01 {
  late bool? value;
}

@Collection(name: 'c01_envelope')
class Envelopec01 {
  Id dbId = autoIncrement;
  late Payloadc01 value;
}

@Collection(name: 'c02')
class Modelc02 {
  Id dbId = autoIncrement;

  late List<bool> value;
}

@embedded
class Payloadc02 {
  late List<bool> value;
}

@Collection(name: 'c02_envelope')
class Envelopec02 {
  Id dbId = autoIncrement;
  late Payloadc02 value;
}

@Collection(name: 'c03')
class Modelc03 {
  Id dbId = autoIncrement;

  late List<bool?> value;
}

@embedded
class Payloadc03 {
  late List<bool?> value;
}

@Collection(name: 'c03_envelope')
class Envelopec03 {
  Id dbId = autoIncrement;
  late Payloadc03 value;
}

@Collection(name: 'c04')
class Modelc04 {
  Id dbId = autoIncrement;

  late List<bool>? value;
}

@embedded
class Payloadc04 {
  late List<bool>? value;
}

@Collection(name: 'c04_envelope')
class Envelopec04 {
  Id dbId = autoIncrement;
  late Payloadc04 value;
}

@Collection(name: 'c05')
class Modelc05 {
  Id dbId = autoIncrement;

  late List<bool?>? value;
}

@embedded
class Payloadc05 {
  late List<bool?>? value;
}

@Collection(name: 'c05_envelope')
class Envelopec05 {
  Id dbId = autoIncrement;
  late Payloadc05 value;
}

@Collection(name: 'c06')
class Modelc06 {
  Id dbId = autoIncrement;

  late int value;
}

@embedded
class Payloadc06 {
  late int value;
}

@Collection(name: 'c06_envelope')
class Envelopec06 {
  Id dbId = autoIncrement;
  late Payloadc06 value;
}

@Collection(name: 'c07')
class Modelc07 {
  Id dbId = autoIncrement;

  late int? value;
}

@embedded
class Payloadc07 {
  late int? value;
}

@Collection(name: 'c07_envelope')
class Envelopec07 {
  Id dbId = autoIncrement;
  late Payloadc07 value;
}

@Collection(name: 'c08')
class Modelc08 {
  Id dbId = autoIncrement;

  late List<int> value;
}

@embedded
class Payloadc08 {
  late List<int> value;
}

@Collection(name: 'c08_envelope')
class Envelopec08 {
  Id dbId = autoIncrement;
  late Payloadc08 value;
}

@Collection(name: 'c09')
class Modelc09 {
  Id dbId = autoIncrement;

  late List<int?> value;
}

@embedded
class Payloadc09 {
  late List<int?> value;
}

@Collection(name: 'c09_envelope')
class Envelopec09 {
  Id dbId = autoIncrement;
  late Payloadc09 value;
}

@Collection(name: 'c10')
class Modelc10 {
  Id dbId = autoIncrement;

  late List<int>? value;
}

@embedded
class Payloadc10 {
  late List<int>? value;
}

@Collection(name: 'c10_envelope')
class Envelopec10 {
  Id dbId = autoIncrement;
  late Payloadc10 value;
}

@Collection(name: 'c11')
class Modelc11 {
  Id dbId = autoIncrement;

  late List<int?>? value;
}

@embedded
class Payloadc11 {
  late List<int?>? value;
}

@Collection(name: 'c11_envelope')
class Envelopec11 {
  Id dbId = autoIncrement;
  late Payloadc11 value;
}

@Collection(name: 'c12')
class Modelc12 {
  Id dbId = autoIncrement;

  late double value;
}

@embedded
class Payloadc12 {
  late double value;
}

@Collection(name: 'c12_envelope')
class Envelopec12 {
  Id dbId = autoIncrement;
  late Payloadc12 value;
}

@Collection(name: 'c13')
class Modelc13 {
  Id dbId = autoIncrement;

  late double? value;
}

@embedded
class Payloadc13 {
  late double? value;
}

@Collection(name: 'c13_envelope')
class Envelopec13 {
  Id dbId = autoIncrement;
  late Payloadc13 value;
}

@Collection(name: 'c14')
class Modelc14 {
  Id dbId = autoIncrement;

  late List<double> value;
}

@embedded
class Payloadc14 {
  late List<double> value;
}

@Collection(name: 'c14_envelope')
class Envelopec14 {
  Id dbId = autoIncrement;
  late Payloadc14 value;
}

@Collection(name: 'c15')
class Modelc15 {
  Id dbId = autoIncrement;

  late List<double?> value;
}

@embedded
class Payloadc15 {
  late List<double?> value;
}

@Collection(name: 'c15_envelope')
class Envelopec15 {
  Id dbId = autoIncrement;
  late Payloadc15 value;
}

@Collection(name: 'c16')
class Modelc16 {
  Id dbId = autoIncrement;

  late List<double>? value;
}

@embedded
class Payloadc16 {
  late List<double>? value;
}

@Collection(name: 'c16_envelope')
class Envelopec16 {
  Id dbId = autoIncrement;
  late Payloadc16 value;
}

@Collection(name: 'c17')
class Modelc17 {
  Id dbId = autoIncrement;

  late List<double?>? value;
}

@embedded
class Payloadc17 {
  late List<double?>? value;
}

@Collection(name: 'c17_envelope')
class Envelopec17 {
  Id dbId = autoIncrement;
  late Payloadc17 value;
}

@Collection(name: 'c18')
class Modelc18 {
  Id dbId = autoIncrement;

  late String value;
}

@embedded
class Payloadc18 {
  late String value;
}

@Collection(name: 'c18_envelope')
class Envelopec18 {
  Id dbId = autoIncrement;
  late Payloadc18 value;
}

@Collection(name: 'c19')
class Modelc19 {
  Id dbId = autoIncrement;

  late String? value;
}

@embedded
class Payloadc19 {
  late String? value;
}

@Collection(name: 'c19_envelope')
class Envelopec19 {
  Id dbId = autoIncrement;
  late Payloadc19 value;
}

@Collection(name: 'c20')
class Modelc20 {
  Id dbId = autoIncrement;

  late List<String> value;
}

@embedded
class Payloadc20 {
  late List<String> value;
}

@Collection(name: 'c20_envelope')
class Envelopec20 {
  Id dbId = autoIncrement;
  late Payloadc20 value;
}

@Collection(name: 'c21')
class Modelc21 {
  Id dbId = autoIncrement;

  late List<String?> value;
}

@embedded
class Payloadc21 {
  late List<String?> value;
}

@Collection(name: 'c21_envelope')
class Envelopec21 {
  Id dbId = autoIncrement;
  late Payloadc21 value;
}

@Collection(name: 'c22')
class Modelc22 {
  Id dbId = autoIncrement;

  late List<String>? value;
}

@embedded
class Payloadc22 {
  late List<String>? value;
}

@Collection(name: 'c22_envelope')
class Envelopec22 {
  Id dbId = autoIncrement;
  late Payloadc22 value;
}

@Collection(name: 'c23')
class Modelc23 {
  Id dbId = autoIncrement;

  late List<String?>? value;
}

@embedded
class Payloadc23 {
  late List<String?>? value;
}

@Collection(name: 'c23_envelope')
class Envelopec23 {
  Id dbId = autoIncrement;
  late Payloadc23 value;
}

@Collection(name: 'c24')
class Modelc24 {
  Id dbId = autoIncrement;

  late DateTime value;
}

@embedded
class Payloadc24 {
  late DateTime value;
}

@Collection(name: 'c24_envelope')
class Envelopec24 {
  Id dbId = autoIncrement;
  late Payloadc24 value;
}

@Collection(name: 'c25')
class Modelc25 {
  Id dbId = autoIncrement;

  late DateTime? value;
}

@embedded
class Payloadc25 {
  late DateTime? value;
}

@Collection(name: 'c25_envelope')
class Envelopec25 {
  Id dbId = autoIncrement;
  late Payloadc25 value;
}

@Collection(name: 'c26')
class Modelc26 {
  Id dbId = autoIncrement;

  late List<DateTime> value;
}

@embedded
class Payloadc26 {
  late List<DateTime> value;
}

@Collection(name: 'c26_envelope')
class Envelopec26 {
  Id dbId = autoIncrement;
  late Payloadc26 value;
}

@Collection(name: 'c27')
class Modelc27 {
  Id dbId = autoIncrement;

  late List<DateTime?> value;
}

@embedded
class Payloadc27 {
  late List<DateTime?> value;
}

@Collection(name: 'c27_envelope')
class Envelopec27 {
  Id dbId = autoIncrement;
  late Payloadc27 value;
}

@Collection(name: 'c28')
class Modelc28 {
  Id dbId = autoIncrement;

  late List<DateTime>? value;
}

@embedded
class Payloadc28 {
  late List<DateTime>? value;
}

@Collection(name: 'c28_envelope')
class Envelopec28 {
  Id dbId = autoIncrement;
  late Payloadc28 value;
}

@Collection(name: 'c29')
class Modelc29 {
  Id dbId = autoIncrement;

  late List<DateTime?>? value;
}

@embedded
class Payloadc29 {
  late List<DateTime?>? value;
}

@Collection(name: 'c29_envelope')
class Envelopec29 {
  Id dbId = autoIncrement;
  late Payloadc29 value;
}

@Collection(name: 'c30')
class Modelc30 {
  Id dbId = autoIncrement;

  late Duration value;
}

@embedded
class Payloadc30 {
  late Duration value;
}

@Collection(name: 'c30_envelope')
class Envelopec30 {
  Id dbId = autoIncrement;
  late Payloadc30 value;
}

@Collection(name: 'c31')
class Modelc31 {
  Id dbId = autoIncrement;

  late Duration? value;
}

@embedded
class Payloadc31 {
  late Duration? value;
}

@Collection(name: 'c31_envelope')
class Envelopec31 {
  Id dbId = autoIncrement;
  late Payloadc31 value;
}

@Collection(name: 'c32')
class Modelc32 {
  Id dbId = autoIncrement;

  late List<Duration> value;
}

@embedded
class Payloadc32 {
  late List<Duration> value;
}

@Collection(name: 'c32_envelope')
class Envelopec32 {
  Id dbId = autoIncrement;
  late Payloadc32 value;
}

@Collection(name: 'c33')
class Modelc33 {
  Id dbId = autoIncrement;

  late List<Duration?> value;
}

@embedded
class Payloadc33 {
  late List<Duration?> value;
}

@Collection(name: 'c33_envelope')
class Envelopec33 {
  Id dbId = autoIncrement;
  late Payloadc33 value;
}

@Collection(name: 'c34')
class Modelc34 {
  Id dbId = autoIncrement;

  late List<Duration>? value;
}

@embedded
class Payloadc34 {
  late List<Duration>? value;
}

@Collection(name: 'c34_envelope')
class Envelopec34 {
  Id dbId = autoIncrement;
  late Payloadc34 value;
}

@Collection(name: 'c35')
class Modelc35 {
  Id dbId = autoIncrement;

  late List<Duration?>? value;
}

@embedded
class Payloadc35 {
  late List<Duration?>? value;
}

@Collection(name: 'c35_envelope')
class Envelopec35 {
  Id dbId = autoIncrement;
  late Payloadc35 value;
}

@Collection(name: 'c36')
class Modelc36 {
  Id dbId = autoIncrement;

  late ProbeEnum value;
}

@embedded
class Payloadc36 {
  late ProbeEnum value;
}

@Collection(name: 'c36_envelope')
class Envelopec36 {
  Id dbId = autoIncrement;
  late Payloadc36 value;
}

@Collection(name: 'c37')
class Modelc37 {
  Id dbId = autoIncrement;

  late ProbeEnum? value;
}

@embedded
class Payloadc37 {
  late ProbeEnum? value;
}

@Collection(name: 'c37_envelope')
class Envelopec37 {
  Id dbId = autoIncrement;
  late Payloadc37 value;
}

@Collection(name: 'c38')
class Modelc38 {
  Id dbId = autoIncrement;

  late List<ProbeEnum> value;
}

@embedded
class Payloadc38 {
  late List<ProbeEnum> value;
}

@Collection(name: 'c38_envelope')
class Envelopec38 {
  Id dbId = autoIncrement;
  late Payloadc38 value;
}

@Collection(name: 'c39')
class Modelc39 {
  Id dbId = autoIncrement;

  late List<ProbeEnum?> value;
}

@embedded
class Payloadc39 {
  late List<ProbeEnum?> value;
}

@Collection(name: 'c39_envelope')
class Envelopec39 {
  Id dbId = autoIncrement;
  late Payloadc39 value;
}

@Collection(name: 'c40')
class Modelc40 {
  Id dbId = autoIncrement;

  late List<ProbeEnum>? value;
}

@embedded
class Payloadc40 {
  late List<ProbeEnum>? value;
}

@Collection(name: 'c40_envelope')
class Envelopec40 {
  Id dbId = autoIncrement;
  late Payloadc40 value;
}

@Collection(name: 'c41')
class Modelc41 {
  Id dbId = autoIncrement;

  late List<ProbeEnum?>? value;
}

@embedded
class Payloadc41 {
  late List<ProbeEnum?>? value;
}

@Collection(name: 'c41_envelope')
class Envelopec41 {
  Id dbId = autoIncrement;
  late Payloadc41 value;
}

@Collection(name: 'c42')
class Modelc42 {
  Id dbId = autoIncrement;
  @Enumerated(CindelEnumType.ordinal)
  late ProbeEnum value;
}

@embedded
class Payloadc42 {
  @Enumerated(CindelEnumType.ordinal)
  late ProbeEnum value;
}

@Collection(name: 'c42_envelope')
class Envelopec42 {
  Id dbId = autoIncrement;
  late Payloadc42 value;
}

@Collection(name: 'c43')
class Modelc43 {
  Id dbId = autoIncrement;
  @Enumerated(CindelEnumType.ordinal)
  late ProbeEnum? value;
}

@embedded
class Payloadc43 {
  @Enumerated(CindelEnumType.ordinal)
  late ProbeEnum? value;
}

@Collection(name: 'c43_envelope')
class Envelopec43 {
  Id dbId = autoIncrement;
  late Payloadc43 value;
}

@Collection(name: 'c44')
class Modelc44 {
  Id dbId = autoIncrement;
  @Enumerated(CindelEnumType.value, valueField: 'code')
  late ProbeStringEnum value;
}

@embedded
class Payloadc44 {
  @Enumerated(CindelEnumType.value, valueField: 'code')
  late ProbeStringEnum value;
}

@Collection(name: 'c44_envelope')
class Envelopec44 {
  Id dbId = autoIncrement;
  late Payloadc44 value;
}

@Collection(name: 'c45')
class Modelc45 {
  Id dbId = autoIncrement;
  @Enumerated(CindelEnumType.value, valueField: 'code')
  late ProbeStringEnum? value;
}

@embedded
class Payloadc45 {
  @Enumerated(CindelEnumType.value, valueField: 'code')
  late ProbeStringEnum? value;
}

@Collection(name: 'c45_envelope')
class Envelopec45 {
  Id dbId = autoIncrement;
  late Payloadc45 value;
}

@Collection(name: 'c46')
class Modelc46 {
  Id dbId = autoIncrement;
  @Enumerated(CindelEnumType.value, valueField: 'code')
  late ProbeintEnum value;
}

@embedded
class Payloadc46 {
  @Enumerated(CindelEnumType.value, valueField: 'code')
  late ProbeintEnum value;
}

@Collection(name: 'c46_envelope')
class Envelopec46 {
  Id dbId = autoIncrement;
  late Payloadc46 value;
}

@Collection(name: 'c47')
class Modelc47 {
  Id dbId = autoIncrement;
  @Enumerated(CindelEnumType.value, valueField: 'code')
  late ProbeintEnum? value;
}

@embedded
class Payloadc47 {
  @Enumerated(CindelEnumType.value, valueField: 'code')
  late ProbeintEnum? value;
}

@Collection(name: 'c47_envelope')
class Envelopec47 {
  Id dbId = autoIncrement;
  late Payloadc47 value;
}

@Collection(name: 'c48')
class Modelc48 {
  Id dbId = autoIncrement;
  @Enumerated(CindelEnumType.value, valueField: 'code')
  late ProbedoubleEnum value;
}

@embedded
class Payloadc48 {
  @Enumerated(CindelEnumType.value, valueField: 'code')
  late ProbedoubleEnum value;
}

@Collection(name: 'c48_envelope')
class Envelopec48 {
  Id dbId = autoIncrement;
  late Payloadc48 value;
}

@Collection(name: 'c49')
class Modelc49 {
  Id dbId = autoIncrement;
  @Enumerated(CindelEnumType.value, valueField: 'code')
  late ProbedoubleEnum? value;
}

@embedded
class Payloadc49 {
  @Enumerated(CindelEnumType.value, valueField: 'code')
  late ProbedoubleEnum? value;
}

@Collection(name: 'c49_envelope')
class Envelopec49 {
  Id dbId = autoIncrement;
  late Payloadc49 value;
}

@Collection(name: 'c50')
class Modelc50 {
  Id dbId = autoIncrement;
  @Enumerated(CindelEnumType.value, valueField: 'code')
  late ProbeboolEnum value;
}

@embedded
class Payloadc50 {
  @Enumerated(CindelEnumType.value, valueField: 'code')
  late ProbeboolEnum value;
}

@Collection(name: 'c50_envelope')
class Envelopec50 {
  Id dbId = autoIncrement;
  late Payloadc50 value;
}

@Collection(name: 'c51')
class Modelc51 {
  Id dbId = autoIncrement;
  @Enumerated(CindelEnumType.value, valueField: 'code')
  late ProbeboolEnum? value;
}

@embedded
class Payloadc51 {
  @Enumerated(CindelEnumType.value, valueField: 'code')
  late ProbeboolEnum? value;
}

@Collection(name: 'c51_envelope')
class Envelopec51 {
  Id dbId = autoIncrement;
  late Payloadc51 value;
}

@Collection(name: 'c52')
class Modelc52 {
  Id dbId = autoIncrement;

  late ProbeLeaf value;
}

@embedded
class Payloadc52 {
  late ProbeLeaf value;
}

@Collection(name: 'c52_envelope')
class Envelopec52 {
  Id dbId = autoIncrement;
  late Payloadc52 value;
}

@Collection(name: 'c53')
class Modelc53 {
  Id dbId = autoIncrement;

  late ProbeLeaf? value;
}

@embedded
class Payloadc53 {
  late ProbeLeaf? value;
}

@Collection(name: 'c53_envelope')
class Envelopec53 {
  Id dbId = autoIncrement;
  late Payloadc53 value;
}

@Collection(name: 'c54')
class Modelc54 {
  Id dbId = autoIncrement;

  late List<ProbeLeaf> value;
}

@embedded
class Payloadc54 {
  late List<ProbeLeaf> value;
}

@Collection(name: 'c54_envelope')
class Envelopec54 {
  Id dbId = autoIncrement;
  late Payloadc54 value;
}

@Collection(name: 'c55')
class Modelc55 {
  Id dbId = autoIncrement;

  late List<ProbeLeaf?> value;
}

@embedded
class Payloadc55 {
  late List<ProbeLeaf?> value;
}

@Collection(name: 'c55_envelope')
class Envelopec55 {
  Id dbId = autoIncrement;
  late Payloadc55 value;
}

@Collection(name: 'c56')
class Modelc56 {
  Id dbId = autoIncrement;

  late List<ProbeLeaf>? value;
}

@embedded
class Payloadc56 {
  late List<ProbeLeaf>? value;
}

@Collection(name: 'c56_envelope')
class Envelopec56 {
  Id dbId = autoIncrement;
  late Payloadc56 value;
}

@Collection(name: 'c57')
class Modelc57 {
  Id dbId = autoIncrement;

  late List<ProbeLeaf?>? value;
}

@embedded
class Payloadc57 {
  late List<ProbeLeaf?>? value;
}

@Collection(name: 'c57_envelope')
class Envelopec57 {
  Id dbId = autoIncrement;
  late Payloadc57 value;
}

@collection
class ListAfterScalar {
  Id dbId = autoIncrement;
  int anchor = 1;
  List<String?> value = const [];
}

@collection
class ListBeforeScalar {
  Id dbId = autoIncrement;
  List<String?> value = const [];
  int zAnchor = 1;
}
