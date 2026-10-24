import 'package:cindel/cindel.dart';
import 'package:test/test.dart';

import 'close_test_support_io.dart'
    if (dart.library.js_interop) 'close_test_support_web.dart';
import 'type_compatibility_fixture.dart';

void runTypeCompatibility(CindelStorageBackend backend) {
  _runControls(backend);
  _register<Modelc00>(
    backend,
    'c00',
    'bool',
    'root',
    Modelc00Schema,
    () => [
      (Modelc00()
        ..dbId = 1
        ..value = (true)),
      (Modelc00()
        ..dbId = 2
        ..value = (false)),
    ],
    (object) => object.value,
    (collection) => Modelc00CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => value,
  );
  _register<Envelopec00>(
    backend,
    'c00',
    'bool',
    'nested',
    Envelopec00Schema,
    () => [
      (Envelopec00()
        ..dbId = 1
        ..value = (Payloadc00()..value = (true))),
      (Envelopec00()
        ..dbId = 2
        ..value = (Payloadc00()..value = (false))),
    ],
    (object) => object.value.value,
    (collection) => Envelopec00CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => (value as Payloadc00).value,
  );
  _register<Modelc01>(
    backend,
    'c01',
    'bool?',
    'root',
    Modelc01Schema,
    () => [
      (Modelc01()
        ..dbId = 1
        ..value = (true)),
      (Modelc01()
        ..dbId = 2
        ..value = (false)),
      (Modelc01()
        ..dbId = 3
        ..value = (null)),
    ],
    (object) => object.value,
    (collection) => Modelc01CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => value,
  );
  _register<Envelopec01>(
    backend,
    'c01',
    'bool?',
    'nested',
    Envelopec01Schema,
    () => [
      (Envelopec01()
        ..dbId = 1
        ..value = (Payloadc01()..value = (true))),
      (Envelopec01()
        ..dbId = 2
        ..value = (Payloadc01()..value = (false))),
      (Envelopec01()
        ..dbId = 3
        ..value = (Payloadc01()..value = (null))),
    ],
    (object) => object.value.value,
    (collection) => Envelopec01CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => (value as Payloadc01).value,
  );
  _register<Modelc02>(
    backend,
    'c02',
    'List<bool>',
    'root',
    Modelc02Schema,
    () => [
      (Modelc02()
        ..dbId = 1
        ..value = (<bool>[(true), (false)])),
      (Modelc02()
        ..dbId = 2
        ..value = (<bool>[])),
    ],
    (object) => object.value,
    (collection) => Modelc02CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => value,
  );
  _register<Envelopec02>(
    backend,
    'c02',
    'List<bool>',
    'nested',
    Envelopec02Schema,
    () => [
      (Envelopec02()
        ..dbId = 1
        ..value = (Payloadc02()..value = (<bool>[(true), (false)]))),
      (Envelopec02()
        ..dbId = 2
        ..value = (Payloadc02()..value = (<bool>[]))),
    ],
    (object) => object.value.value,
    (collection) => Envelopec02CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => (value as Payloadc02).value,
  );
  _register<Modelc03>(
    backend,
    'c03',
    'List<bool?>',
    'root',
    Modelc03Schema,
    () => [
      (Modelc03()
        ..dbId = 1
        ..value = (<bool?>[(true), (false), null])),
      (Modelc03()
        ..dbId = 2
        ..value = (<bool?>[])),
      (Modelc03()
        ..dbId = 3
        ..value = (<bool?>[null, null])),
    ],
    (object) => object.value,
    (collection) => Modelc03CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => value,
  );
  _register<Envelopec03>(
    backend,
    'c03',
    'List<bool?>',
    'nested',
    Envelopec03Schema,
    () => [
      (Envelopec03()
        ..dbId = 1
        ..value = (Payloadc03()..value = (<bool?>[(true), (false), null]))),
      (Envelopec03()
        ..dbId = 2
        ..value = (Payloadc03()..value = (<bool?>[]))),
      (Envelopec03()
        ..dbId = 3
        ..value = (Payloadc03()..value = (<bool?>[null, null]))),
    ],
    (object) => object.value.value,
    (collection) => Envelopec03CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => (value as Payloadc03).value,
  );
  _register<Modelc04>(
    backend,
    'c04',
    'List<bool>?',
    'root',
    Modelc04Schema,
    () => [
      (Modelc04()
        ..dbId = 1
        ..value = (<bool>[(true), (false)])),
      (Modelc04()
        ..dbId = 2
        ..value = (<bool>[])),
      (Modelc04()
        ..dbId = 3
        ..value = (null)),
    ],
    (object) => object.value,
    (collection) => Modelc04CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => value,
  );
  _register<Envelopec04>(
    backend,
    'c04',
    'List<bool>?',
    'nested',
    Envelopec04Schema,
    () => [
      (Envelopec04()
        ..dbId = 1
        ..value = (Payloadc04()..value = (<bool>[(true), (false)]))),
      (Envelopec04()
        ..dbId = 2
        ..value = (Payloadc04()..value = (<bool>[]))),
      (Envelopec04()
        ..dbId = 3
        ..value = (Payloadc04()..value = (null))),
    ],
    (object) => object.value.value,
    (collection) => Envelopec04CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => (value as Payloadc04).value,
  );
  _register<Modelc05>(
    backend,
    'c05',
    'List<bool?>?',
    'root',
    Modelc05Schema,
    () => [
      (Modelc05()
        ..dbId = 1
        ..value = (<bool?>[(true), (false), null])),
      (Modelc05()
        ..dbId = 2
        ..value = (<bool?>[])),
      (Modelc05()
        ..dbId = 3
        ..value = (null)),
      (Modelc05()
        ..dbId = 4
        ..value = (<bool?>[null, null])),
    ],
    (object) => object.value,
    (collection) => Modelc05CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => value,
  );
  _register<Envelopec05>(
    backend,
    'c05',
    'List<bool?>?',
    'nested',
    Envelopec05Schema,
    () => [
      (Envelopec05()
        ..dbId = 1
        ..value = (Payloadc05()..value = (<bool?>[(true), (false), null]))),
      (Envelopec05()
        ..dbId = 2
        ..value = (Payloadc05()..value = (<bool?>[]))),
      (Envelopec05()
        ..dbId = 3
        ..value = (Payloadc05()..value = (null))),
      (Envelopec05()
        ..dbId = 4
        ..value = (Payloadc05()..value = (<bool?>[null, null]))),
    ],
    (object) => object.value.value,
    (collection) => Envelopec05CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => (value as Payloadc05).value,
  );
  _register<Modelc06>(
    backend,
    'c06',
    'int',
    'root',
    Modelc06Schema,
    () => [
      (Modelc06()
        ..dbId = 1
        ..value = (42)),
      (Modelc06()
        ..dbId = 2
        ..value = (-7)),
    ],
    (object) => object.value,
    (collection) => Modelc06CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => value,
  );
  _register<Envelopec06>(
    backend,
    'c06',
    'int',
    'nested',
    Envelopec06Schema,
    () => [
      (Envelopec06()
        ..dbId = 1
        ..value = (Payloadc06()..value = (42))),
      (Envelopec06()
        ..dbId = 2
        ..value = (Payloadc06()..value = (-7))),
    ],
    (object) => object.value.value,
    (collection) => Envelopec06CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => (value as Payloadc06).value,
  );
  _register<Modelc07>(
    backend,
    'c07',
    'int?',
    'root',
    Modelc07Schema,
    () => [
      (Modelc07()
        ..dbId = 1
        ..value = (42)),
      (Modelc07()
        ..dbId = 2
        ..value = (-7)),
      (Modelc07()
        ..dbId = 3
        ..value = (null)),
    ],
    (object) => object.value,
    (collection) => Modelc07CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => value,
  );
  _register<Envelopec07>(
    backend,
    'c07',
    'int?',
    'nested',
    Envelopec07Schema,
    () => [
      (Envelopec07()
        ..dbId = 1
        ..value = (Payloadc07()..value = (42))),
      (Envelopec07()
        ..dbId = 2
        ..value = (Payloadc07()..value = (-7))),
      (Envelopec07()
        ..dbId = 3
        ..value = (Payloadc07()..value = (null))),
    ],
    (object) => object.value.value,
    (collection) => Envelopec07CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => (value as Payloadc07).value,
  );
  _register<Modelc08>(
    backend,
    'c08',
    'List<int>',
    'root',
    Modelc08Schema,
    () => [
      (Modelc08()
        ..dbId = 1
        ..value = (<int>[(42), (-7)])),
      (Modelc08()
        ..dbId = 2
        ..value = (<int>[])),
    ],
    (object) => object.value,
    (collection) => Modelc08CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => value,
  );
  _register<Envelopec08>(
    backend,
    'c08',
    'List<int>',
    'nested',
    Envelopec08Schema,
    () => [
      (Envelopec08()
        ..dbId = 1
        ..value = (Payloadc08()..value = (<int>[(42), (-7)]))),
      (Envelopec08()
        ..dbId = 2
        ..value = (Payloadc08()..value = (<int>[]))),
    ],
    (object) => object.value.value,
    (collection) => Envelopec08CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => (value as Payloadc08).value,
  );
  _register<Modelc09>(
    backend,
    'c09',
    'List<int?>',
    'root',
    Modelc09Schema,
    () => [
      (Modelc09()
        ..dbId = 1
        ..value = (<int?>[(42), (-7), null])),
      (Modelc09()
        ..dbId = 2
        ..value = (<int?>[])),
      (Modelc09()
        ..dbId = 3
        ..value = (<int?>[null, null])),
    ],
    (object) => object.value,
    (collection) => Modelc09CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => value,
  );
  _register<Envelopec09>(
    backend,
    'c09',
    'List<int?>',
    'nested',
    Envelopec09Schema,
    () => [
      (Envelopec09()
        ..dbId = 1
        ..value = (Payloadc09()..value = (<int?>[(42), (-7), null]))),
      (Envelopec09()
        ..dbId = 2
        ..value = (Payloadc09()..value = (<int?>[]))),
      (Envelopec09()
        ..dbId = 3
        ..value = (Payloadc09()..value = (<int?>[null, null]))),
    ],
    (object) => object.value.value,
    (collection) => Envelopec09CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => (value as Payloadc09).value,
  );
  _register<Modelc10>(
    backend,
    'c10',
    'List<int>?',
    'root',
    Modelc10Schema,
    () => [
      (Modelc10()
        ..dbId = 1
        ..value = (<int>[(42), (-7)])),
      (Modelc10()
        ..dbId = 2
        ..value = (<int>[])),
      (Modelc10()
        ..dbId = 3
        ..value = (null)),
    ],
    (object) => object.value,
    (collection) => Modelc10CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => value,
  );
  _register<Envelopec10>(
    backend,
    'c10',
    'List<int>?',
    'nested',
    Envelopec10Schema,
    () => [
      (Envelopec10()
        ..dbId = 1
        ..value = (Payloadc10()..value = (<int>[(42), (-7)]))),
      (Envelopec10()
        ..dbId = 2
        ..value = (Payloadc10()..value = (<int>[]))),
      (Envelopec10()
        ..dbId = 3
        ..value = (Payloadc10()..value = (null))),
    ],
    (object) => object.value.value,
    (collection) => Envelopec10CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => (value as Payloadc10).value,
  );
  _register<Modelc11>(
    backend,
    'c11',
    'List<int?>?',
    'root',
    Modelc11Schema,
    () => [
      (Modelc11()
        ..dbId = 1
        ..value = (<int?>[(42), (-7), null])),
      (Modelc11()
        ..dbId = 2
        ..value = (<int?>[])),
      (Modelc11()
        ..dbId = 3
        ..value = (null)),
      (Modelc11()
        ..dbId = 4
        ..value = (<int?>[null, null])),
    ],
    (object) => object.value,
    (collection) => Modelc11CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => value,
  );
  _register<Envelopec11>(
    backend,
    'c11',
    'List<int?>?',
    'nested',
    Envelopec11Schema,
    () => [
      (Envelopec11()
        ..dbId = 1
        ..value = (Payloadc11()..value = (<int?>[(42), (-7), null]))),
      (Envelopec11()
        ..dbId = 2
        ..value = (Payloadc11()..value = (<int?>[]))),
      (Envelopec11()
        ..dbId = 3
        ..value = (Payloadc11()..value = (null))),
      (Envelopec11()
        ..dbId = 4
        ..value = (Payloadc11()..value = (<int?>[null, null]))),
    ],
    (object) => object.value.value,
    (collection) => Envelopec11CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => (value as Payloadc11).value,
  );
  _register<Modelc12>(
    backend,
    'c12',
    'double',
    'root',
    Modelc12Schema,
    () => [
      (Modelc12()
        ..dbId = 1
        ..value = (1.25)),
      (Modelc12()
        ..dbId = 2
        ..value = (-3.5)),
    ],
    (object) => object.value,
    (collection) => Modelc12CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => value,
  );
  _register<Envelopec12>(
    backend,
    'c12',
    'double',
    'nested',
    Envelopec12Schema,
    () => [
      (Envelopec12()
        ..dbId = 1
        ..value = (Payloadc12()..value = (1.25))),
      (Envelopec12()
        ..dbId = 2
        ..value = (Payloadc12()..value = (-3.5))),
    ],
    (object) => object.value.value,
    (collection) => Envelopec12CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => (value as Payloadc12).value,
  );
  _register<Modelc13>(
    backend,
    'c13',
    'double?',
    'root',
    Modelc13Schema,
    () => [
      (Modelc13()
        ..dbId = 1
        ..value = (1.25)),
      (Modelc13()
        ..dbId = 2
        ..value = (-3.5)),
      (Modelc13()
        ..dbId = 3
        ..value = (null)),
    ],
    (object) => object.value,
    (collection) => Modelc13CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => value,
  );
  _register<Envelopec13>(
    backend,
    'c13',
    'double?',
    'nested',
    Envelopec13Schema,
    () => [
      (Envelopec13()
        ..dbId = 1
        ..value = (Payloadc13()..value = (1.25))),
      (Envelopec13()
        ..dbId = 2
        ..value = (Payloadc13()..value = (-3.5))),
      (Envelopec13()
        ..dbId = 3
        ..value = (Payloadc13()..value = (null))),
    ],
    (object) => object.value.value,
    (collection) => Envelopec13CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => (value as Payloadc13).value,
  );
  _register<Modelc14>(
    backend,
    'c14',
    'List<double>',
    'root',
    Modelc14Schema,
    () => [
      (Modelc14()
        ..dbId = 1
        ..value = (<double>[(1.25), (-3.5)])),
      (Modelc14()
        ..dbId = 2
        ..value = (<double>[])),
    ],
    (object) => object.value,
    (collection) => Modelc14CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => value,
  );
  _register<Envelopec14>(
    backend,
    'c14',
    'List<double>',
    'nested',
    Envelopec14Schema,
    () => [
      (Envelopec14()
        ..dbId = 1
        ..value = (Payloadc14()..value = (<double>[(1.25), (-3.5)]))),
      (Envelopec14()
        ..dbId = 2
        ..value = (Payloadc14()..value = (<double>[]))),
    ],
    (object) => object.value.value,
    (collection) => Envelopec14CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => (value as Payloadc14).value,
  );
  _register<Modelc15>(
    backend,
    'c15',
    'List<double?>',
    'root',
    Modelc15Schema,
    () => [
      (Modelc15()
        ..dbId = 1
        ..value = (<double?>[(1.25), (-3.5), null])),
      (Modelc15()
        ..dbId = 2
        ..value = (<double?>[])),
      (Modelc15()
        ..dbId = 3
        ..value = (<double?>[null, null])),
    ],
    (object) => object.value,
    (collection) => Modelc15CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => value,
  );
  _register<Envelopec15>(
    backend,
    'c15',
    'List<double?>',
    'nested',
    Envelopec15Schema,
    () => [
      (Envelopec15()
        ..dbId = 1
        ..value = (Payloadc15()..value = (<double?>[(1.25), (-3.5), null]))),
      (Envelopec15()
        ..dbId = 2
        ..value = (Payloadc15()..value = (<double?>[]))),
      (Envelopec15()
        ..dbId = 3
        ..value = (Payloadc15()..value = (<double?>[null, null]))),
    ],
    (object) => object.value.value,
    (collection) => Envelopec15CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => (value as Payloadc15).value,
  );
  _register<Modelc16>(
    backend,
    'c16',
    'List<double>?',
    'root',
    Modelc16Schema,
    () => [
      (Modelc16()
        ..dbId = 1
        ..value = (<double>[(1.25), (-3.5)])),
      (Modelc16()
        ..dbId = 2
        ..value = (<double>[])),
      (Modelc16()
        ..dbId = 3
        ..value = (null)),
    ],
    (object) => object.value,
    (collection) => Modelc16CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => value,
  );
  _register<Envelopec16>(
    backend,
    'c16',
    'List<double>?',
    'nested',
    Envelopec16Schema,
    () => [
      (Envelopec16()
        ..dbId = 1
        ..value = (Payloadc16()..value = (<double>[(1.25), (-3.5)]))),
      (Envelopec16()
        ..dbId = 2
        ..value = (Payloadc16()..value = (<double>[]))),
      (Envelopec16()
        ..dbId = 3
        ..value = (Payloadc16()..value = (null))),
    ],
    (object) => object.value.value,
    (collection) => Envelopec16CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => (value as Payloadc16).value,
  );
  _register<Modelc17>(
    backend,
    'c17',
    'List<double?>?',
    'root',
    Modelc17Schema,
    () => [
      (Modelc17()
        ..dbId = 1
        ..value = (<double?>[(1.25), (-3.5), null])),
      (Modelc17()
        ..dbId = 2
        ..value = (<double?>[])),
      (Modelc17()
        ..dbId = 3
        ..value = (null)),
      (Modelc17()
        ..dbId = 4
        ..value = (<double?>[null, null])),
    ],
    (object) => object.value,
    (collection) => Modelc17CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => value,
  );
  _register<Envelopec17>(
    backend,
    'c17',
    'List<double?>?',
    'nested',
    Envelopec17Schema,
    () => [
      (Envelopec17()
        ..dbId = 1
        ..value = (Payloadc17()..value = (<double?>[(1.25), (-3.5), null]))),
      (Envelopec17()
        ..dbId = 2
        ..value = (Payloadc17()..value = (<double?>[]))),
      (Envelopec17()
        ..dbId = 3
        ..value = (Payloadc17()..value = (null))),
      (Envelopec17()
        ..dbId = 4
        ..value = (Payloadc17()..value = (<double?>[null, null]))),
    ],
    (object) => object.value.value,
    (collection) => Envelopec17CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => (value as Payloadc17).value,
  );
  _register<Modelc18>(
    backend,
    'c18',
    'String',
    'root',
    Modelc18Schema,
    () => [
      (Modelc18()
        ..dbId = 1
        ..value = ('á🚀')),
      (Modelc18()
        ..dbId = 2
        ..value = ('')),
    ],
    (object) => object.value,
    (collection) => Modelc18CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => value,
  );
  _register<Envelopec18>(
    backend,
    'c18',
    'String',
    'nested',
    Envelopec18Schema,
    () => [
      (Envelopec18()
        ..dbId = 1
        ..value = (Payloadc18()..value = ('á🚀'))),
      (Envelopec18()
        ..dbId = 2
        ..value = (Payloadc18()..value = (''))),
    ],
    (object) => object.value.value,
    (collection) => Envelopec18CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => (value as Payloadc18).value,
  );
  _register<Modelc19>(
    backend,
    'c19',
    'String?',
    'root',
    Modelc19Schema,
    () => [
      (Modelc19()
        ..dbId = 1
        ..value = ('á🚀')),
      (Modelc19()
        ..dbId = 2
        ..value = ('')),
      (Modelc19()
        ..dbId = 3
        ..value = (null)),
    ],
    (object) => object.value,
    (collection) => Modelc19CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => value,
  );
  _register<Envelopec19>(
    backend,
    'c19',
    'String?',
    'nested',
    Envelopec19Schema,
    () => [
      (Envelopec19()
        ..dbId = 1
        ..value = (Payloadc19()..value = ('á🚀'))),
      (Envelopec19()
        ..dbId = 2
        ..value = (Payloadc19()..value = (''))),
      (Envelopec19()
        ..dbId = 3
        ..value = (Payloadc19()..value = (null))),
    ],
    (object) => object.value.value,
    (collection) => Envelopec19CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => (value as Payloadc19).value,
  );
  _register<Modelc20>(
    backend,
    'c20',
    'List<String>',
    'root',
    Modelc20Schema,
    () => [
      (Modelc20()
        ..dbId = 1
        ..value = (<String>[('á🚀'), ('')])),
      (Modelc20()
        ..dbId = 2
        ..value = (<String>[])),
    ],
    (object) => object.value,
    (collection) => Modelc20CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => value,
  );
  _register<Envelopec20>(
    backend,
    'c20',
    'List<String>',
    'nested',
    Envelopec20Schema,
    () => [
      (Envelopec20()
        ..dbId = 1
        ..value = (Payloadc20()..value = (<String>[('á🚀'), ('')]))),
      (Envelopec20()
        ..dbId = 2
        ..value = (Payloadc20()..value = (<String>[]))),
    ],
    (object) => object.value.value,
    (collection) => Envelopec20CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => (value as Payloadc20).value,
  );
  _register<Modelc21>(
    backend,
    'c21',
    'List<String?>',
    'root',
    Modelc21Schema,
    () => [
      (Modelc21()
        ..dbId = 1
        ..value = (<String?>[('á🚀'), (''), null])),
      (Modelc21()
        ..dbId = 2
        ..value = (<String?>[])),
      (Modelc21()
        ..dbId = 3
        ..value = (<String?>[null, null])),
    ],
    (object) => object.value,
    (collection) => Modelc21CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => value,
  );
  _register<Envelopec21>(
    backend,
    'c21',
    'List<String?>',
    'nested',
    Envelopec21Schema,
    () => [
      (Envelopec21()
        ..dbId = 1
        ..value = (Payloadc21()..value = (<String?>[('á🚀'), (''), null]))),
      (Envelopec21()
        ..dbId = 2
        ..value = (Payloadc21()..value = (<String?>[]))),
      (Envelopec21()
        ..dbId = 3
        ..value = (Payloadc21()..value = (<String?>[null, null]))),
    ],
    (object) => object.value.value,
    (collection) => Envelopec21CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => (value as Payloadc21).value,
  );
  _register<Modelc22>(
    backend,
    'c22',
    'List<String>?',
    'root',
    Modelc22Schema,
    () => [
      (Modelc22()
        ..dbId = 1
        ..value = (<String>[('á🚀'), ('')])),
      (Modelc22()
        ..dbId = 2
        ..value = (<String>[])),
      (Modelc22()
        ..dbId = 3
        ..value = (null)),
    ],
    (object) => object.value,
    (collection) => Modelc22CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => value,
  );
  _register<Envelopec22>(
    backend,
    'c22',
    'List<String>?',
    'nested',
    Envelopec22Schema,
    () => [
      (Envelopec22()
        ..dbId = 1
        ..value = (Payloadc22()..value = (<String>[('á🚀'), ('')]))),
      (Envelopec22()
        ..dbId = 2
        ..value = (Payloadc22()..value = (<String>[]))),
      (Envelopec22()
        ..dbId = 3
        ..value = (Payloadc22()..value = (null))),
    ],
    (object) => object.value.value,
    (collection) => Envelopec22CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => (value as Payloadc22).value,
  );
  _register<Modelc23>(
    backend,
    'c23',
    'List<String?>?',
    'root',
    Modelc23Schema,
    () => [
      (Modelc23()
        ..dbId = 1
        ..value = (<String?>[('á🚀'), (''), null])),
      (Modelc23()
        ..dbId = 2
        ..value = (<String?>[])),
      (Modelc23()
        ..dbId = 3
        ..value = (null)),
      (Modelc23()
        ..dbId = 4
        ..value = (<String?>[null, null])),
    ],
    (object) => object.value,
    (collection) => Modelc23CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => value,
  );
  _register<Envelopec23>(
    backend,
    'c23',
    'List<String?>?',
    'nested',
    Envelopec23Schema,
    () => [
      (Envelopec23()
        ..dbId = 1
        ..value = (Payloadc23()..value = (<String?>[('á🚀'), (''), null]))),
      (Envelopec23()
        ..dbId = 2
        ..value = (Payloadc23()..value = (<String?>[]))),
      (Envelopec23()
        ..dbId = 3
        ..value = (Payloadc23()..value = (null))),
      (Envelopec23()
        ..dbId = 4
        ..value = (Payloadc23()..value = (<String?>[null, null]))),
    ],
    (object) => object.value.value,
    (collection) => Envelopec23CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => (value as Payloadc23).value,
  );
  _register<Modelc24>(
    backend,
    'c24',
    'DateTime',
    'root',
    Modelc24Schema,
    () => [
      (Modelc24()
        ..dbId = 1
        ..value = (DateTime.fromMicrosecondsSinceEpoch(
          1700000000123456,
          isUtc: true,
        ))),
      (Modelc24()
        ..dbId = 2
        ..value = (DateTime.fromMicrosecondsSinceEpoch(-123456, isUtc: true))),
    ],
    (object) => object.value,
    (collection) => Modelc24CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => value,
  );
  _register<Envelopec24>(
    backend,
    'c24',
    'DateTime',
    'nested',
    Envelopec24Schema,
    () => [
      (Envelopec24()
        ..dbId = 1
        ..value = (Payloadc24()
          ..value = (DateTime.fromMicrosecondsSinceEpoch(
            1700000000123456,
            isUtc: true,
          )))),
      (Envelopec24()
        ..dbId = 2
        ..value = (Payloadc24()
          ..value = (DateTime.fromMicrosecondsSinceEpoch(
            -123456,
            isUtc: true,
          )))),
    ],
    (object) => object.value.value,
    (collection) => Envelopec24CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => (value as Payloadc24).value,
  );
  _register<Modelc25>(
    backend,
    'c25',
    'DateTime?',
    'root',
    Modelc25Schema,
    () => [
      (Modelc25()
        ..dbId = 1
        ..value = (DateTime.fromMicrosecondsSinceEpoch(
          1700000000123456,
          isUtc: true,
        ))),
      (Modelc25()
        ..dbId = 2
        ..value = (DateTime.fromMicrosecondsSinceEpoch(-123456, isUtc: true))),
      (Modelc25()
        ..dbId = 3
        ..value = (null)),
    ],
    (object) => object.value,
    (collection) => Modelc25CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => value,
  );
  _register<Envelopec25>(
    backend,
    'c25',
    'DateTime?',
    'nested',
    Envelopec25Schema,
    () => [
      (Envelopec25()
        ..dbId = 1
        ..value = (Payloadc25()
          ..value = (DateTime.fromMicrosecondsSinceEpoch(
            1700000000123456,
            isUtc: true,
          )))),
      (Envelopec25()
        ..dbId = 2
        ..value = (Payloadc25()
          ..value = (DateTime.fromMicrosecondsSinceEpoch(
            -123456,
            isUtc: true,
          )))),
      (Envelopec25()
        ..dbId = 3
        ..value = (Payloadc25()..value = (null))),
    ],
    (object) => object.value.value,
    (collection) => Envelopec25CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => (value as Payloadc25).value,
  );
  _register<Modelc26>(
    backend,
    'c26',
    'List<DateTime>',
    'root',
    Modelc26Schema,
    () => [
      (Modelc26()
        ..dbId = 1
        ..value = (<DateTime>[
          (DateTime.fromMicrosecondsSinceEpoch(1700000000123456, isUtc: true)),
          (DateTime.fromMicrosecondsSinceEpoch(-123456, isUtc: true)),
        ])),
      (Modelc26()
        ..dbId = 2
        ..value = (<DateTime>[])),
    ],
    (object) => object.value,
    (collection) => Modelc26CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => value,
  );
  _register<Envelopec26>(
    backend,
    'c26',
    'List<DateTime>',
    'nested',
    Envelopec26Schema,
    () => [
      (Envelopec26()
        ..dbId = 1
        ..value = (Payloadc26()
          ..value = (<DateTime>[
            (DateTime.fromMicrosecondsSinceEpoch(
              1700000000123456,
              isUtc: true,
            )),
            (DateTime.fromMicrosecondsSinceEpoch(-123456, isUtc: true)),
          ]))),
      (Envelopec26()
        ..dbId = 2
        ..value = (Payloadc26()..value = (<DateTime>[]))),
    ],
    (object) => object.value.value,
    (collection) => Envelopec26CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => (value as Payloadc26).value,
  );
  _register<Modelc27>(
    backend,
    'c27',
    'List<DateTime?>',
    'root',
    Modelc27Schema,
    () => [
      (Modelc27()
        ..dbId = 1
        ..value = (<DateTime?>[
          (DateTime.fromMicrosecondsSinceEpoch(1700000000123456, isUtc: true)),
          (DateTime.fromMicrosecondsSinceEpoch(-123456, isUtc: true)),
          null,
        ])),
      (Modelc27()
        ..dbId = 2
        ..value = (<DateTime?>[])),
      (Modelc27()
        ..dbId = 3
        ..value = (<DateTime?>[null, null])),
    ],
    (object) => object.value,
    (collection) => Modelc27CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => value,
  );
  _register<Envelopec27>(
    backend,
    'c27',
    'List<DateTime?>',
    'nested',
    Envelopec27Schema,
    () => [
      (Envelopec27()
        ..dbId = 1
        ..value = (Payloadc27()
          ..value = (<DateTime?>[
            (DateTime.fromMicrosecondsSinceEpoch(
              1700000000123456,
              isUtc: true,
            )),
            (DateTime.fromMicrosecondsSinceEpoch(-123456, isUtc: true)),
            null,
          ]))),
      (Envelopec27()
        ..dbId = 2
        ..value = (Payloadc27()..value = (<DateTime?>[]))),
      (Envelopec27()
        ..dbId = 3
        ..value = (Payloadc27()..value = (<DateTime?>[null, null]))),
    ],
    (object) => object.value.value,
    (collection) => Envelopec27CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => (value as Payloadc27).value,
  );
  _register<Modelc28>(
    backend,
    'c28',
    'List<DateTime>?',
    'root',
    Modelc28Schema,
    () => [
      (Modelc28()
        ..dbId = 1
        ..value = (<DateTime>[
          (DateTime.fromMicrosecondsSinceEpoch(1700000000123456, isUtc: true)),
          (DateTime.fromMicrosecondsSinceEpoch(-123456, isUtc: true)),
        ])),
      (Modelc28()
        ..dbId = 2
        ..value = (<DateTime>[])),
      (Modelc28()
        ..dbId = 3
        ..value = (null)),
    ],
    (object) => object.value,
    (collection) => Modelc28CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => value,
  );
  _register<Envelopec28>(
    backend,
    'c28',
    'List<DateTime>?',
    'nested',
    Envelopec28Schema,
    () => [
      (Envelopec28()
        ..dbId = 1
        ..value = (Payloadc28()
          ..value = (<DateTime>[
            (DateTime.fromMicrosecondsSinceEpoch(
              1700000000123456,
              isUtc: true,
            )),
            (DateTime.fromMicrosecondsSinceEpoch(-123456, isUtc: true)),
          ]))),
      (Envelopec28()
        ..dbId = 2
        ..value = (Payloadc28()..value = (<DateTime>[]))),
      (Envelopec28()
        ..dbId = 3
        ..value = (Payloadc28()..value = (null))),
    ],
    (object) => object.value.value,
    (collection) => Envelopec28CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => (value as Payloadc28).value,
  );
  _register<Modelc29>(
    backend,
    'c29',
    'List<DateTime?>?',
    'root',
    Modelc29Schema,
    () => [
      (Modelc29()
        ..dbId = 1
        ..value = (<DateTime?>[
          (DateTime.fromMicrosecondsSinceEpoch(1700000000123456, isUtc: true)),
          (DateTime.fromMicrosecondsSinceEpoch(-123456, isUtc: true)),
          null,
        ])),
      (Modelc29()
        ..dbId = 2
        ..value = (<DateTime?>[])),
      (Modelc29()
        ..dbId = 3
        ..value = (null)),
      (Modelc29()
        ..dbId = 4
        ..value = (<DateTime?>[null, null])),
    ],
    (object) => object.value,
    (collection) => Modelc29CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => value,
  );
  _register<Envelopec29>(
    backend,
    'c29',
    'List<DateTime?>?',
    'nested',
    Envelopec29Schema,
    () => [
      (Envelopec29()
        ..dbId = 1
        ..value = (Payloadc29()
          ..value = (<DateTime?>[
            (DateTime.fromMicrosecondsSinceEpoch(
              1700000000123456,
              isUtc: true,
            )),
            (DateTime.fromMicrosecondsSinceEpoch(-123456, isUtc: true)),
            null,
          ]))),
      (Envelopec29()
        ..dbId = 2
        ..value = (Payloadc29()..value = (<DateTime?>[]))),
      (Envelopec29()
        ..dbId = 3
        ..value = (Payloadc29()..value = (null))),
      (Envelopec29()
        ..dbId = 4
        ..value = (Payloadc29()..value = (<DateTime?>[null, null]))),
    ],
    (object) => object.value.value,
    (collection) => Envelopec29CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => (value as Payloadc29).value,
  );
  _register<Modelc30>(
    backend,
    'c30',
    'Duration',
    'root',
    Modelc30Schema,
    () => [
      (Modelc30()
        ..dbId = 1
        ..value = (const Duration(microseconds: 123456))),
      (Modelc30()
        ..dbId = 2
        ..value = (const Duration(microseconds: -567))),
    ],
    (object) => object.value,
    (collection) => Modelc30CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => value,
  );
  _register<Envelopec30>(
    backend,
    'c30',
    'Duration',
    'nested',
    Envelopec30Schema,
    () => [
      (Envelopec30()
        ..dbId = 1
        ..value = (Payloadc30()
          ..value = (const Duration(microseconds: 123456)))),
      (Envelopec30()
        ..dbId = 2
        ..value = (Payloadc30()..value = (const Duration(microseconds: -567)))),
    ],
    (object) => object.value.value,
    (collection) => Envelopec30CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => (value as Payloadc30).value,
  );
  _register<Modelc31>(
    backend,
    'c31',
    'Duration?',
    'root',
    Modelc31Schema,
    () => [
      (Modelc31()
        ..dbId = 1
        ..value = (const Duration(microseconds: 123456))),
      (Modelc31()
        ..dbId = 2
        ..value = (const Duration(microseconds: -567))),
      (Modelc31()
        ..dbId = 3
        ..value = (null)),
    ],
    (object) => object.value,
    (collection) => Modelc31CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => value,
  );
  _register<Envelopec31>(
    backend,
    'c31',
    'Duration?',
    'nested',
    Envelopec31Schema,
    () => [
      (Envelopec31()
        ..dbId = 1
        ..value = (Payloadc31()
          ..value = (const Duration(microseconds: 123456)))),
      (Envelopec31()
        ..dbId = 2
        ..value = (Payloadc31()..value = (const Duration(microseconds: -567)))),
      (Envelopec31()
        ..dbId = 3
        ..value = (Payloadc31()..value = (null))),
    ],
    (object) => object.value.value,
    (collection) => Envelopec31CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => (value as Payloadc31).value,
  );
  _register<Modelc32>(
    backend,
    'c32',
    'List<Duration>',
    'root',
    Modelc32Schema,
    () => [
      (Modelc32()
        ..dbId = 1
        ..value = (<Duration>[
          (const Duration(microseconds: 123456)),
          (const Duration(microseconds: -567)),
        ])),
      (Modelc32()
        ..dbId = 2
        ..value = (<Duration>[])),
    ],
    (object) => object.value,
    (collection) => Modelc32CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => value,
  );
  _register<Envelopec32>(
    backend,
    'c32',
    'List<Duration>',
    'nested',
    Envelopec32Schema,
    () => [
      (Envelopec32()
        ..dbId = 1
        ..value = (Payloadc32()
          ..value = (<Duration>[
            (const Duration(microseconds: 123456)),
            (const Duration(microseconds: -567)),
          ]))),
      (Envelopec32()
        ..dbId = 2
        ..value = (Payloadc32()..value = (<Duration>[]))),
    ],
    (object) => object.value.value,
    (collection) => Envelopec32CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => (value as Payloadc32).value,
  );
  _register<Modelc33>(
    backend,
    'c33',
    'List<Duration?>',
    'root',
    Modelc33Schema,
    () => [
      (Modelc33()
        ..dbId = 1
        ..value = (<Duration?>[
          (const Duration(microseconds: 123456)),
          (const Duration(microseconds: -567)),
          null,
        ])),
      (Modelc33()
        ..dbId = 2
        ..value = (<Duration?>[])),
      (Modelc33()
        ..dbId = 3
        ..value = (<Duration?>[null, null])),
    ],
    (object) => object.value,
    (collection) => Modelc33CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => value,
  );
  _register<Envelopec33>(
    backend,
    'c33',
    'List<Duration?>',
    'nested',
    Envelopec33Schema,
    () => [
      (Envelopec33()
        ..dbId = 1
        ..value = (Payloadc33()
          ..value = (<Duration?>[
            (const Duration(microseconds: 123456)),
            (const Duration(microseconds: -567)),
            null,
          ]))),
      (Envelopec33()
        ..dbId = 2
        ..value = (Payloadc33()..value = (<Duration?>[]))),
      (Envelopec33()
        ..dbId = 3
        ..value = (Payloadc33()..value = (<Duration?>[null, null]))),
    ],
    (object) => object.value.value,
    (collection) => Envelopec33CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => (value as Payloadc33).value,
  );
  _register<Modelc34>(
    backend,
    'c34',
    'List<Duration>?',
    'root',
    Modelc34Schema,
    () => [
      (Modelc34()
        ..dbId = 1
        ..value = (<Duration>[
          (const Duration(microseconds: 123456)),
          (const Duration(microseconds: -567)),
        ])),
      (Modelc34()
        ..dbId = 2
        ..value = (<Duration>[])),
      (Modelc34()
        ..dbId = 3
        ..value = (null)),
    ],
    (object) => object.value,
    (collection) => Modelc34CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => value,
  );
  _register<Envelopec34>(
    backend,
    'c34',
    'List<Duration>?',
    'nested',
    Envelopec34Schema,
    () => [
      (Envelopec34()
        ..dbId = 1
        ..value = (Payloadc34()
          ..value = (<Duration>[
            (const Duration(microseconds: 123456)),
            (const Duration(microseconds: -567)),
          ]))),
      (Envelopec34()
        ..dbId = 2
        ..value = (Payloadc34()..value = (<Duration>[]))),
      (Envelopec34()
        ..dbId = 3
        ..value = (Payloadc34()..value = (null))),
    ],
    (object) => object.value.value,
    (collection) => Envelopec34CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => (value as Payloadc34).value,
  );
  _register<Modelc35>(
    backend,
    'c35',
    'List<Duration?>?',
    'root',
    Modelc35Schema,
    () => [
      (Modelc35()
        ..dbId = 1
        ..value = (<Duration?>[
          (const Duration(microseconds: 123456)),
          (const Duration(microseconds: -567)),
          null,
        ])),
      (Modelc35()
        ..dbId = 2
        ..value = (<Duration?>[])),
      (Modelc35()
        ..dbId = 3
        ..value = (null)),
      (Modelc35()
        ..dbId = 4
        ..value = (<Duration?>[null, null])),
    ],
    (object) => object.value,
    (collection) => Modelc35CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => value,
  );
  _register<Envelopec35>(
    backend,
    'c35',
    'List<Duration?>?',
    'nested',
    Envelopec35Schema,
    () => [
      (Envelopec35()
        ..dbId = 1
        ..value = (Payloadc35()
          ..value = (<Duration?>[
            (const Duration(microseconds: 123456)),
            (const Duration(microseconds: -567)),
            null,
          ]))),
      (Envelopec35()
        ..dbId = 2
        ..value = (Payloadc35()..value = (<Duration?>[]))),
      (Envelopec35()
        ..dbId = 3
        ..value = (Payloadc35()..value = (null))),
      (Envelopec35()
        ..dbId = 4
        ..value = (Payloadc35()..value = (<Duration?>[null, null]))),
    ],
    (object) => object.value.value,
    (collection) => Envelopec35CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => (value as Payloadc35).value,
  );
  _register<Modelc36>(
    backend,
    'c36',
    'ProbeEnum',
    'root',
    Modelc36Schema,
    () => [
      (Modelc36()
        ..dbId = 1
        ..value = (ProbeEnum.first)),
      (Modelc36()
        ..dbId = 2
        ..value = (ProbeEnum.second)),
    ],
    (object) => object.value,
    (collection) => Modelc36CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => value,
  );
  _register<Envelopec36>(
    backend,
    'c36',
    'ProbeEnum',
    'nested',
    Envelopec36Schema,
    () => [
      (Envelopec36()
        ..dbId = 1
        ..value = (Payloadc36()..value = (ProbeEnum.first))),
      (Envelopec36()
        ..dbId = 2
        ..value = (Payloadc36()..value = (ProbeEnum.second))),
    ],
    (object) => object.value.value,
    (collection) => Envelopec36CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => (value as Payloadc36).value,
  );
  _register<Modelc37>(
    backend,
    'c37',
    'ProbeEnum?',
    'root',
    Modelc37Schema,
    () => [
      (Modelc37()
        ..dbId = 1
        ..value = (ProbeEnum.first)),
      (Modelc37()
        ..dbId = 2
        ..value = (ProbeEnum.second)),
      (Modelc37()
        ..dbId = 3
        ..value = (null)),
    ],
    (object) => object.value,
    (collection) => Modelc37CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => value,
  );
  _register<Envelopec37>(
    backend,
    'c37',
    'ProbeEnum?',
    'nested',
    Envelopec37Schema,
    () => [
      (Envelopec37()
        ..dbId = 1
        ..value = (Payloadc37()..value = (ProbeEnum.first))),
      (Envelopec37()
        ..dbId = 2
        ..value = (Payloadc37()..value = (ProbeEnum.second))),
      (Envelopec37()
        ..dbId = 3
        ..value = (Payloadc37()..value = (null))),
    ],
    (object) => object.value.value,
    (collection) => Envelopec37CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => (value as Payloadc37).value,
  );
  _register<Modelc38>(
    backend,
    'c38',
    'List<ProbeEnum>',
    'root',
    Modelc38Schema,
    () => [
      (Modelc38()
        ..dbId = 1
        ..value = (<ProbeEnum>[(ProbeEnum.first), (ProbeEnum.second)])),
      (Modelc38()
        ..dbId = 2
        ..value = (<ProbeEnum>[])),
    ],
    (object) => object.value,
    (collection) => Modelc38CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => value,
  );
  _register<Envelopec38>(
    backend,
    'c38',
    'List<ProbeEnum>',
    'nested',
    Envelopec38Schema,
    () => [
      (Envelopec38()
        ..dbId = 1
        ..value = (Payloadc38()
          ..value = (<ProbeEnum>[(ProbeEnum.first), (ProbeEnum.second)]))),
      (Envelopec38()
        ..dbId = 2
        ..value = (Payloadc38()..value = (<ProbeEnum>[]))),
    ],
    (object) => object.value.value,
    (collection) => Envelopec38CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => (value as Payloadc38).value,
  );
  _register<Modelc39>(
    backend,
    'c39',
    'List<ProbeEnum?>',
    'root',
    Modelc39Schema,
    () => [
      (Modelc39()
        ..dbId = 1
        ..value = (<ProbeEnum?>[(ProbeEnum.first), (ProbeEnum.second), null])),
      (Modelc39()
        ..dbId = 2
        ..value = (<ProbeEnum?>[])),
      (Modelc39()
        ..dbId = 3
        ..value = (<ProbeEnum?>[null, null])),
    ],
    (object) => object.value,
    (collection) => Modelc39CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => value,
  );
  _register<Envelopec39>(
    backend,
    'c39',
    'List<ProbeEnum?>',
    'nested',
    Envelopec39Schema,
    () => [
      (Envelopec39()
        ..dbId = 1
        ..value = (Payloadc39()
          ..value = (<ProbeEnum?>[
            (ProbeEnum.first),
            (ProbeEnum.second),
            null,
          ]))),
      (Envelopec39()
        ..dbId = 2
        ..value = (Payloadc39()..value = (<ProbeEnum?>[]))),
      (Envelopec39()
        ..dbId = 3
        ..value = (Payloadc39()..value = (<ProbeEnum?>[null, null]))),
    ],
    (object) => object.value.value,
    (collection) => Envelopec39CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => (value as Payloadc39).value,
  );
  _register<Modelc40>(
    backend,
    'c40',
    'List<ProbeEnum>?',
    'root',
    Modelc40Schema,
    () => [
      (Modelc40()
        ..dbId = 1
        ..value = (<ProbeEnum>[(ProbeEnum.first), (ProbeEnum.second)])),
      (Modelc40()
        ..dbId = 2
        ..value = (<ProbeEnum>[])),
      (Modelc40()
        ..dbId = 3
        ..value = (null)),
    ],
    (object) => object.value,
    (collection) => Modelc40CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => value,
  );
  _register<Envelopec40>(
    backend,
    'c40',
    'List<ProbeEnum>?',
    'nested',
    Envelopec40Schema,
    () => [
      (Envelopec40()
        ..dbId = 1
        ..value = (Payloadc40()
          ..value = (<ProbeEnum>[(ProbeEnum.first), (ProbeEnum.second)]))),
      (Envelopec40()
        ..dbId = 2
        ..value = (Payloadc40()..value = (<ProbeEnum>[]))),
      (Envelopec40()
        ..dbId = 3
        ..value = (Payloadc40()..value = (null))),
    ],
    (object) => object.value.value,
    (collection) => Envelopec40CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => (value as Payloadc40).value,
  );
  _register<Modelc41>(
    backend,
    'c41',
    'List<ProbeEnum?>?',
    'root',
    Modelc41Schema,
    () => [
      (Modelc41()
        ..dbId = 1
        ..value = (<ProbeEnum?>[(ProbeEnum.first), (ProbeEnum.second), null])),
      (Modelc41()
        ..dbId = 2
        ..value = (<ProbeEnum?>[])),
      (Modelc41()
        ..dbId = 3
        ..value = (null)),
      (Modelc41()
        ..dbId = 4
        ..value = (<ProbeEnum?>[null, null])),
    ],
    (object) => object.value,
    (collection) => Modelc41CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => value,
  );
  _register<Envelopec41>(
    backend,
    'c41',
    'List<ProbeEnum?>?',
    'nested',
    Envelopec41Schema,
    () => [
      (Envelopec41()
        ..dbId = 1
        ..value = (Payloadc41()
          ..value = (<ProbeEnum?>[
            (ProbeEnum.first),
            (ProbeEnum.second),
            null,
          ]))),
      (Envelopec41()
        ..dbId = 2
        ..value = (Payloadc41()..value = (<ProbeEnum?>[]))),
      (Envelopec41()
        ..dbId = 3
        ..value = (Payloadc41()..value = (null))),
      (Envelopec41()
        ..dbId = 4
        ..value = (Payloadc41()..value = (<ProbeEnum?>[null, null]))),
    ],
    (object) => object.value.value,
    (collection) => Envelopec41CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => (value as Payloadc41).value,
  );
  _register<Modelc42>(
    backend,
    'c42',
    'ProbeEnum',
    'root',
    Modelc42Schema,
    () => [
      (Modelc42()
        ..dbId = 1
        ..value = (ProbeEnum.first)),
      (Modelc42()
        ..dbId = 2
        ..value = (ProbeEnum.second)),
    ],
    (object) => object.value,
    (collection) => Modelc42CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => value,
  );
  _register<Envelopec42>(
    backend,
    'c42',
    'ProbeEnum',
    'nested',
    Envelopec42Schema,
    () => [
      (Envelopec42()
        ..dbId = 1
        ..value = (Payloadc42()..value = (ProbeEnum.first))),
      (Envelopec42()
        ..dbId = 2
        ..value = (Payloadc42()..value = (ProbeEnum.second))),
    ],
    (object) => object.value.value,
    (collection) => Envelopec42CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => (value as Payloadc42).value,
  );
  _register<Modelc43>(
    backend,
    'c43',
    'ProbeEnum?',
    'root',
    Modelc43Schema,
    () => [
      (Modelc43()
        ..dbId = 1
        ..value = (ProbeEnum.first)),
      (Modelc43()
        ..dbId = 2
        ..value = (ProbeEnum.second)),
      (Modelc43()
        ..dbId = 3
        ..value = (null)),
    ],
    (object) => object.value,
    (collection) => Modelc43CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => value,
  );
  _register<Envelopec43>(
    backend,
    'c43',
    'ProbeEnum?',
    'nested',
    Envelopec43Schema,
    () => [
      (Envelopec43()
        ..dbId = 1
        ..value = (Payloadc43()..value = (ProbeEnum.first))),
      (Envelopec43()
        ..dbId = 2
        ..value = (Payloadc43()..value = (ProbeEnum.second))),
      (Envelopec43()
        ..dbId = 3
        ..value = (Payloadc43()..value = (null))),
    ],
    (object) => object.value.value,
    (collection) => Envelopec43CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => (value as Payloadc43).value,
  );
  _register<Modelc44>(
    backend,
    'c44',
    'ProbeStringEnum',
    'root',
    Modelc44Schema,
    () => [
      (Modelc44()
        ..dbId = 1
        ..value = (ProbeStringEnum.first)),
      (Modelc44()
        ..dbId = 2
        ..value = (ProbeStringEnum.second)),
    ],
    (object) => object.value,
    (collection) => Modelc44CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => value,
  );
  _register<Envelopec44>(
    backend,
    'c44',
    'ProbeStringEnum',
    'nested',
    Envelopec44Schema,
    () => [
      (Envelopec44()
        ..dbId = 1
        ..value = (Payloadc44()..value = (ProbeStringEnum.first))),
      (Envelopec44()
        ..dbId = 2
        ..value = (Payloadc44()..value = (ProbeStringEnum.second))),
    ],
    (object) => object.value.value,
    (collection) => Envelopec44CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => (value as Payloadc44).value,
  );
  _register<Modelc45>(
    backend,
    'c45',
    'ProbeStringEnum?',
    'root',
    Modelc45Schema,
    () => [
      (Modelc45()
        ..dbId = 1
        ..value = (ProbeStringEnum.first)),
      (Modelc45()
        ..dbId = 2
        ..value = (ProbeStringEnum.second)),
      (Modelc45()
        ..dbId = 3
        ..value = (null)),
    ],
    (object) => object.value,
    (collection) => Modelc45CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => value,
  );
  _register<Envelopec45>(
    backend,
    'c45',
    'ProbeStringEnum?',
    'nested',
    Envelopec45Schema,
    () => [
      (Envelopec45()
        ..dbId = 1
        ..value = (Payloadc45()..value = (ProbeStringEnum.first))),
      (Envelopec45()
        ..dbId = 2
        ..value = (Payloadc45()..value = (ProbeStringEnum.second))),
      (Envelopec45()
        ..dbId = 3
        ..value = (Payloadc45()..value = (null))),
    ],
    (object) => object.value.value,
    (collection) => Envelopec45CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => (value as Payloadc45).value,
  );
  _register<Modelc46>(
    backend,
    'c46',
    'ProbeintEnum',
    'root',
    Modelc46Schema,
    () => [
      (Modelc46()
        ..dbId = 1
        ..value = (ProbeintEnum.first)),
      (Modelc46()
        ..dbId = 2
        ..value = (ProbeintEnum.second)),
    ],
    (object) => object.value,
    (collection) => Modelc46CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => value,
  );
  _register<Envelopec46>(
    backend,
    'c46',
    'ProbeintEnum',
    'nested',
    Envelopec46Schema,
    () => [
      (Envelopec46()
        ..dbId = 1
        ..value = (Payloadc46()..value = (ProbeintEnum.first))),
      (Envelopec46()
        ..dbId = 2
        ..value = (Payloadc46()..value = (ProbeintEnum.second))),
    ],
    (object) => object.value.value,
    (collection) => Envelopec46CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => (value as Payloadc46).value,
  );
  _register<Modelc47>(
    backend,
    'c47',
    'ProbeintEnum?',
    'root',
    Modelc47Schema,
    () => [
      (Modelc47()
        ..dbId = 1
        ..value = (ProbeintEnum.first)),
      (Modelc47()
        ..dbId = 2
        ..value = (ProbeintEnum.second)),
      (Modelc47()
        ..dbId = 3
        ..value = (null)),
    ],
    (object) => object.value,
    (collection) => Modelc47CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => value,
  );
  _register<Envelopec47>(
    backend,
    'c47',
    'ProbeintEnum?',
    'nested',
    Envelopec47Schema,
    () => [
      (Envelopec47()
        ..dbId = 1
        ..value = (Payloadc47()..value = (ProbeintEnum.first))),
      (Envelopec47()
        ..dbId = 2
        ..value = (Payloadc47()..value = (ProbeintEnum.second))),
      (Envelopec47()
        ..dbId = 3
        ..value = (Payloadc47()..value = (null))),
    ],
    (object) => object.value.value,
    (collection) => Envelopec47CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => (value as Payloadc47).value,
  );
  _register<Modelc48>(
    backend,
    'c48',
    'ProbedoubleEnum',
    'root',
    Modelc48Schema,
    () => [
      (Modelc48()
        ..dbId = 1
        ..value = (ProbedoubleEnum.first)),
      (Modelc48()
        ..dbId = 2
        ..value = (ProbedoubleEnum.second)),
    ],
    (object) => object.value,
    (collection) => Modelc48CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => value,
  );
  _register<Envelopec48>(
    backend,
    'c48',
    'ProbedoubleEnum',
    'nested',
    Envelopec48Schema,
    () => [
      (Envelopec48()
        ..dbId = 1
        ..value = (Payloadc48()..value = (ProbedoubleEnum.first))),
      (Envelopec48()
        ..dbId = 2
        ..value = (Payloadc48()..value = (ProbedoubleEnum.second))),
    ],
    (object) => object.value.value,
    (collection) => Envelopec48CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => (value as Payloadc48).value,
  );
  _register<Modelc49>(
    backend,
    'c49',
    'ProbedoubleEnum?',
    'root',
    Modelc49Schema,
    () => [
      (Modelc49()
        ..dbId = 1
        ..value = (ProbedoubleEnum.first)),
      (Modelc49()
        ..dbId = 2
        ..value = (ProbedoubleEnum.second)),
      (Modelc49()
        ..dbId = 3
        ..value = (null)),
    ],
    (object) => object.value,
    (collection) => Modelc49CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => value,
  );
  _register<Envelopec49>(
    backend,
    'c49',
    'ProbedoubleEnum?',
    'nested',
    Envelopec49Schema,
    () => [
      (Envelopec49()
        ..dbId = 1
        ..value = (Payloadc49()..value = (ProbedoubleEnum.first))),
      (Envelopec49()
        ..dbId = 2
        ..value = (Payloadc49()..value = (ProbedoubleEnum.second))),
      (Envelopec49()
        ..dbId = 3
        ..value = (Payloadc49()..value = (null))),
    ],
    (object) => object.value.value,
    (collection) => Envelopec49CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => (value as Payloadc49).value,
  );
  _register<Modelc50>(
    backend,
    'c50',
    'ProbeboolEnum',
    'root',
    Modelc50Schema,
    () => [
      (Modelc50()
        ..dbId = 1
        ..value = (ProbeboolEnum.first)),
      (Modelc50()
        ..dbId = 2
        ..value = (ProbeboolEnum.second)),
    ],
    (object) => object.value,
    (collection) => Modelc50CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => value,
  );
  _register<Envelopec50>(
    backend,
    'c50',
    'ProbeboolEnum',
    'nested',
    Envelopec50Schema,
    () => [
      (Envelopec50()
        ..dbId = 1
        ..value = (Payloadc50()..value = (ProbeboolEnum.first))),
      (Envelopec50()
        ..dbId = 2
        ..value = (Payloadc50()..value = (ProbeboolEnum.second))),
    ],
    (object) => object.value.value,
    (collection) => Envelopec50CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => (value as Payloadc50).value,
  );
  _register<Modelc51>(
    backend,
    'c51',
    'ProbeboolEnum?',
    'root',
    Modelc51Schema,
    () => [
      (Modelc51()
        ..dbId = 1
        ..value = (ProbeboolEnum.first)),
      (Modelc51()
        ..dbId = 2
        ..value = (ProbeboolEnum.second)),
      (Modelc51()
        ..dbId = 3
        ..value = (null)),
    ],
    (object) => object.value,
    (collection) => Modelc51CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => value,
  );
  _register<Envelopec51>(
    backend,
    'c51',
    'ProbeboolEnum?',
    'nested',
    Envelopec51Schema,
    () => [
      (Envelopec51()
        ..dbId = 1
        ..value = (Payloadc51()..value = (ProbeboolEnum.first))),
      (Envelopec51()
        ..dbId = 2
        ..value = (Payloadc51()..value = (ProbeboolEnum.second))),
      (Envelopec51()
        ..dbId = 3
        ..value = (Payloadc51()..value = (null))),
    ],
    (object) => object.value.value,
    (collection) => Envelopec51CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => (value as Payloadc51).value,
  );
  _register<Modelc52>(
    backend,
    'c52',
    'ProbeLeaf',
    'root',
    Modelc52Schema,
    () => [
      (Modelc52()
        ..dbId = 1
        ..value = (ProbeLeaf()..label = 'á🚀')),
      (Modelc52()
        ..dbId = 2
        ..value = (ProbeLeaf()..label = null)),
    ],
    (object) => object.value,
    (collection) => Modelc52CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => value,
  );
  _register<Envelopec52>(
    backend,
    'c52',
    'ProbeLeaf',
    'nested',
    Envelopec52Schema,
    () => [
      (Envelopec52()
        ..dbId = 1
        ..value = (Payloadc52()..value = (ProbeLeaf()..label = 'á🚀'))),
      (Envelopec52()
        ..dbId = 2
        ..value = (Payloadc52()..value = (ProbeLeaf()..label = null))),
    ],
    (object) => object.value.value,
    (collection) => Envelopec52CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => (value as Payloadc52).value,
  );
  _register<Modelc53>(
    backend,
    'c53',
    'ProbeLeaf?',
    'root',
    Modelc53Schema,
    () => [
      (Modelc53()
        ..dbId = 1
        ..value = (ProbeLeaf()..label = 'á🚀')),
      (Modelc53()
        ..dbId = 2
        ..value = (ProbeLeaf()..label = null)),
      (Modelc53()
        ..dbId = 3
        ..value = (null)),
    ],
    (object) => object.value,
    (collection) => Modelc53CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => value,
  );
  _register<Envelopec53>(
    backend,
    'c53',
    'ProbeLeaf?',
    'nested',
    Envelopec53Schema,
    () => [
      (Envelopec53()
        ..dbId = 1
        ..value = (Payloadc53()..value = (ProbeLeaf()..label = 'á🚀'))),
      (Envelopec53()
        ..dbId = 2
        ..value = (Payloadc53()..value = (ProbeLeaf()..label = null))),
      (Envelopec53()
        ..dbId = 3
        ..value = (Payloadc53()..value = (null))),
    ],
    (object) => object.value.value,
    (collection) => Envelopec53CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => (value as Payloadc53).value,
  );
  _register<Modelc54>(
    backend,
    'c54',
    'List<ProbeLeaf>',
    'root',
    Modelc54Schema,
    () => [
      (Modelc54()
        ..dbId = 1
        ..value = (<ProbeLeaf>[
          (ProbeLeaf()..label = 'á🚀'),
          (ProbeLeaf()..label = null),
        ])),
      (Modelc54()
        ..dbId = 2
        ..value = (<ProbeLeaf>[])),
    ],
    (object) => object.value,
    (collection) => Modelc54CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => value,
  );
  _register<Envelopec54>(
    backend,
    'c54',
    'List<ProbeLeaf>',
    'nested',
    Envelopec54Schema,
    () => [
      (Envelopec54()
        ..dbId = 1
        ..value = (Payloadc54()
          ..value = (<ProbeLeaf>[
            (ProbeLeaf()..label = 'á🚀'),
            (ProbeLeaf()..label = null),
          ]))),
      (Envelopec54()
        ..dbId = 2
        ..value = (Payloadc54()..value = (<ProbeLeaf>[]))),
    ],
    (object) => object.value.value,
    (collection) => Envelopec54CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => (value as Payloadc54).value,
  );
  _register<Modelc55>(
    backend,
    'c55',
    'List<ProbeLeaf?>',
    'root',
    Modelc55Schema,
    () => [
      (Modelc55()
        ..dbId = 1
        ..value = (<ProbeLeaf?>[
          (ProbeLeaf()..label = 'á🚀'),
          (ProbeLeaf()..label = null),
          null,
        ])),
      (Modelc55()
        ..dbId = 2
        ..value = (<ProbeLeaf?>[])),
      (Modelc55()
        ..dbId = 3
        ..value = (<ProbeLeaf?>[null, null])),
    ],
    (object) => object.value,
    (collection) => Modelc55CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => value,
  );
  _register<Envelopec55>(
    backend,
    'c55',
    'List<ProbeLeaf?>',
    'nested',
    Envelopec55Schema,
    () => [
      (Envelopec55()
        ..dbId = 1
        ..value = (Payloadc55()
          ..value = (<ProbeLeaf?>[
            (ProbeLeaf()..label = 'á🚀'),
            (ProbeLeaf()..label = null),
            null,
          ]))),
      (Envelopec55()
        ..dbId = 2
        ..value = (Payloadc55()..value = (<ProbeLeaf?>[]))),
      (Envelopec55()
        ..dbId = 3
        ..value = (Payloadc55()..value = (<ProbeLeaf?>[null, null]))),
    ],
    (object) => object.value.value,
    (collection) => Envelopec55CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => (value as Payloadc55).value,
  );
  _register<Modelc56>(
    backend,
    'c56',
    'List<ProbeLeaf>?',
    'root',
    Modelc56Schema,
    () => [
      (Modelc56()
        ..dbId = 1
        ..value = (<ProbeLeaf>[
          (ProbeLeaf()..label = 'á🚀'),
          (ProbeLeaf()..label = null),
        ])),
      (Modelc56()
        ..dbId = 2
        ..value = (<ProbeLeaf>[])),
      (Modelc56()
        ..dbId = 3
        ..value = (null)),
    ],
    (object) => object.value,
    (collection) => Modelc56CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => value,
  );
  _register<Envelopec56>(
    backend,
    'c56',
    'List<ProbeLeaf>?',
    'nested',
    Envelopec56Schema,
    () => [
      (Envelopec56()
        ..dbId = 1
        ..value = (Payloadc56()
          ..value = (<ProbeLeaf>[
            (ProbeLeaf()..label = 'á🚀'),
            (ProbeLeaf()..label = null),
          ]))),
      (Envelopec56()
        ..dbId = 2
        ..value = (Payloadc56()..value = (<ProbeLeaf>[]))),
      (Envelopec56()
        ..dbId = 3
        ..value = (Payloadc56()..value = (null))),
    ],
    (object) => object.value.value,
    (collection) => Envelopec56CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => (value as Payloadc56).value,
  );
  _register<Modelc57>(
    backend,
    'c57',
    'List<ProbeLeaf?>?',
    'root',
    Modelc57Schema,
    () => [
      (Modelc57()
        ..dbId = 1
        ..value = (<ProbeLeaf?>[
          (ProbeLeaf()..label = 'á🚀'),
          (ProbeLeaf()..label = null),
          null,
        ])),
      (Modelc57()
        ..dbId = 2
        ..value = (<ProbeLeaf?>[])),
      (Modelc57()
        ..dbId = 3
        ..value = (null)),
      (Modelc57()
        ..dbId = 4
        ..value = (<ProbeLeaf?>[null, null])),
    ],
    (object) => object.value,
    (collection) => Modelc57CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => value,
  );
  _register<Envelopec57>(
    backend,
    'c57',
    'List<ProbeLeaf?>?',
    'nested',
    Envelopec57Schema,
    () => [
      (Envelopec57()
        ..dbId = 1
        ..value = (Payloadc57()
          ..value = (<ProbeLeaf?>[
            (ProbeLeaf()..label = 'á🚀'),
            (ProbeLeaf()..label = null),
            null,
          ]))),
      (Envelopec57()
        ..dbId = 2
        ..value = (Payloadc57()..value = (<ProbeLeaf?>[]))),
      (Envelopec57()
        ..dbId = 3
        ..value = (Payloadc57()..value = (null))),
      (Envelopec57()
        ..dbId = 4
        ..value = (Payloadc57()..value = (<ProbeLeaf?>[null, null]))),
    ],
    (object) => object.value.value,
    (collection) => Envelopec57CindelQueryModifierAccess(
      collection.all(),
    ).valueProperty().findAll(),
    (value) => (value as Payloadc57).value,
  );
}

Object? _normalize(Object? value) {
  if (value is DateTime) {
    return {'dateTimeMicros': value.microsecondsSinceEpoch};
  }
  if (value is Duration) return {'durationMicros': value.inMicroseconds};
  if (value is Enum) return value.toString();
  if (value is ProbeLeaf) return {'label': value.label};
  if (value is List) return value.map(_normalize).toList();
  return value;
}

void _register<T>(
  CindelStorageBackend backend,
  String id,
  String type,
  String context,
  CindelCollectionSchema<T> schema,
  List<T> Function() create,
  Object? Function(T) valueOf,
  Future<List<Object?>> Function(CindelTypedCollection<T>) projection,
  Object? Function(Object?) projectedValue,
) {
  for (final mode in ['put', 'putAll']) {
    // Scenario: Real generated models traverse each supported storage/read route.
    // Covers: Populated, empty and null values independently at root/embedded depth.
    // Expected: Every route preserves the logical values; record all failures before asserting.
    test('$id $context $type $mode', () async {
      final directory = await createCloseTestDirectory();
      CindelDatabase? db;
      final failures = <String>[];
      Future<bool> check(
        String operation,
        Future<Object?> Function() action,
        Object? expected,
      ) async {
        String? error;
        try {
          expect(await action(), expected);
        } catch (e) {
          error = e.toString();
          failures.add('$operation: $error');
        }
        return error == null;
      }

      try {
        db = await Cindel.open(
          directory: directory,
          backend: backend,
          schemas: [schema],
        );
        var collection = db.typedCollection(schema);
        final objects = create();
        final expected = objects.map((o) => _normalize(valueOf(o))).toList();
        final written = await check('write', () async {
          if (mode == 'put') {
            for (final object in objects) {
              await collection.put(object);
            }
          } else {
            await collection.putAll(objects);
          }
          return null;
        }, null);
        if (written) {
          for (var i = 0; i < objects.length; i++) {
            await check(
              'get/${i + 1}',
              () async => _normalize(valueOf((await collection.get(i + 1))!)),
              expected[i],
            );
          }
          await check(
            'getAll',
            () async => (await collection.getAll([
              for (var i = 1; i <= objects.length; i++) i,
            ])).map((o) => _normalize(valueOf(o as T))).toList(),
            expected,
          );
          await check(
            'findAll',
            () async => (await collection.all().sortBy('dbId').findAll())
                .map((o) => _normalize(valueOf(o)))
                .toList(),
            expected,
          );
          await check(
            'findFirst',
            () async => _normalize(
              valueOf((await collection.all().sortBy('dbId').findFirst())!),
            ),
            expected.first,
          );
          await check(
            'projection',
            () async => (await projection(
              collection,
            )).map((v) => _normalize(projectedValue(v))).toList(),
            expected,
          );
          await db.close();
          db = await Cindel.open(
            directory: directory,
            backend: backend,
            schemas: [schema],
          );
          collection = db.typedCollection(schema);
          await check(
            'reopen/getAll',
            () async => (await collection.getAll([
              for (var i = 1; i <= objects.length; i++) i,
            ])).map((o) => _normalize(valueOf(o as T))).toList(),
            expected,
          );
        }
      } finally {
        await db?.close();
        await deleteCloseTestDirectory(directory);
      }
      expect(failures, isEmpty);
    });
  }
}

void _runControls(CindelStorageBackend backend) {
  // A binary list count can start with '[' (91), as can a compact table (201).
  _register<Modelc20>(
    backend,
    'control_lengths',
    'List<String>',
    'root',
    Modelc20Schema,
    () => [
      for (final (index, count) in [0, 3, 91, 201, 347].indexed)
        Modelc20()
          ..dbId = index + 1
          ..value = List.generate(count, (i) => 'v-$i'),
    ],
    (object) => object.value,
    (collection) => collection.all().valueProperty().findAll(),
    (value) => value,
  );
  _register<Modelc08>(
    backend,
    'control_binary_count',
    'List<int>',
    'root',
    Modelc08Schema,
    () => [
      Modelc08()
        ..dbId = 1
        ..value = List.generate(91, (i) => i),
    ],
    (object) => object.value,
    (collection) => collection.all().valueProperty().findAll(),
    (value) => value,
  );
  _register<Modelc20>(
    backend,
    'control_ascii',
    'List<String>',
    'root',
    Modelc20Schema,
    () => [
      Modelc20()
        ..dbId = 1
        ..value = ['a'],
      Modelc20()
        ..dbId = 2
        ..value = ['a', 'b', 'c'],
      Modelc20()
        ..dbId = 3
        ..value = [],
    ],
    (object) => object.value,
    (collection) => collection.all().valueProperty().findAll(),
    (v) => v,
  );
  _register<ListAfterScalar>(
    backend,
    'control_after',
    'List<String?>',
    'root',
    ListAfterScalarSchema,
    () => [
      ListAfterScalar()
        ..dbId = 1
        ..value = ['a', null],
      ListAfterScalar()
        ..dbId = 2
        ..value = [],
    ],
    (object) => object.value,
    (collection) => collection.all().valueProperty().findAll(),
    (v) => v,
  );
  _register<ListBeforeScalar>(
    backend,
    'control_before',
    'List<String?>',
    'root',
    ListBeforeScalarSchema,
    () => [
      ListBeforeScalar()
        ..dbId = 1
        ..value = ['a', null],
      ListBeforeScalar()
        ..dbId = 2
        ..value = [],
    ],
    (object) => object.value,
    (collection) => collection.all().valueProperty().findAll(),
    (v) => v,
  );
}
