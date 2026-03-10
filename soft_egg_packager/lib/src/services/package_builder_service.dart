import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:soft_egg_packager/src/models/packaging_models.dart';
import 'package:soft_egg_packager/src/services/checksum_service.dart';
import 'package:soft_egg_packager/src/services/ftp_download_service.dart';
import 'package:soft_egg_packager/src/services/local_settings_service.dart';

typedef PackagingProgressCallback =
    void Function(PackagingProgressUpdate update);

class PackagingProgressUpdate {
  const PackagingProgressUpdate({
    required this.progress,
    required this.task,
    required this.level,
    required this.message,
    this.loggable = true,
    this.processedBytes,
    this.totalBytes,
    this.bytesPerSecond,
    this.clearMetrics = false,
  });

  final double progress;
  final String task;
  final String level;
  final String message;
  final bool loggable;
  final int? processedBytes;
  final int? totalBytes;
  final double? bytesPerSecond;
  final bool clearMetrics;
}

class PackageBuilderService {
  const PackageBuilderService({
    required FtpDownloadService ftpDownloadService,
    required ChecksumService checksumService,
  }) : _ftpDownloadService = ftpDownloadService,
       _checksumService = checksumService;

  final FtpDownloadService _ftpDownloadService;
  final ChecksumService _checksumService;

  Future<PackagingResult> build({
    required SoftEggSettings settings,
    required CompanyInfo company,
    required RemoteSoftwarePackage softwarePackage,
    required List<RemoteSoftwareBinary> selectedDependencies,
    required PackagingProgressCallback onProgress,
  }) async {
    final blocker = settings.packagingBlocker;
    if (blocker != null) {
      throw PackageBuildException(blocker);
    }
    if (!softwarePackage.mainBinary.hasUri) {
      throw const PackageBuildException('메인 바이너리 경로가 없어 패키징할 수 없습니다.');
    }
    if (selectedDependencies.any((item) => !item.hasUri)) {
      throw const PackageBuildException('의존성 중 다운로드 경로가 비어 있는 항목이 있습니다.');
    }

    final tempRoot = await Directory.systemTemp.createTemp('softegg_build_');
    try {
      final exportDirectory = await _prepareExportDirectory(settings);
      final allArtifacts = <RemoteSoftwareBinary>[
        softwarePackage.mainBinary,
        ...selectedDependencies,
      ];
      final artifactSizes = await _resolveArtifactSizes(
        binaries: allArtifacts,
        settings: settings,
        onProgress: onProgress,
      );
      final artifactSlices = _buildArtifactSlices(
        binaries: allArtifacts,
        artifactSizes: artifactSizes,
        phaseStart: 0.05,
        phaseEnd: 0.97,
        minimumSliceSpan: 0.02,
      );
      final payloadRoot = Directory(p.join(tempRoot.path, 'payload'))
        ..createSync(recursive: true);
      final mainDirectory = Directory(p.join(payloadRoot.path, 'main'))
        ..createSync(recursive: true);
      final dependencyDirectory = Directory(
        p.join(payloadRoot.path, 'dependencies'),
      )..createSync(recursive: true);

      onProgress(
        const PackagingProgressUpdate(
          progress: 0.02,
          task: '작업 디렉터리 준비',
          level: 'INFO',
          message: '임시 작업 디렉터리를 구성했습니다.',
          clearMetrics: true,
        ),
      );

      final mainFile = await _downloadArtifact(
        binary: softwarePackage.mainBinary,
        destinationDirectory: mainDirectory,
        settings: settings,
        progressStart: artifactSlices[softwarePackage.mainBinary.uri.trim()]!.$1,
        progressEnd: artifactSlices[softwarePackage.mainBinary.uri.trim()]!.$2,
        onProgress: onProgress,
        labelPrefix: '메인 바이너리',
      );

      final dependencyArtifacts = <PackagingArtifactRecord>[];
      if (selectedDependencies.isNotEmpty) {
        for (var index = 0; index < selectedDependencies.length; index++) {
          final dependency = selectedDependencies[index];
          final dependencySlice = artifactSlices[dependency.uri.trim()]!;
          final artifact = await _downloadArtifact(
            binary: dependency,
            destinationDirectory: dependencyDirectory,
            settings: settings,
            progressStart: dependencySlice.$1,
            progressEnd: dependencySlice.$2,
            onProgress: onProgress,
            labelPrefix: '의존성 ${index + 1}/${selectedDependencies.length}',
          );
          dependencyArtifacts.add(artifact);
        }
      } else {
        onProgress(
          const PackagingProgressUpdate(
            progress: 0.97,
            task: '의존성 없음',
            level: 'INFO',
            message: '선택된 의존성이 없어 다음 단계로 진행합니다.',
            clearMetrics: true,
          ),
        );
      }

      final generatedAt = DateTime.now();
      final manifestFile = File(p.join(payloadRoot.path, 'manifest.json'));
      final packageFileName = _buildPackageFileName(
        softwarePackage,
        generatedAt,
      );
      final packageFilePath = p.join(exportDirectory.path, packageFileName);
      final tempPackageFilePath = p.join(tempRoot.path, packageFileName);
      await _ensurePackageFileWritable(packageFilePath);

      onProgress(
        const PackagingProgressUpdate(
          progress: 0.975,
          task: '매니페스트 생성',
          level: 'INFO',
          message: '패키지 내부 매니페스트를 작성합니다.',
          clearMetrics: true,
        ),
      );

      final result = PackagingResult(
        packageFilePath: packageFilePath,
        packageFileName: packageFileName,
        packageSizeBytes: 0,
        mainArtifact: mainFile,
        dependencyArtifacts: dependencyArtifacts,
        generatedAt: generatedAt,
        installOptions: softwarePackage.installOptions,
        company: company,
        selectedPackage: softwarePackage,
      );
      await manifestFile.writeAsString(result.toPrettyManifestJson());

      onProgress(
        const PackagingProgressUpdate(
          progress: 0.985,
          task: '.segg 생성',
          level: 'INFO',
          message: '압축 아카이브를 생성합니다.',
          clearMetrics: true,
        ),
      );

      final encoder = ZipFileEncoder();
      try {
        encoder.create(tempPackageFilePath);
        await encoder.addDirectory(
          payloadRoot,
          includeDirName: false,
          onProgress: (progress) {
            onProgress(
              PackagingProgressUpdate(
                progress: (0.985 + (progress * 0.01)).clamp(0.985, 0.995),
                task: '.segg 생성 중',
                level: 'INFO',
                message:
                    '아카이브 구성 ${((progress * 100).clamp(0, 100)).round()}%',
                loggable: false,
                clearMetrics: true,
              ),
            );
          },
        );
      } on PathAccessException catch (error) {
        throw PackageBuildException(
          '패키지 파일 생성에 실패했습니다: ${error.path ?? packageFilePath}',
        );
      } on FileSystemException catch (error) {
        throw PackageBuildException(
          '패키지 파일 생성에 실패했습니다: ${error.path ?? packageFilePath}',
        );
      } finally {
        try {
          await encoder.close();
        } catch (_) {
          // ignore close failures after archive creation errors
        }
      }

      onProgress(
        const PackagingProgressUpdate(
          progress: 0.996,
          task: '패키지 배치',
          level: 'INFO',
          message: '생성된 패키지를 출력 폴더로 이동합니다.',
          clearMetrics: true,
        ),
      );

      await _placePackageFile(
        sourcePath: tempPackageFilePath,
        destinationPath: packageFilePath,
      );

      final packageFile = File(packageFilePath);
      final packageSizeBytes = await packageFile.length();
      final completedResult = PackagingResult(
        packageFilePath: packageFilePath,
        packageFileName: packageFileName,
        packageSizeBytes: packageSizeBytes,
        mainArtifact: mainFile,
        dependencyArtifacts: dependencyArtifacts,
        generatedAt: generatedAt,
        installOptions: softwarePackage.installOptions,
        company: company,
        selectedPackage: softwarePackage,
      );

      onProgress(
        PackagingProgressUpdate(
          progress: 1,
          task: '패키징 완료',
          level: 'DONE',
          message: '패키지를 생성했습니다: $packageFileName',
          clearMetrics: true,
        ),
      );
      return completedResult;
    } finally {
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    }
  }

  Future<Directory> _prepareExportDirectory(SoftEggSettings settings) async {
    final directory = Directory(settings.exportRootPath);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    await _ensureDirectoryWritable(directory);
    return directory;
  }

  Future<void> _ensureDirectoryWritable(Directory directory) async {
    final probeFile = File(
      p.join(
        directory.path,
        '.softegg-write-probe-${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    try {
      await probeFile.writeAsString('probe', flush: true);
    } on PathAccessException catch (error) {
      throw PackageBuildException(
        '출력 폴더에 쓸 수 없습니다: ${error.path ?? directory.path}',
      );
    } on FileSystemException catch (error) {
      throw PackageBuildException(
        '출력 폴더에 쓸 수 없습니다: ${error.path ?? directory.path}',
      );
    } finally {
      if (await probeFile.exists()) {
        try {
          await probeFile.delete();
        } catch (_) {
          // ignore cleanup failures for probe files
        }
      }
    }
  }

  Future<void> _ensurePackageFileWritable(String packageFilePath) async {
    final packageFile = File(packageFilePath);
    if (await packageFile.exists()) {
      try {
        await packageFile.delete();
      } on PathAccessException catch (error) {
        throw PackageBuildException(
          '기존 패키지 파일을 덮어쓸 수 없습니다: ${error.path ?? packageFilePath}',
        );
      } on FileSystemException catch (error) {
        throw PackageBuildException(
          '기존 패키지 파일을 덮어쓸 수 없습니다: ${error.path ?? packageFilePath}',
        );
      }
    }
  }

  Future<void> _placePackageFile({
    required String sourcePath,
    required String destinationPath,
  }) async {
    final sourceFile = File(sourcePath);
    final destinationFile = File(destinationPath);
    try {
      await sourceFile.rename(destinationPath);
      return;
    } on FileSystemException {
      // fall through to copy for cross-device moves or sandbox rename issues
    }

    try {
      await sourceFile.copy(destinationPath);
    } on PathAccessException catch (error) {
      throw PackageBuildException(
        '패키지 파일을 출력 폴더에 배치하지 못했습니다: ${error.path ?? destinationPath}',
      );
    } on FileSystemException catch (error) {
      throw PackageBuildException(
        '패키지 파일을 출력 폴더에 배치하지 못했습니다: ${error.path ?? destinationPath}',
      );
    }

    if (await destinationFile.exists()) {
      try {
        await sourceFile.delete();
      } catch (_) {
        // keep copied destination even if temp cleanup fails
      }
    }
  }

  Future<Map<String, int?>> _resolveArtifactSizes({
    required List<RemoteSoftwareBinary> binaries,
    required SoftEggSettings settings,
    required PackagingProgressCallback onProgress,
  }) async {
    final sizeMap = <String, int?>{};
    if (binaries.isEmpty) {
      return sizeMap;
    }

    for (var index = 0; index < binaries.length; index++) {
      final binary = binaries[index];
      final uri = binary.uri.trim();
      final progress = 0.03 + (0.04 * ((index + 1) / binaries.length));
      onProgress(
        PackagingProgressUpdate(
          progress: progress,
          task: '원격 파일 정보 확인',
          level: 'INFO',
          message: '${binary.fileName} 원격 크기를 확인합니다.',
          loggable: index == 0,
          clearMetrics: true,
        ),
      );
      sizeMap[uri] = await _ftpDownloadService.fetchRemoteSize(
        ftpUri: binary.uri,
        settings: settings,
      );
    }
    return sizeMap;
  }

  Map<String, (double, double)> _buildArtifactSlices({
    required List<RemoteSoftwareBinary> binaries,
    required Map<String, int?> artifactSizes,
    required double phaseStart,
    required double phaseEnd,
    required double minimumSliceSpan,
  }) {
    final slices = <String, (double, double)>{};
    if (binaries.isEmpty) {
      return slices;
    }

    final phaseSpan = phaseEnd - phaseStart;
    final fallbackWeight = 1 / binaries.length;
    final totalKnownSize = binaries.fold<int>(
      0,
      (sum, binary) => sum + (artifactSizes[binary.uri.trim()] ?? 0),
    );
    final reservedMinimum = minimumSliceSpan * binaries.length;
    final distributableSpan = reservedMinimum >= phaseSpan
        ? 0.0
        : (phaseSpan - reservedMinimum);

    var cursor = phaseStart;
    for (var index = 0; index < binaries.length; index++) {
      final binary = binaries[index];
      final size = artifactSizes[binary.uri.trim()];
      final weight = totalKnownSize > 0 && size != null && size > 0
          ? size / totalKnownSize
          : fallbackWeight;
      final start = cursor;
      final end = index == binaries.length - 1
          ? phaseEnd
          : (cursor + minimumSliceSpan + (distributableSpan * weight));
      slices[binary.uri.trim()] = (start, end);
      cursor = end;
    }
    return slices;
  }

  Future<PackagingArtifactRecord> _downloadArtifact({
    required RemoteSoftwareBinary binary,
    required Directory destinationDirectory,
    required SoftEggSettings settings,
    required double progressStart,
    required double progressEnd,
    required PackagingProgressCallback onProgress,
    required String labelPrefix,
  }) async {
    final safeName = _uniqueSanitizedFileName(
      destinationDirectory.path,
      binary.fileName,
    );
    final file = File(p.join(destinationDirectory.path, safeName));
    onProgress(
      PackagingProgressUpdate(
        progress: progressStart,
        task: '$labelPrefix 다운로드 시작',
        level: 'INFO',
        message: '${binary.fileName} 다운로드를 시작합니다.',
        processedBytes: 0,
      ),
    );

    final downloadEnd = progressStart + ((progressEnd - progressStart) * 0.90);
    await _ftpDownloadService.downloadFile(
      ftpUri: binary.uri,
      destinationFile: file,
      settings: settings,
      onRetry: (attempt, reason) {
        onProgress(
          PackagingProgressUpdate(
            progress: progressStart,
            task: '$labelPrefix 재연결 시도',
            level: 'WARN',
            message: '$attempt회차 연결을 다시 시도합니다. $reason',
          ),
        );
      },
      onProgress: (progress, receivedBytes, totalBytes, bytesPerSecond) {
        final scaled =
            progressStart + ((downloadEnd - progressStart) * (progress / 100));
        onProgress(
          PackagingProgressUpdate(
            progress: scaled.clamp(progressStart, downloadEnd),
            task: '$labelPrefix 다운로드 중',
            level: 'INFO',
            message:
                '${binary.fileName} ${progress.toStringAsFixed(0)}% · ${_formatBytes(receivedBytes)}'
                '${totalBytes > 0 ? ' / ${_formatBytes(totalBytes)}' : ''}'
                '${bytesPerSecond > 0 ? ' · ${_formatBytes(bytesPerSecond.round())}/s' : ''}',
            loggable: false,
            processedBytes: receivedBytes,
            totalBytes: totalBytes > 0 ? totalBytes : null,
            bytesPerSecond: bytesPerSecond > 0 ? bytesPerSecond : null,
          ),
        );
      },
    );

    onProgress(
      PackagingProgressUpdate(
        progress: downloadEnd,
        task: '$labelPrefix 체크섬 검증',
        level: 'INFO',
        message: '${binary.fileName} 체크섬을 검증합니다.',
      ),
    );

    final isValid = await _checksumService.verifyFile(
      file,
      binary.checksum,
      onProgress: (progress, processedBytes, totalBytes) {
        final scaled =
            downloadEnd + ((progressEnd - downloadEnd) * (progress / 100));
        onProgress(
          PackagingProgressUpdate(
            progress: scaled.clamp(downloadEnd, progressEnd),
            task: '$labelPrefix 체크섬 검증 중',
            level: 'INFO',
            message:
                '${binary.fileName} 체크섬 ${progress.toStringAsFixed(0)}% · '
                '${_formatBytes(processedBytes)} / ${_formatBytes(totalBytes)}',
            loggable: false,
            processedBytes: processedBytes,
            totalBytes: totalBytes,
          ),
        );
      },
    );
    if (!isValid) {
      throw PackageBuildException(
        '체크섬 검증에 실패했습니다: ${binary.fileName} (expected ${binary.checksum})',
      );
    }

    final sizeBytes = await file.length();
    final checksum = binary.checksum.trim().isNotEmpty
        ? binary.checksum.trim().toLowerCase()
        : await _checksumService.computeXxHash64(file);
    onProgress(
      PackagingProgressUpdate(
        progress: progressEnd,
        task: '$labelPrefix 완료',
        level: 'INFO',
        message:
            '${binary.fileName} 다운로드 및 검증이 완료되었습니다. (${_formatBytes(sizeBytes)})',
        processedBytes: sizeBytes,
        totalBytes: sizeBytes,
        clearMetrics: true,
      ),
    );

    return PackagingArtifactRecord(
      kind: labelPrefix.startsWith('메인') ? 'main' : 'dependency',
      fileName: safeName,
      archivePath: p.join(
        labelPrefix.startsWith('메인') ? 'main' : 'dependencies',
        safeName,
      ),
      checksum: checksum,
      sizeBytes: sizeBytes,
    );
  }

  String _buildPackageFileName(
    RemoteSoftwarePackage softwarePackage,
    DateTime timestamp,
  ) {
    final safeSoftwareName = _sanitizeSegment(softwarePackage.name);
    final safeVersion = _sanitizeSegment(softwarePackage.version);
    return '${safeSoftwareName}_$safeVersion.segg';
  }

  String _formatBytes(int value) {
    if (value >= 1024 * 1024 * 1024) {
      return '${(value / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
    if (value >= 1024 * 1024) {
      return '${(value / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
    if (value >= 1024) {
      return '${(value / 1024).toStringAsFixed(2)} KB';
    }
    return '$value B';
  }

  String _uniqueSanitizedFileName(String directoryPath, String rawName) {
    final name = _sanitizeSegment(rawName.isEmpty ? 'artifact.bin' : rawName);
    final extension = p.extension(name);
    final baseName = extension.isEmpty
        ? name
        : name.substring(0, name.length - extension.length);

    var candidate = name;
    var index = 2;
    while (File(p.join(directoryPath, candidate)).existsSync()) {
      candidate = '$baseName-$index$extension';
      index += 1;
    }
    return candidate;
  }

  String _sanitizeSegment(String value) {
    final sanitized = value.replaceAll(RegExp(r'[^\w.\-]+'), '_');
    return sanitized.isEmpty ? 'artifact' : sanitized;
  }
}

class PackageBuildException implements Exception {
  const PackageBuildException(this.message);

  final String message;

  @override
  String toString() => message;
}
