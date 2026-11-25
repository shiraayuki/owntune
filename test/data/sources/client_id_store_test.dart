import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:owntune/data/db/database.dart';
import 'package:owntune/data/sources/soundcloud/client_id_store.dart';

void main() {
  test('the store keeps the client_id in settings_entries', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final store = DbSoundcloudClientIdStore(db);

    expect(await store.read(), isNull);
    await store.write('first');
    expect(await store.read(), 'first');
    await store.write('second');
    expect(await store.read(), 'second');

    final rows = await db.select(db.settingsEntries).get();
    expect(rows.map((r) => (r.key, r.value)), [
      ('soundcloud_client_id', 'second'),
    ]);
  });
}
