import 'dart:ffi';
import 'dart:typed_data' show Uint8List;

import 'package:flat_buffers/flat_buffers.dart' as fb;

import '../common.dart';
import 'bindings.dart';
import 'structs.dart';
import '../modelinfo/index.dart';

class _OBXFBEntity {
  _OBXFBEntity._(this._bc, this._bcOffset);

  static const fb.Reader<_OBXFBEntity> reader = _OBXFBEntityReader();

  factory _OBXFBEntity(final Uint8List bytes) {
    final rootRef = fb.BufferContext.fromBytes(bytes);
    return reader.read(rootRef, 0);
  }

  final fb.BufferContext _bc;
  final int _bcOffset;

  dynamic getProp(propReader, int field) =>
      propReader.vTableGet(_bc, _bcOffset, field);
}

class _OBXFBEntityReader extends fb.TableReader<_OBXFBEntity> {
  const _OBXFBEntityReader();

  @override
  _OBXFBEntity createObject(fb.BufferContext bc, int offset) =>
      _OBXFBEntity._(bc, offset);
}

class OBXFlatbuffersManager<T> {
  final ModelEntity _modelEntity;
  final ObjectWriter<T> _entityBuilder;

  OBXFlatbuffersManager(this._modelEntity, this._entityBuilder);

  OBX_bytes_wrapper marshal(Map<String, dynamic> propVals) {
    var builder = fb.Builder(initialSize: 1024);

    // write all strings
    final offsets = <int, int>{};
    _modelEntity.properties.forEach((ModelProperty p) {
      switch (p.type) {
        case OBXPropertyType.String:
          offsets[p.id.id] = builder.writeString(propVals[p.name]);
          break;
        case OBXPropertyType.StringVector:
          final stringVector = propVals[p.name] as List<String>;
          offsets[p.id.id] = stringVector == null
              ? null
              : builder.writeList(
                  stringVector.map((str) => builder.writeString(str)).toList());
          break;
        case OBXPropertyType.ByteVector:
          final byteVector = propVals[p.name];
          offsets[p.id.id] =
              byteVector == null ? null : builder.writeListInt8(byteVector);
          break;
      }
    });

    // create table and write actual properties
    // TODO: make sure that Id property has a value >= 1
    builder.startTable();
    _modelEntity.properties.forEach((ModelProperty p) {
      final field = p.id.id - 1;
      final value = propVals[p.name];
      switch (p.type) {
        case OBXPropertyType.Bool:
          builder.addBool(field, value);
          break;
        case OBXPropertyType.Char:
          builder.addInt8(field, value);
          break;
        case OBXPropertyType.Byte:
          builder.addUint8(field, value);
          break;
        case OBXPropertyType.Short:
          builder.addInt16(field, value);
          break;
        case OBXPropertyType.Int:
          builder.addInt32(field, value);
          break;
        case OBXPropertyType.Long:
          builder.addInt64(field, value);
          break;
        case OBXPropertyType.Float:
          builder.addFloat32(field, value);
          break;
        case OBXPropertyType.Double:
          builder.addFloat64(field, value);
          break;
        // offset-based fields
        case OBXPropertyType.String:
        case OBXPropertyType.StringVector:
        case OBXPropertyType.ByteVector:
          builder.addOffset(field, offsets[p.id.id] /*!*/);
          break;
        default:
          throw Exception('unsupported type: ${p.type}');
      }
    });

    var endOffset = builder.endTable();
    return OBX_bytes_wrapper.managedCopyOf(builder.finish(endOffset),
        align: true);
  }

  T unmarshal(Pointer<Uint8> dataPtr, int length) {
    // create a no-copy view
    final bytes = dataPtr.asTypedList(length);

    final entity = _OBXFBEntity(bytes);
    final propVals = <String, dynamic>{};

    _modelEntity.properties.forEach((p) {
      var propReader;
      switch (p.type) {
        case OBXPropertyType.Bool:
          propReader = fb.BoolReader();
          break;
        case OBXPropertyType.Char:
          propReader = fb.Int8Reader();
          break;
        case OBXPropertyType.Byte:
          propReader = fb.Int8Reader();
          break;
        case OBXPropertyType.Short:
          propReader = fb.Int16Reader();
          break;
        case OBXPropertyType.Int:
          propReader = fb.Int32Reader();
          break;
        case OBXPropertyType.Long:
          propReader = fb.Int64Reader();
          break;
        case OBXPropertyType.String:
          propReader = fb.StringReader();
          break;
        case OBXPropertyType.Float:
          propReader = fb.Float32Reader();
          break;
        case OBXPropertyType.Double:
          propReader = fb.Float64Reader();
          break;
        case OBXPropertyType.StringVector:
          propReader = const fb.ListReader<String>(fb.StringReader());
          break;
        case OBXPropertyType.ByteVector:
          propReader = const fb.ListReader<int>(fb.Int8Reader());
          break;
        default:
          throw Exception('unsupported type: ${p.type}');
      }

      propVals[p.name] = entity.getProp(propReader, (p.id.id + 1) * 2);
    });

    return _entityBuilder(propVals);
  }

  T /*?*/ unmarshalWithMissing(Pointer<Uint8> dataPtr, int length) {
    if (dataPtr == null || dataPtr.address == 0 || length == 0) {
      return null;
    }
    return unmarshal(dataPtr, length);
  }

  // expects pointer to OBX_bytes_array and manually resolves its contents (see objectbox.h)
  List<T> unmarshalArray(final Pointer<OBX_bytes_array> bytesArray) {
    final result = <T>[];
    result.length = bytesArray.ref.count;

    for (var i = 0; i < bytesArray.ref.count; i++) {
      final bytesPtr = bytesArray.ref.bytes.elementAt(i);
      if (bytesPtr == null || bytesPtr == nullptr || bytesPtr.ref.size == 0) {
        throw ObjectBoxException(
            dartMsg: "can't access data of empty OBX_bytes");
      }
      result[i] = unmarshal(bytesPtr.ref.data.cast<Uint8>(), bytesPtr.ref.size);
    }

    return result;
  }

  // expects pointer to OBX_bytes_array and manually resolves its contents (see objectbox.h)
  List<T /*?*/ > unmarshalArrayWithMissing(
      final Pointer<OBX_bytes_array> bytesArray) {
    final result = <T /*?*/ >[];
    result.length = bytesArray.ref.count;

    for (var i = 0; i < bytesArray.ref.count; i++) {
      final bytesPtr = bytesArray.ref.bytes.elementAt(i);
      if (bytesPtr == null || bytesPtr == nullptr || bytesPtr.ref.size == 0) {
        result[i] = null;
      } else {
        result[i] = unmarshalWithMissing(
            bytesPtr.ref.data.cast<Uint8>(), bytesPtr.ref.size);
      }
    }

    return result;
  }
}
