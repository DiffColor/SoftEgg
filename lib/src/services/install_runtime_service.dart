import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/installer_models.dart';

typedef InstallProgressCallback =
    void Function(String message, double progress);

class InstallRuntimeService {
  SoftEggSnapshot buildSnapshot({
    required String partnerCode,
    required SoftwareDefinition software,
    required SoftwareVersionDefinition version,
    required Map<String, String> selectedDependencyVersions,
    String? snapshotId,
    DateTime? createdAt,
  }) {
    final bundle = _buildBundle(
      software: software,
      version: version,
      selectedDependencyVersions: selectedDependencyVersions,
    );

    final dependencies = bundle.dependencies
        .map(
          (dep) => SnapshotDependency(
            id: dep.id,
            name: dep.name,
            version: dep.version,
          ),
        )
        .toList(growable: false);

    final dependencyVersions = <String, String>{
      for (final dep in dependencies) dep.id: dep.version,
    };

    final binaryFiles = bundle.files
        .map(
          (file) => SnapshotBinaryFile(
            relativePath: file.relativePath,
            payloadBase64: base64Encode(file.bytes),
          ),
        )
        .toList(growable: false);

    return SoftEggSnapshot(
      snapshotId: snapshotId ?? _createSnapshotId(software.id),
      partnerCode: partnerCode,
      softwareId: software.id,
      softwareName: software.name,
      version: version.version,
      dependencyVersions: dependencyVersions,
      dependencies: dependencies,
      binaryFiles: binaryFiles,
      createdAt: createdAt ?? DateTime.now(),
    );
  }

  Future<InstalledMainSoftware> install({
    required SoftwareDefinition software,
    required SoftwareVersionDefinition version,
    required Map<String, String> selectedDependencyVersions,
    required InstallProgressCallback onProgress,
    InstalledMainSoftware? existing,
  }) async {
    final root = await _resolveRoot();
    final installId = existing?.installId ?? _createInstallId(software.id);
    final bundle = _buildBundle(
      software: software,
      version: version,
      selectedDependencyVersions: selectedDependencyVersions,
    );

    onProgress('파일 배치 준비 중...', 0.15);
    final packageDir = Directory(p.join(root.path, installId));
    await packageDir.create(recursive: true);

    onProgress('메인 바이너리 복사 중...', 0.30);
    await _writeBundleFiles(packageDir.path, bundle.files);

    onProgress('SW 등록 중...', 0.65);
    onProgress('바로가기 구성 중...', 0.82);
    await _writeShortcutPlaceholder(root.path, software.name, installId);

    onProgress('설치 마무리 중...', 1.0);
    await Future<void>.delayed(const Duration(milliseconds: 250));

    return InstalledMainSoftware(
      installId: installId,
      softwareId: software.id,
      softwareName: software.name,
      version: version.version,
      installedAt: DateTime.now(),
      authenticated: existing?.authenticated ?? false,
      authKey: existing?.authKey,
      dependencies: bundle.dependencies,
    );
  }

  Future<InstalledMainSoftware> installFromSnapshot({
    required SoftEggSnapshot snapshot,
    required InstallProgressCallback onProgress,
    InstalledMainSoftware? existing,
  }) async {
    if (!snapshot.isOfflineInstallReady) {
      throw StateError('오프라인 설치가 가능한 바이너리가 스냅샷에 없습니다.');
    }

    final root = await _resolveRoot();
    final installId = existing?.installId ?? _createInstallId(snapshot.softwareId);

    onProgress('오프라인 패키지 준비 중...', 0.15);
    final packageDir = Directory(p.join(root.path, installId));
    await packageDir.create(recursive: true);

    onProgress('바이너리 배치 중...', 0.55);
    for (final file in snapshot.binaryFiles) {
      final target = File(p.join(packageDir.path, file.relativePath));
      await target.parent.create(recursive: true);
      await target.writeAsBytes(base64Decode(file.payloadBase64), flush: true);
    }

    onProgress('바로가기 구성 중...', 0.82);
    await _writeShortcutPlaceholder(root.path, snapshot.softwareName, installId);

    onProgress('설치 마무리 중...', 1.0);
    await Future<void>.delayed(const Duration(milliseconds: 250));

    final dependencies = snapshot.dependencies.isNotEmpty
        ? snapshot.dependencies
              .map(
                (dep) => DependencyInstallState(
                  id: dep.id,
                  name: dep.name,
                  version: dep.version,
                  installed: true,
                  authExemptByMain: false,
                  authInheritedKey: null,
                ),
              )
              .toList(growable: false)
        : snapshot.dependencyVersions.entries
              .map(
                (entry) => DependencyInstallState(
                  id: entry.key,
                  name: entry.key,
                  version: entry.value,
                  installed: true,
                  authExemptByMain: false,
                  authInheritedKey: null,
                ),
              )
              .toList(growable: false);

    return InstalledMainSoftware(
      installId: installId,
      softwareId: snapshot.softwareId,
      softwareName: snapshot.softwareName,
      version: snapshot.version,
      installedAt: DateTime.now(),
      authenticated: existing?.authenticated ?? false,
      authKey: existing?.authKey,
      dependencies: dependencies,
    );
  }

  Future<void> remove({
    required InstalledMainSoftware target,
    required InstallProgressCallback onProgress,
  }) async {
    final root = await _resolveRoot();
    final packageDir = Directory(p.join(root.path, target.installId));

    onProgress('설치 데이터 제거 중...', 0.3);
    if (await packageDir.exists()) {
      await packageDir.delete(recursive: true);
    }

    onProgress('바로가기 정리 중...', 0.7);
    final shortcut = File(
      p.join(root.path, 'shortcuts', '${target.installId}.shortcut'),
    );
    if (await shortcut.exists()) {
      await shortcut.delete();
    }

    onProgress('제거 완료', 1.0);
  }

  _RuntimeBundle _buildBundle({
    required SoftwareDefinition software,
    required SoftwareVersionDefinition version,
    required Map<String, String> selectedDependencyVersions,
  }) {
    final dependencies = <DependencyInstallState>[];
    final files = <_RuntimeBundleFile>[];

    files.add(
      _RuntimeBundleFile(
        relativePath: p.join('main', '${software.id}_${version.version}.bin'),
        bytes: utf8.encode('Main binary ${software.id} ${version.version}'),
      ),
    );

    for (final dep in version.dependencies) {
      final pickedVersion =
          selectedDependencyVersions[dep.id] ?? dep.defaultVersion;
      dependencies.add(
        DependencyInstallState(
          id: dep.id,
          name: dep.name,
          version: pickedVersion,
          installed: true,
          authExemptByMain: false,
          authInheritedKey: null,
        ),
      );
      files.add(
        _RuntimeBundleFile(
          relativePath: p.join('deps', '${dep.id}_$pickedVersion.bin'),
          bytes: utf8.encode('Dependency binary ${dep.id} $pickedVersion'),
        ),
      );
    }

    final depLines = dependencies
        .map((d) => '${d.id},${d.name},${d.version}')
        .join('\n');
    files.add(
      _RuntimeBundleFile(
        relativePath: 'install_manifest.txt',
        bytes: utf8.encode(
          'softwareId=${software.id}\n'
          'softwareName=${software.name}\n'
          'version=${version.version}\n'
          '$depLines\n',
        ),
      ),
    );

    return _RuntimeBundle(dependencies: dependencies, files: files);
  }

  Future<void> _writeBundleFiles(
    String packageRoot,
    List<_RuntimeBundleFile> files,
  ) async {
    for (final file in files) {
      final target = File(p.join(packageRoot, file.relativePath));
      await target.parent.create(recursive: true);
      await target.writeAsBytes(file.bytes, flush: true);
    }
  }

  Future<Directory> _resolveRoot() async {
    final supportDir = await getApplicationSupportDirectory();
    final root = Directory(p.join(supportDir.path, 'installhub', 'runtime'));
    await root.create(recursive: true);
    return root;
  }

  Future<void> _writeShortcutPlaceholder(
    String rootPath,
    String softwareName,
    String installId,
  ) async {
    final shortcut = File(p.join(rootPath, 'shortcuts', '$installId.shortcut'));
    await shortcut.parent.create(recursive: true);
    await shortcut.writeAsString('shortcut=$softwareName');
  }

  String _createInstallId(String softwareId) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final normalized = softwareId.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
    return '${normalized}_$now';
  }

  String _createSnapshotId(String softwareId) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final normalized = softwareId.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
    return 'SEGG_${normalized}_$now';
  }
}

class _RuntimeBundle {
  const _RuntimeBundle({required this.dependencies, required this.files});

  final List<DependencyInstallState> dependencies;
  final List<_RuntimeBundleFile> files;
}

class _RuntimeBundleFile {
  const _RuntimeBundleFile({required this.relativePath, required this.bytes});

  final String relativePath;
  final List<int> bytes;
}
