import 'dart:io';
import 'dart:typed_data';

import 'package:soft_egg_packager/src/services/packaging_cancellation.dart';

class ChecksumService {
  static final BigInt _prime1 = BigInt.parse('11400714785074694791');
  static final BigInt _prime2 = BigInt.parse('14029467366897019727');
  static final BigInt _prime3 = BigInt.parse('1609587929392839161');
  static final BigInt _prime4 = BigInt.parse('9650029242287828579');
  static final BigInt _prime5 = BigInt.parse('2870177450012600261');

  const ChecksumService();

  Future<String> computeXxHash64(
    File file, {
    void Function(double progress, int processedBytes, int totalBytes)?
    onProgress,
    PackagingCancellationToken? cancellationToken,
  }) async {
    final totalBytes = await file.length();
    final hash = await _digestStream(
      file.openRead(),
      totalBytes: totalBytes,
      onProgress: onProgress,
      cancellationToken: cancellationToken,
    );
    return hash.toRadixString(16).padLeft(16, '0');
  }

  Future<bool> verifyFile(
    File file,
    String expectedChecksum, {
    void Function(double progress, int processedBytes, int totalBytes)?
    onProgress,
    PackagingCancellationToken? cancellationToken,
  }) async {
    final expected = expectedChecksum.trim().toLowerCase();
    if (expected.isEmpty) {
      return true;
    }
    final computed = await computeXxHash64(
      file,
      onProgress: onProgress,
      cancellationToken: cancellationToken,
    );
    return computed == expected;
  }

  Future<BigInt> _digestStream(
    Stream<List<int>> stream, {
    required int totalBytes,
    void Function(double progress, int processedBytes, int totalBytes)?
    onProgress,
    PackagingCancellationToken? cancellationToken,
  }) async {
    final tail = Uint8List(32);
    var tailLength = 0;
    var hadStripe = false;
    var totalLength = BigInt.zero;
    var processedBytes = 0;
    var lastReportedBytes = -1;
    var v1 = (_prime1 + _prime2).toUnsigned(64);
    var v2 = _prime2.toUnsigned(64);
    var v3 = BigInt.zero;
    var v4 = (-_prime1).toUnsigned(64);

    await for (final chunk in stream) {
      cancellationToken?.throwIfCancelled();
      totalLength += BigInt.from(chunk.length);
      processedBytes += chunk.length;
      var offset = 0;

      if (tailLength > 0) {
        final needed = 32 - tailLength;
        if (chunk.length < needed) {
          tail.setRange(tailLength, tailLength + chunk.length, chunk);
          tailLength += chunk.length;
          continue;
        }

        tail.setRange(tailLength, 32, chunk.sublist(0, needed));
        v1 = _round(v1, _readUint64LE(tail, 0));
        v2 = _round(v2, _readUint64LE(tail, 8));
        v3 = _round(v3, _readUint64LE(tail, 16));
        v4 = _round(v4, _readUint64LE(tail, 24));
        hadStripe = true;
        offset += needed;
        tailLength = 0;
      }

      final limit = chunk.length - ((chunk.length - offset) % 32);
      while (offset < limit) {
        v1 = _round(v1, _readUint64LE(chunk, offset));
        v2 = _round(v2, _readUint64LE(chunk, offset + 8));
        v3 = _round(v3, _readUint64LE(chunk, offset + 16));
        v4 = _round(v4, _readUint64LE(chunk, offset + 24));
        hadStripe = true;
        offset += 32;
      }

      if (offset < chunk.length) {
        tailLength = chunk.length - offset;
        tail.setRange(0, tailLength, chunk.sublist(offset));
      }

      if (onProgress != null && totalBytes > 0) {
        final shouldReport =
            processedBytes == totalBytes ||
            processedBytes - lastReportedBytes >= (256 * 1024);
        if (shouldReport) {
          cancellationToken?.throwIfCancelled();
          lastReportedBytes = processedBytes;
          onProgress(
            ((processedBytes / totalBytes) * 100).clamp(0, 100).toDouble(),
            processedBytes,
            totalBytes,
          );
        }
      }
    }

    cancellationToken?.throwIfCancelled();

    BigInt hash;
    if (hadStripe) {
      hash = (_rotl(v1, 1) + _rotl(v2, 7) + _rotl(v3, 12) + _rotl(v4, 18))
          .toUnsigned(64);
      hash = _mergeRound(hash, v1);
      hash = _mergeRound(hash, v2);
      hash = _mergeRound(hash, v3);
      hash = _mergeRound(hash, v4);
    } else {
      hash = _prime5.toUnsigned(64);
    }

    hash = (hash + totalLength).toUnsigned(64);

    var tailOffset = 0;
    while (tailOffset + 8 <= tailLength) {
      final lane = _readUint64LE(tail, tailOffset);
      hash ^= _round(BigInt.zero, lane);
      hash = ((_rotl(hash, 27) * _prime1) + _prime4).toUnsigned(64);
      tailOffset += 8;
    }

    if (tailOffset + 4 <= tailLength) {
      final lane = _readUint32LE(tail, tailOffset);
      hash ^= (lane * _prime1).toUnsigned(64);
      hash = ((_rotl(hash, 23) * _prime2) + _prime3).toUnsigned(64);
      tailOffset += 4;
    }

    while (tailOffset < tailLength) {
      hash ^= (BigInt.from(tail[tailOffset]) * _prime5).toUnsigned(64);
      hash = (_rotl(hash, 11) * _prime1).toUnsigned(64);
      tailOffset += 1;
    }

    return _avalanche(hash).toUnsigned(64);
  }

  BigInt _round(BigInt acc, BigInt input) {
    var next = acc + (input * _prime2).toUnsigned(64);
    next = next.toUnsigned(64);
    next = _rotl(next, 31);
    next = (next * _prime1).toUnsigned(64);
    return next;
  }

  BigInt _mergeRound(BigInt acc, BigInt value) {
    var next = acc ^ _round(BigInt.zero, value);
    next = ((next * _prime1).toUnsigned(64) + _prime4).toUnsigned(64);
    return next;
  }

  BigInt _avalanche(BigInt hash) {
    var next = hash;
    next ^= next >> 33;
    next = (next * _prime2).toUnsigned(64);
    next ^= next >> 29;
    next = (next * _prime3).toUnsigned(64);
    next ^= next >> 32;
    return next;
  }

  BigInt _rotl(BigInt value, int count) {
    return ((value << count) | (value >> (64 - count))).toUnsigned(64);
  }

  BigInt _readUint64LE(List<int> bytes, int offset) {
    var result = BigInt.zero;
    for (var index = 0; index < 8; index++) {
      result |= BigInt.from(bytes[offset + index]) << (index * 8);
    }
    return result.toUnsigned(64);
  }

  BigInt _readUint32LE(List<int> bytes, int offset) {
    var result = BigInt.zero;
    for (var index = 0; index < 4; index++) {
      result |= BigInt.from(bytes[offset + index]) << (index * 8);
    }
    return result.toUnsigned(32).toUnsigned(64);
  }
}
