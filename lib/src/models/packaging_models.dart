import 'dart:convert';

class CompanyCatalog {
  const CompanyCatalog({required this.company, required this.softwarePackages});

  factory CompanyCatalog.fromJson(Map<String, dynamic> json) {
    return CompanyCatalog(
      company: CompanyInfo.fromJson(
        (json['company'] as Map?)?.cast<String, dynamic>() ??
            <String, dynamic>{},
      ),
      softwarePackages: ((json['softwarePackages'] as List?) ?? const [])
          .map(
            (item) => RemoteSoftwarePackage.fromJson(
              (item as Map).cast<String, dynamic>(),
            ),
          )
          .toList(growable: false),
    );
  }

  final CompanyInfo company;
  final List<RemoteSoftwarePackage> softwarePackages;

  List<SoftwareGroupViewModel> buildGroups() {
    final groups = <String, List<RemoteSoftwarePackage>>{};
    for (final item in softwarePackages) {
      final key =
          '${item.name}|${item.codeName}|${item.os.toLowerCase()}|${item.releaseChannel.toLowerCase()}';
      groups.putIfAbsent(key, () => <RemoteSoftwarePackage>[]).add(item);
    }

    final results = groups.entries
        .map((entry) {
          final packages = [...entry.value]
            ..sort((a, b) => compareVersionDescending(a.version, b.version));
          final first = packages.first;
          return SoftwareGroupViewModel(
            id: entry.key,
            name: first.name,
            codeName: first.codeName,
            os: first.os,
            releaseChannel: first.releaseChannel,
            packages: packages,
          );
        })
        .toList(growable: false);

    results.sort((a, b) {
      final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      if (byName != 0) {
        return byName;
      }
      return a.codeName.toLowerCase().compareTo(b.codeName.toLowerCase());
    });
    return results;
  }
}

class CompanyInfo {
  const CompanyInfo({
    required this.companyNodeId,
    required this.companyName,
    required this.companyCode,
    required this.issuedAt,
    required this.expiresAt,
  });

  factory CompanyInfo.fromJson(Map<String, dynamic> json) {
    return CompanyInfo(
      companyNodeId: (json['companyNodeId'] ?? '').toString(),
      companyName: (json['companyName'] ?? '').toString(),
      companyCode: (json['companyCode'] ?? '').toString(),
      issuedAt: DateTime.tryParse((json['issuedAt'] ?? '').toString()),
      expiresAt: DateTime.tryParse((json['expiresAt'] ?? '').toString()),
    );
  }

  final String companyNodeId;
  final String companyName;
  final String companyCode;
  final DateTime? issuedAt;
  final DateTime? expiresAt;
}

class RemoteSoftwarePackage {
  const RemoteSoftwarePackage({
    required this.id,
    required this.name,
    required this.codeName,
    required this.productId,
    required this.version,
    required this.os,
    required this.releaseChannel,
    required this.price,
    required this.mainBinary,
    required this.dependencies,
    required this.installOptions,
  });

  factory RemoteSoftwarePackage.fromJson(Map<String, dynamic> json) {
    return RemoteSoftwarePackage(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      codeName: (json['codeName'] ?? '').toString(),
      productId: _parseInt(json['productId']),
      version: (json['version'] ?? '').toString(),
      os: (json['os'] ?? 'all').toString(),
      releaseChannel: (json['releaseChannel'] ?? 'stable').toString(),
      price: _parseDouble(json['price']),
      mainBinary: RemoteSoftwareBinary.fromJson(
        (json['mainBinary'] as Map?)?.cast<String, dynamic>() ??
            <String, dynamic>{},
      ),
      dependencies: ((json['dependencies'] as List?) ?? const [])
          .map(
            (item) => RemoteSoftwareBinary.fromJson(
              (item as Map).cast<String, dynamic>(),
            ),
          )
          .toList(growable: false),
      installOptions: RemoteInstallOptions.fromJson(
        (json['installOptions'] as Map?)?.cast<String, dynamic>() ??
            <String, dynamic>{},
      ),
    );
  }

  final String id;
  final String name;
  final String codeName;
  final int productId;
  final String version;
  final String os;
  final String releaseChannel;
  final double price;
  final RemoteSoftwareBinary mainBinary;
  final List<RemoteSoftwareBinary> dependencies;
  final RemoteInstallOptions installOptions;

  bool get hasMissingDependencyUri {
    return dependencies.any((item) => !item.hasUri);
  }

  bool get canPackage {
    return mainBinary.hasUri && !hasMissingDependencyUri;
  }
}

class RemoteSoftwareBinary {
  const RemoteSoftwareBinary({
    required this.name,
    required this.version,
    required this.uri,
    required this.checksum,
  });

  factory RemoteSoftwareBinary.fromJson(Map<String, dynamic> json) {
    return RemoteSoftwareBinary(
      name: (json['name'] ?? '').toString(),
      version: (json['version'] ?? '').toString(),
      uri: (json['uri'] ?? '').toString(),
      checksum: (json['checksum'] ?? '').toString(),
    );
  }

  final String name;
  final String version;
  final String uri;
  final String checksum;

  bool get hasUri => uri.trim().isNotEmpty;

  String get fileName {
    if (name.trim().isNotEmpty) {
      return name.trim();
    }
    if (!hasUri) {
      return 'unknown.bin';
    }
    final parsed = Uri.tryParse(uri.trim());
    final lastSegment = parsed?.pathSegments.isNotEmpty == true
        ? parsed!.pathSegments.last
        : 'unknown.bin';
    return Uri.decodeComponent(lastSegment);
  }
}

class RemoteInstallOptions {
  const RemoteInstallOptions({
    required this.desktopShortcuts,
    required this.startupPrograms,
    required this.shortcutName,
    required this.desktopShortcutTargets,
    required this.startupTargets,
  });

  factory RemoteInstallOptions.fromJson(Map<String, dynamic> json) {
    return RemoteInstallOptions(
      desktopShortcuts: ((json['desktopShortcuts'] as List?) ?? const [])
          .map(
            (item) => RemoteInstallEntry.fromJson(
              (item as Map).cast<String, dynamic>(),
            ),
          )
          .toList(growable: false),
      startupPrograms: ((json['startupPrograms'] as List?) ?? const [])
          .map(
            (item) => RemoteInstallEntry.fromJson(
              (item as Map).cast<String, dynamic>(),
            ),
          )
          .toList(growable: false),
      shortcutName: (json['shortcutName'] ?? '').toString(),
      desktopShortcutTargets:
          ((json['desktopShortcutTargets'] as List?) ?? const [])
              .map((item) => item.toString())
              .toList(growable: false),
      startupTargets: ((json['startupTargets'] as List?) ?? const [])
          .map((item) => item.toString())
          .toList(growable: false),
    );
  }

  final List<RemoteInstallEntry> desktopShortcuts;
  final List<RemoteInstallEntry> startupPrograms;
  final String shortcutName;
  final List<String> desktopShortcutTargets;
  final List<String> startupTargets;

  bool get isEmpty {
    return desktopShortcuts.isEmpty &&
        startupPrograms.isEmpty &&
        desktopShortcutTargets.isEmpty &&
        startupTargets.isEmpty &&
        shortcutName.trim().isEmpty;
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'desktopShortcuts': desktopShortcuts
          .map((item) => item.toJson())
          .toList(),
      'startupPrograms': startupPrograms.map((item) => item.toJson()).toList(),
      'shortcutName': shortcutName,
      'desktopShortcutTargets': desktopShortcutTargets,
      'startupTargets': startupTargets,
    };
  }
}

class RemoteInstallEntry {
  const RemoteInstallEntry({required this.target, required this.name});

  factory RemoteInstallEntry.fromJson(Map<String, dynamic> json) {
    return RemoteInstallEntry(
      target: (json['target'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
    );
  }

  final String target;
  final String name;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{'target': target, 'name': name};
  }

  String get displayName {
    if (name.trim().isNotEmpty) {
      return name.trim();
    }
    if (target.trim().isNotEmpty) {
      return target.trim();
    }
    return 'Unnamed Entry';
  }
}

class SoftwareGroupViewModel {
  const SoftwareGroupViewModel({
    required this.id,
    required this.name,
    required this.codeName,
    required this.os,
    required this.releaseChannel,
    required this.packages,
  });

  final String id;
  final String name;
  final String codeName;
  final String os;
  final String releaseChannel;
  final List<RemoteSoftwarePackage> packages;

  bool get hasPackagableVersion => packages.any((item) => item.canPackage);
}

class PackagingArtifactRecord {
  const PackagingArtifactRecord({
    required this.kind,
    required this.fileName,
    required this.archivePath,
    required this.checksum,
    required this.sizeBytes,
  });

  final String kind;
  final String fileName;
  final String archivePath;
  final String checksum;
  final int sizeBytes;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'kind': kind,
      'fileName': fileName,
      'archivePath': archivePath,
      'checksum': checksum,
      'sizeBytes': sizeBytes,
    };
  }
}

class PackagingResult {
  const PackagingResult({
    required this.packageFilePath,
    required this.packageFileName,
    required this.packageSizeBytes,
    required this.mainArtifact,
    required this.dependencyArtifacts,
    required this.generatedAt,
    required this.installOptions,
    required this.company,
    required this.selectedPackage,
  });

  final String packageFilePath;
  final String packageFileName;
  final int packageSizeBytes;
  final PackagingArtifactRecord mainArtifact;
  final List<PackagingArtifactRecord> dependencyArtifacts;
  final DateTime generatedAt;
  final RemoteInstallOptions installOptions;
  final CompanyInfo company;
  final RemoteSoftwarePackage selectedPackage;

  Map<String, dynamic> toManifestJson() {
    return <String, dynamic>{
      'company': <String, dynamic>{
        'companyNodeId': company.companyNodeId,
        'companyName': company.companyName,
        'companyCode': company.companyCode,
        'issuedAt': company.issuedAt?.toIso8601String(),
        'expiresAt': company.expiresAt?.toIso8601String(),
      },
      'softwarePackage': <String, dynamic>{
        'id': selectedPackage.id,
        'name': selectedPackage.name,
        'codeName': selectedPackage.codeName,
        'productId': selectedPackage.productId,
        'version': selectedPackage.version,
        'os': selectedPackage.os,
        'releaseChannel': selectedPackage.releaseChannel,
        'price': selectedPackage.price,
      },
      'mainArtifact': mainArtifact.toJson(),
      'dependencyArtifacts': dependencyArtifacts
          .map((item) => item.toJson())
          .toList(),
      'installOptions': installOptions.toJson(),
      'packageFileName': packageFileName,
      'generatedAt': generatedAt.toIso8601String(),
      'tool': <String, dynamic>{
        'name': 'SoftEgg Packaging Tool',
        'schemaVersion': 1,
      },
    };
  }

  String toPrettyManifestJson() {
    return const JsonEncoder.withIndent('  ').convert(toManifestJson());
  }
}

int compareVersionDescending(String left, String right) {
  final leftTokens = _tokenizeVersion(left);
  final rightTokens = _tokenizeVersion(right);
  final maxLength = leftTokens.length > rightTokens.length
      ? leftTokens.length
      : rightTokens.length;

  for (var index = 0; index < maxLength; index++) {
    final leftToken = index < leftTokens.length ? leftTokens[index] : '0';
    final rightToken = index < rightTokens.length ? rightTokens[index] : '0';

    final leftNumber = int.tryParse(leftToken);
    final rightNumber = int.tryParse(rightToken);
    if (leftNumber != null && rightNumber != null) {
      if (leftNumber != rightNumber) {
        return rightNumber.compareTo(leftNumber);
      }
      continue;
    }

    final comparison = rightToken.toLowerCase().compareTo(
      leftToken.toLowerCase(),
    );
    if (comparison != 0) {
      return comparison;
    }
  }

  return 0;
}

List<String> _tokenizeVersion(String value) {
  return value
      .split(RegExp(r'[^A-Za-z0-9]+'))
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

int _parseInt(Object? value) {
  if (value is int) {
    return value;
  }
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

double _parseDouble(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  return double.tryParse(value?.toString() ?? '') ?? 0;
}
