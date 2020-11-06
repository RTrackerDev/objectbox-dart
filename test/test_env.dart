import 'dart:ffi';
import 'dart:io';
import 'entity.dart';
import 'objectbox.g.dart';

class TestEnv {
  final Directory dir;
  Store store;
  Box<TestEntity> box;

  TestEnv(String name) : dir = Directory('testdata-' + name) {
    if (dir.existsSync()) dir.deleteSync(recursive: true);

    store = Store(getObjectBoxModel(), directory: dir.path);
    box = Box<TestEntity>(store);
  }

  TestEnv.fromPtr(Pointer<Void> cStore) : dir = null {
    store = Store.fromPtr(getObjectBoxModel(), cStore);
    box = Box<TestEntity>(store);
  }

  void close() {
    store.close();
    if (dir != null && dir.existsSync()) dir.deleteSync(recursive: true);
  }
}
