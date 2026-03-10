// ignore_for_file: implementation_imports

import 'dart:async';
import 'dart:io';

import 'package:ftpconnect/ftpconnect.dart';
import 'package:path/path.dart' as p;
import 'package:ftpconnect/src/ftp_reply.dart';
import 'package:ftpconnect/src/ftp_socket.dart';
import 'package:ftpconnect/src/utils.dart';
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

      final socket = _createSocket(settings, target.host);
      Socket? dataSocket;
      IOSink? sink;
      StreamSubscription<List<int>>? dataSubscription;
      Completer<void>? transferCompleter;
      var cancelled = false;
      final subscription = cancellationToken?.onCancel(() {
        cancelled = true;
        dataSubscription?.cancel();
        dataSocket?.destroy();
        dataSocket = null;
        unawaited(sink?.close() ?? Future<void>.value());
        unawaited(_safeDisconnectSocket(socket));
        if (transferCompleter != null && !transferCompleter.isCompleted) {
          transferCompleter.completeError(const PackagingCancelledException());
        }
      });
      final stopwatch = Stopwatch()..start();
      var lastBytes = 0;
      var lastElapsedMs = 0;
      var lastReportedBytes = 0;
      var lastReportedProgress = 0.0;
      var lastReportedMs = 0;

      try {
        cancellationToken?.throwIfCancelled();
        await socket.connect(settings.ftpUser, settings.ftpPassword);
        cancellationToken?.throwIfCancelled();
        await _changeToParentDirectorySocket(socket, target.absolutePath);
        cancellationToken?.throwIfCancelled();
        final totalBytes = await _sizeFile(socket, target.fileName);
        onProgress?.call(0, 0, totalBytes > 0 ? totalBytes : 0, 0);

        final response = await socket.openDataTransferChannel();
        socket.sendCommandWithoutWaitingResponse('RETR ${target.fileName}');

        final port = Utils.parsePort(response.message, socket.supportIPV6);
        dataSocket = await Socket.connect(
          target.host,
          port,
          timeout: Duration(seconds: socket.timeout),
        );

        final startResponse = await socket.readResponse();
        final transferAccepted =
            startResponse.isSuccessCode() ||
            startResponse.code == 125 ||
            startResponse.code == 150;
        if (!transferAccepted) {
          throw FTPConnectException(
            'Connection refused. ',
            startResponse.message,
          );
        }

        sink = destinationFile.openWrite(mode: FileMode.writeOnly);
        final activeSink = sink;
        final doneCompleter = Completer<void>();
        transferCompleter = doneCompleter;
        var receivedBytes = 0;
        final activeDataSocket = dataSocket;

        dataSubscription = activeDataSocket!.listen(
          (data) {
            if (cancelled || cancellationToken?.isCancelled == true) {
              return;
            }
            activeSink.add(data);
            receivedBytes += data.length;
            final progress = totalBytes > 0
                ? ((receivedBytes / totalBytes) * 100).clamp(0, 100).toDouble()
                : 100.0;
            final elapsedMs = stopwatch.elapsedMilliseconds;
            final deltaBytes = receivedBytes - lastBytes;
            final deltaMs = elapsedMs - lastElapsedMs;
            final speed = deltaMs > 0 ? (deltaBytes * 1000) / deltaMs : 0.0;
            lastBytes = receivedBytes;
            lastElapsedMs = elapsedMs;
            final shouldEmit =
                receivedBytes == totalBytes ||
                receivedBytes - lastReportedBytes >= _progressChunkBytes ||
                progress - lastReportedProgress >= _progressChunkPercent ||
                elapsedMs - lastReportedMs >= _progressChunkMilliseconds;
            if (!shouldEmit) {
              return;
            }
            lastReportedBytes = receivedBytes;
            lastReportedProgress = progress;
            lastReportedMs = elapsedMs;
            onProgress?.call(progress, receivedBytes, totalBytes, speed);
          },
          onDone: () {
            if (!doneCompleter.isCompleted) {
              doneCompleter.complete();
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!doneCompleter.isCompleted) {
              doneCompleter.completeError(error, stackTrace);
            }
          },
          cancelOnError: true,
        );

        await doneCompleter.future;
        transferCompleter = null;
        await activeSink.flush();
        await activeSink.close();
        sink = null;
        await activeDataSocket.close();
        dataSocket = null;

        if (cancelled || cancellationToken?.isCancelled == true) {
          throw const PackagingCancelledException();
        }

        if (!startResponse.isSuccessCode()) {
          final endResponse = await socket.readResponse();
          if (!endResponse.isSuccessCode()) {
            throw FTPConnectException('Transfer Error.', endResponse.message);
          }
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
        await dataSubscription?.cancel();
        if (sink != null) {
          final activeSink = sink;
          try {
            await activeSink.close();
          } catch (_) {}
        }
        if (dataSocket != null) {
          final activeDataSocket = dataSocket!;
          try {
            await activeDataSocket.close();
          } catch (_) {
            activeDataSocket.destroy();
          }
        }
        if (cancelled || cancellationToken?.isCancelled == true) {
          unawaited(_safeDisconnectSocket(socket));
        } else {
          await _safeDisconnectSocket(socket);
        }
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

  FTPSocket _createSocket(SoftEggSettings settings, String host) {
    final socket = FTPSocket(
      host,
      21,
      SecurityType.ftp,
      Logger(isEnabled: false),
      30,
    );
    socket.transferMode = TransferMode.passive;
    socket.supportIPV6 = false;
    return socket;
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

  Future<void> _changeToParentDirectorySocket(
    FTPSocket socket,
    String absolutePath,
  ) async {
    final parentDirectory = p.posix.dirname(absolutePath);
    if (parentDirectory == '.' || parentDirectory.isEmpty) {
      return;
    }
    final response = await socket.sendCommand('CWD $parentDirectory');
    if (!response.isSuccessCode()) {
      throw FtpDownloadException('FTP 디렉터리 이동에 실패했습니다: $parentDirectory');
    }
    await socket.setTransferType(TransferType.binary);
  }

  Future<void> _safeDisconnect(FTPConnect client) async {
    try {
      await client.disconnect();
    } catch (_) {
      // ignore disconnect failures
    }
  }

  Future<void> _safeDisconnectSocket(FTPSocket socket) async {
    try {
      await socket.disconnect();
    } catch (_) {
      // ignore disconnect failures
    }
  }

  Future<int> _sizeFile(FTPSocket socket, String fileName) async {
    try {
      FTPReply response = await socket.sendCommand('SIZE $fileName');
      if (!response.isSuccessCode() &&
          socket.transferType != TransferType.binary) {
        final transferType = socket.transferType;
        await socket.setTransferType(TransferType.binary);
        response = await socket.sendCommand('SIZE $fileName');
        await socket.setTransferType(transferType);
      }
      return int.parse(response.message.replaceAll('213 ', ''));
    } catch (_) {
      return -1;
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
