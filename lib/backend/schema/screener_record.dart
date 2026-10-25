import 'dart:async';

import 'package:collection/collection.dart';

import '/backend/schema/util/firestore_util.dart';
import '/backend/schema/util/schema_util.dart';

import 'index.dart';
import '/flutter_flow/flutter_flow_util.dart';

class ScreenerRecord extends FirestoreRecord {
  ScreenerRecord._(
    DocumentReference reference,
    Map<String, dynamic> data,
  ) : super(reference, data) {
    _initializeFields();
  }

  // "data" field.
  String? _data;
  String get data => _data ?? '';
  bool hasData() => _data != null;

  void _initializeFields() {
    _data = snapshotData['data'] as String?;
  }

  static CollectionReference get collection =>
      FirebaseFirestore.instance.collection('screener');

  static Stream<ScreenerRecord> getDocument(DocumentReference ref) =>
      ref.snapshots().map((s) => ScreenerRecord.fromSnapshot(s));

  static Future<ScreenerRecord> getDocumentOnce(DocumentReference ref) =>
      ref.get().then((s) => ScreenerRecord.fromSnapshot(s));

  static ScreenerRecord fromSnapshot(DocumentSnapshot snapshot) =>
      ScreenerRecord._(
        snapshot.reference,
        mapFromFirestore(snapshot.data() as Map<String, dynamic>),
      );

  static ScreenerRecord getDocumentFromData(
    Map<String, dynamic> data,
    DocumentReference reference,
  ) =>
      ScreenerRecord._(reference, mapFromFirestore(data));

  @override
  String toString() =>
      'ScreenerRecord(reference: ${reference.path}, data: $snapshotData)';

  @override
  int get hashCode => reference.path.hashCode;

  @override
  bool operator ==(other) =>
      other is ScreenerRecord && reference.path == other.reference.path;
}

Map<String, dynamic> createScreenerRecordData({
  String? data,
}) {
  final firestoreData = mapToFirestore(
    <String, dynamic>{
      'data': data,
    }.withoutNulls,
  );

  return firestoreData;
}

class ScreenerRecordDocumentEquality implements Equality<ScreenerRecord> {
  const ScreenerRecordDocumentEquality();

  @override
  bool equals(ScreenerRecord? e1, ScreenerRecord? e2) {
    return e1?.data == e2?.data;
  }

  @override
  int hash(ScreenerRecord? e) => const ListEquality().hash([e?.data]);

  @override
  bool isValidKey(Object? o) => o is ScreenerRecord;
}
