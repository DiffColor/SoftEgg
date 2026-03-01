import 'dart:convert';

class SnapshotDependency {
  const SnapshotDependency({
    required this.id,
    required this.name,
    required this.version,
  });

  final String id;
  final String name;
  final String version;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'version': version,
    };
  }

  factory SnapshotDependency.fromJson(Map<String, dynamic> json) {
    return SnapshotDependency(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      version: json['version'] as String? ?? '',
    );
  }
}

class SnapshotBinaryFile {
  const SnapshotBinaryFile({
    required this.relativePath,
    required this.payloadBase64,
  });

  final String relativePath;
  final String payloadBase64;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'relativePath': relativePath,
      'payloadBase64': payloadBase64,
    };
  }

  factory SnapshotBinaryFile.fromJson(Map<String, dynamic> json) {
    return SnapshotBinaryFile(
      relativePath: json['relativePath'] as String? ?? '',
      payloadBase64: json['payloadBase64'] as String? ?? '',
    );
  }
}

class DependencyOption {
  const DependencyOption({
    required this.id,
    required this.name,
    required this.supportedVersions,
    required this.defaultVersion,
  });

  final String id;
  final String name;
  final List<String> supportedVersions;
  final String defaultVersion;
}

class SoftwareVersionDefinition {
  const SoftwareVersionDefinition({
    required this.version,
    required this.dependencies,
  });

  final String version;
  final List<DependencyOption> dependencies;
}

class SoftwareDefinition {
  const SoftwareDefinition({
    required this.id,
    required this.name,
    required this.versions,
  });

  final String id;
  final String name;
  final List<SoftwareVersionDefinition> versions;
}

class DependencyInstallState {
  const DependencyInstallState({
    required this.id,
    required this.name,
    required this.version,
    required this.installed,
    required this.authExemptByMain,
    required this.authInheritedKey,
  });

  final String id;
  final String name;
  final String version;
  final bool installed;
  final bool authExemptByMain;
  final String? authInheritedKey;

  DependencyInstallState copyWith({
    String? id,
    String? name,
    String? version,
    bool? installed,
    bool? authExemptByMain,
    String? authInheritedKey,
    bool clearAuthKey = false,
  }) {
    return DependencyInstallState(
      id: id ?? this.id,
      name: name ?? this.name,
      version: version ?? this.version,
      installed: installed ?? this.installed,
      authExemptByMain: authExemptByMain ?? this.authExemptByMain,
      authInheritedKey: clearAuthKey
          ? null
          : (authInheritedKey ?? this.authInheritedKey),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'version': version,
      'installed': installed,
      'authExemptByMain': authExemptByMain,
      'authInheritedKey': authInheritedKey,
    };
  }

  factory DependencyInstallState.fromJson(Map<String, dynamic> json) {
    return DependencyInstallState(
      id: json['id'] as String,
      name: json['name'] as String,
      version: json['version'] as String,
      installed: json['installed'] as bool? ?? false,
      authExemptByMain: json['authExemptByMain'] as bool? ?? false,
      authInheritedKey: json['authInheritedKey'] as String?,
    );
  }
}

class InstalledMainSoftware {
  const InstalledMainSoftware({
    required this.installId,
    required this.softwareId,
    required this.softwareName,
    required this.version,
    required this.installedAt,
    required this.authenticated,
    required this.authKey,
    required this.dependencies,
  });

  final String installId;
  final String softwareId;
  final String softwareName;
  final String version;
  final DateTime installedAt;
  final bool authenticated;
  final String? authKey;
  final List<DependencyInstallState> dependencies;

  InstalledMainSoftware copyWith({
    String? installId,
    String? softwareId,
    String? softwareName,
    String? version,
    DateTime? installedAt,
    bool? authenticated,
    String? authKey,
    bool clearAuthKey = false,
    List<DependencyInstallState>? dependencies,
  }) {
    return InstalledMainSoftware(
      installId: installId ?? this.installId,
      softwareId: softwareId ?? this.softwareId,
      softwareName: softwareName ?? this.softwareName,
      version: version ?? this.version,
      installedAt: installedAt ?? this.installedAt,
      authenticated: authenticated ?? this.authenticated,
      authKey: clearAuthKey ? null : (authKey ?? this.authKey),
      dependencies: dependencies ?? this.dependencies,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'installId': installId,
      'softwareId': softwareId,
      'softwareName': softwareName,
      'version': version,
      'installedAt': installedAt.toIso8601String(),
      'authenticated': authenticated,
      'authKey': authKey,
      'dependencies': dependencies.map((e) => e.toJson()).toList(),
    };
  }

  String encodeJson() => jsonEncode(toJson());

  factory InstalledMainSoftware.fromJson(Map<String, dynamic> json) {
    final deps = (json['dependencies'] as List<dynamic>? ?? <dynamic>[])
        .map((e) => DependencyInstallState.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);

    return InstalledMainSoftware(
      installId: json['installId'] as String,
      softwareId: json['softwareId'] as String,
      softwareName: json['softwareName'] as String,
      version: json['version'] as String,
      installedAt:
          DateTime.tryParse(json['installedAt'] as String? ?? '') ??
          DateTime.now(),
      authenticated: json['authenticated'] as bool? ?? false,
      authKey: json['authKey'] as String?,
      dependencies: deps,
    );
  }

  factory InstalledMainSoftware.decodeJson(String source) {
    final decoded = jsonDecode(source) as Map<String, dynamic>;
    return InstalledMainSoftware.fromJson(decoded);
  }
}

class SoftEggSnapshot {
  const SoftEggSnapshot({
    required this.snapshotId,
    required this.partnerCode,
    required this.softwareId,
    required this.softwareName,
    required this.version,
    required this.dependencyVersions,
    required this.dependencies,
    required this.binaryFiles,
    required this.createdAt,
  });

  final String snapshotId;
  final String partnerCode;
  final String softwareId;
  final String softwareName;
  final String version;
  final Map<String, String> dependencyVersions;
  final List<SnapshotDependency> dependencies;
  final List<SnapshotBinaryFile> binaryFiles;
  final DateTime createdAt;

  bool get isOfflineInstallReady => binaryFiles.isNotEmpty;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'snapshotId': snapshotId,
      'partnerCode': partnerCode,
      'softwareId': softwareId,
      'softwareName': softwareName,
      'version': version,
      'dependencyVersions': dependencyVersions,
      'dependencies': dependencies.map((e) => e.toJson()).toList(),
      'binaryFiles': binaryFiles.map((e) => e.toJson()).toList(),
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory SoftEggSnapshot.fromJson(Map<String, dynamic> json) {
    final rawDeps =
        (json['dependencyVersions'] as Map<dynamic, dynamic>? ??
                <dynamic, dynamic>{})
            .cast<dynamic, dynamic>();
    final dependencyVersions = rawDeps.map(
      (key, value) => MapEntry(key.toString(), value.toString()),
    );
    final dependenciesJson =
        (json['dependencies'] as List<dynamic>? ?? <dynamic>[])
            .cast<Map<String, dynamic>>();
    final dependencies = dependenciesJson
        .map(SnapshotDependency.fromJson)
        .toList(growable: false);
    final binaryFilesJson =
        (json['binaryFiles'] as List<dynamic>? ?? <dynamic>[])
            .cast<Map<String, dynamic>>();
    final binaryFiles = binaryFilesJson
        .map(SnapshotBinaryFile.fromJson)
        .toList(growable: false);

    final mergedDependencies = dependencies.isNotEmpty
        ? dependencies
        : dependencyVersions.entries
              .map(
                (entry) => SnapshotDependency(
                  id: entry.key,
                  name: entry.key,
                  version: entry.value,
                ),
              )
              .toList(growable: false);

    return SoftEggSnapshot(
      snapshotId: json['snapshotId'] as String? ?? '',
      partnerCode: json['partnerCode'] as String? ?? '',
      softwareId: json['softwareId'] as String? ?? '',
      softwareName: json['softwareName'] as String? ?? '',
      version: json['version'] as String? ?? '',
      dependencyVersions: dependencyVersions,
      dependencies: mergedDependencies,
      binaryFiles: binaryFiles,
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

class SoftEggSnapshotRef {
  const SoftEggSnapshotRef({
    required this.path,
    required this.fileName,
    required this.modifiedAt,
    required this.bytes,
  });

  final String path;
  final String fileName;
  final DateTime modifiedAt;
  final int bytes;
}
