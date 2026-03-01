import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/installer_models.dart';

class SoftEggSnapshotService {
  Future<List<SoftEggSnapshotRef>> listSnapshots() async {
    final dir = await _resolveSnapshotDir();
    if (!await dir.exists()) {
      return <SoftEggSnapshotRef>[];
    }

    final refs = <SoftEggSnapshotRef>[];
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) {
        continue;
      }
      if (!entity.path.toLowerCase().endsWith('.segg')) {
        continue;
      }

      final stat = await entity.stat();
      refs.add(
        SoftEggSnapshotRef(
          path: entity.path,
          fileName: p.basename(entity.path),
          modifiedAt: stat.modified,
          bytes: stat.size,
        ),
      );
    }

    refs.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
    return refs;
  }

  Future<SoftEggSnapshotRef> saveSnapshot(SoftEggSnapshot snapshot) async {
    final dir = await _resolveSnapshotDir();
    await dir.create(recursive: true);

    final stamp = snapshot.createdAt.toIso8601String().replaceAll(':', '-');
    final safeSoftwareId = snapshot.softwareId.replaceAll(
      RegExp(r'[^a-zA-Z0-9_-]'),
      '_',
    );
    final fileName = '${safeSoftwareId}_$stamp.segg';
    final target = File(p.join(dir.path, fileName));

    final jsonPayload = jsonEncode(snapshot.toJson());
    final compressed = GZipCodec().encode(utf8.encode(jsonPayload));
    await target.writeAsBytes(compressed, flush: true);

    final stat = await target.stat();
    return SoftEggSnapshotRef(
      path: target.path,
      fileName: p.basename(target.path),
      modifiedAt: stat.modified,
      bytes: stat.size,
    );
  }

  Future<SoftEggSnapshot> loadSnapshot(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw StateError('스냅샷 파일을 찾지 못했습니다: $filePath');
    }

    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      throw StateError('스냅샷 파일이 비어 있습니다.');
    }

    String decoded;
    try {
      decoded = utf8.decode(GZipCodec().decode(bytes));
    } catch (_) {
      decoded = utf8.decode(bytes);
    }

    final map = jsonDecode(decoded) as Map<String, dynamic>;
    return SoftEggSnapshot.fromJson(map);
  }

  Future<Directory> _resolveSnapshotDir() async {
    final support = await getApplicationSupportDirectory();
    return Directory(p.join(support.path, 'installhub', 'softegg_snapshots'));
  }
}
