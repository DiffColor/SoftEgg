import 'dart:async';
import 'dart:io';

import 'package:ftpconnect/ftpconnect.dart';
import 'package:path/path.dart' as p;
import 'package:soft_egg_packager/src/services/local_settings_service.dart';
import 'package:soft_egg_packager/src/services/packaging_cancellation.dart';

class FtpDownloadService {
  const FtpDownloadService();

  static const int _progressChunkBytes = 512 * 1024;
  static const double _progressChunkPercent = 0.45;
  static const int _progressChunkMilliseconds = 140;
  static const int _maxDownloadAttempts = 3;

  Future<int?> fetchRemoteSize({
    required String ftpUri,
    required SoftEggSettings settings,
    PackagingCancellationToken? cancellationToken,
  }) async {
    final target = _parseRemoteTarget(ftpUri, settings);
    final client = _createClient(settings, target.host);
    var cancelled = false;
    final subscription = cancellationToken?.onCancel(() {
      cancelled = true;
      unawaited(_safeDisconnect(client));
    });
    try {
      cancellationToken?.throwIfCancelled();
      await client.connect();
      cancellationToken?.throwIfCancelled();
      await _changeToParentDirectory(client, target.absolutePath);
      cancellationToken?.throwIfCancelled();
      final size = await client.sizeFile(target.fileName);
      return size >= 0 ? size : null;
    } on FTPConnectException {
      if (cancelled || cancellationToken?.isCancelled == true) {
        throw const PackagingCancelledException();
      }
      return null;
    } finally {
      subscription?.dispose();
      await _safeDisconnect(client);
    }
  }

  Future<void> downloadFile({
    required String ftpUri,
    required File destinationFile,
    required SoftEggSettings settings,
    PackagingCancellationToken? cancellationToken,
    void Function(
      double progress,
      int receivedBytes,
      int totalBytes,
      double bytesPerSecond,
    )?
    onProgress,
    void Function(int attempt, String reason)? onRetry,
  }) async {
    final target = _parseRemoteTarget(ftpUri, settings);
    final parent = destinationFile.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }
    Object? lastError;

    for (var attempt = 1; attempt <= _maxDownloadAttempts; attempt++) {
      cancellationToken?.throwIfCancelled();
      if (await destinationFile.exists()) {
        await destinationFile.delete();
      }

      final client = _createClient(settings, target.host);
      var cancelled = false;
      final subscription = cancellationToken?.onCancel(() {
        cancelled = true;
        unawaited(_safeDisconnect(client));
      });
      final stopwatch = Stopwatch()..start();
      var lastBytes = 0;
      var lastElapsedMs = 0;
      var lastReportedBytes = 0;
      var lastReportedProgress = 0.0;
      var lastReportedMs = 0;

      try {
        cancellationToken?.throwIfCancelled();
        await client.connect();
        cancellationToken?.throwIfCancelled();
        await _changeToParentDirectory(client, target.absolutePath);
        cancellationToken?.throwIfCancelled();
        final totalBytes = await client.sizeFile(target.fileName);
        onProgress?.call(0, 0, totalBytes > 0 ? totalBytes : 0, 0);

        final downloaded = await client.downloadFile(
          target.fileName,
          destinationFile,
          onProgress: (progress, receivedBytes, fileSize) {
            final elapsedMs = stopwatch.elapsedMilliseconds;
            final deltaBytes = receivedBytes - lastBytes;
            final deltaMs = elapsedMs - lastElapsedMs;
            final speed = deltaMs > 0 ? (deltaBytes * 1000) / deltaMs : 0.0;
            lastBytes = receivedBytes;
            lastElapsedMs = elapsedMs;
            final shouldEmit =
                receivedBytes == fileSize ||
                receivedBytes - lastReportedBytes >= _progressChunkBytes ||
                progress - lastReportedProgress >= _progressChunkPercent ||
                elapsedMs - lastReportedMs >= _progressChunkMilliseconds;
            if (!shouldEmit) {
              return;
            }
            cancellationToken?.throwIfCancelled();
            lastReportedBytes = receivedBytes;
            lastReportedProgress = progress;
            lastReportedMs = elapsedMs;
            onProgress?.call(progress, receivedBytes, fileSize, speed);
          },
        );

        if (!downloaded) {
          if (cancelled || cancellationToken?.isCancelled == true) {
            throw const PackagingCancelledException();
          }
          throw FtpDownloadException(
            'FTP 다운로드에 실패했습니다: ${target.absolutePath}',
          );
        }
        if (!await destinationFile.exists()) {
          if (cancelled || cancellationToken?.isCancelled == true) {
            throw const PackagingCancelledException();
          }
          throw const FtpDownloadException('다운로드 파일이 생성되지 않았습니다.');
        }

        final size = await destinationFile.length();
        final resolvedTotal = totalBytes > 0 ? totalBytes : size;
        onProgress?.call(100, size, resolvedTotal, 0);
        return;
      } on PackagingCancelledException {
        if (await destinationFile.exists()) {
          await destinationFile.delete();
        }
        rethrow;
      } on FTPConnectException catch (error) {
        if (cancelled || cancellationToken?.isCancelled == true) {
          if (await destinationFile.exists()) {
            await destinationFile.delete();
          }
          throw const PackagingCancelledException();
        }
        lastError = FtpDownloadException(
          _normalizeFtpError(error, target.absolutePath),
        );
      } on SocketException catch (error) {
        if (cancelled || cancellationToken?.isCancelled == true) {
          if (await destinationFile.exists()) {
            await destinationFile.delete();
          }
          throw const PackagingCancelledException();
        }
        lastError = FtpDownloadException('FTP 소켓 연결에 실패했습니다: ${error.message}');
      } on FtpDownloadException catch (error) {
        if (cancelled || cancellationToken?.isCancelled == true) {
          if (await destinationFile.exists()) {
            await destinationFile.delete();
          }
          throw const PackagingCancelledException();
        }
        lastError = error;
      } finally {
        subscription?.dispose();
        await _safeDisconnect(client);
      }

      if (cancellationToken?.isCancelled == true) {
        throw const PackagingCancelledException();
      }
      if (attempt < _maxDownloadAttempts) {
        onRetry?.call(attempt + 1, lastError.toString());
        await Future<void>.delayed(Duration(milliseconds: 400 * attempt));
      }
    }

    throw (lastError is FtpDownloadException
        ? lastError
        : const FtpDownloadException('FTP 다운로드에 실패했습니다.'));
  }

  FTPConnect _createClient(SoftEggSettings settings, String host) {
    final client = FTPConnect(
      host,
      user: settings.ftpUser,
      pass: settings.ftpPassword,
      timeout: 30,
      showLog: false,
      securityType: SecurityType.ftp,
    );
    client.transferMode = TransferMode.passive;
    client.supportIPV6 = false;
    return client;
  }

  Future<void> _changeToParentDirectory(
    FTPConnect client,
    String absolutePath,
  ) async {
    final parentDirectory = p.posix.dirname(absolutePath);
    if (parentDirectory == '.' || parentDirectory.isEmpty) {
      return;
    }
    final ok = await client.changeDirectory(parentDirectory);
    if (!ok) {
      throw FtpDownloadException('FTP 디렉터리 이동에 실패했습니다: $parentDirectory');
    }
    await client.setTransferType(TransferType.binary);
  }

  Future<void> _safeDisconnect(FTPConnect client) async {
    try {
      await client.disconnect();
    } catch (_) {
      // ignore disconnect failures
    }
  }

  _FtpTarget _parseRemoteTarget(String ftpUri, SoftEggSettings settings) {
    final uri = Uri.parse(ftpUri.trim());
    if (uri.scheme.toLowerCase() != 'ftp') {
      throw FtpDownloadException('FTP URI 형식이 아닙니다: $ftpUri');
    }
    if (uri.pathSegments.isEmpty) {
      throw FtpDownloadException('FTP 파일 경로가 비어 있습니다: $ftpUri');
    }
    final host = uri.host.isNotEmpty ? uri.host : settings.ftpHost;
    if (host.isEmpty) {
      throw const FtpDownloadException('FTP 호스트 설정이 비어 있습니다.');
    }
    final decodedSegments = uri.pathSegments
        .map(Uri.decodeComponent)
        .where((segment) => segment.trim().isNotEmpty)
        .toList(growable: false);
    if (decodedSegments.isEmpty) {
      throw FtpDownloadException('FTP 경로 해석에 실패했습니다: $ftpUri');
    }
    final absolutePath = '/${decodedSegments.join('/')}';
    return _FtpTarget(
      host: host,
      absolutePath: absolutePath,
      fileName: decodedSegments.last,
    );
  }

  String _normalizeFtpError(FTPConnectException error, String path) {
    final message = error.toString().trim();
    if (message.isEmpty) {
      return 'FTP 다운로드에 실패했습니다: $path';
    }
    return 'FTP 다운로드에 실패했습니다: $message';
  }
}

class FtpDownloadException implements Exception {
  const FtpDownloadException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _FtpTarget {
  const _FtpTarget({
    required this.host,
    required this.absolutePath,
    required this.fileName,
  });

  final String host;
  final String absolutePath;
  final String fileName;
}
