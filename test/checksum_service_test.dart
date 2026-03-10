import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:soft_egg_packager/src/services/checksum_service.dart';

void main() {
  test('xxHash64 계산값은 다시 검증할 수 있다', () async {
    final tempDir = await Directory.systemTemp.createTemp('softegg_checksum_');
    try {
      final file = File('${tempDir.path}/sample.bin');
      await file.writeAsBytes(
        Uint8List.fromList(List<int>.generate(64, (i) => i)),
      );
      const service = ChecksumService();
      final checksum = await service.computeXxHash64(file);

      expect(await service.verifyFile(file, checksum), isTrue);
      expect(await service.verifyFile(file, '0000000000000000'), isFalse);
    } finally {
      await tempDir.delete(recursive: true);
    }
  });

  test('스트리밍 xxHash64는 알려진 벡터와 일치한다', () async {
    final tempDir = await Directory.systemTemp.createTemp('softegg_checksum_');
    const service = ChecksumService();
    final cases = <String, List<int>>{
      'ef46db3751d8e999': <int>[],
      '0a9edecebeb03ae4': <int>[42],
      'c346d2b59b4d8ee1': List<int>.generate(31, (i) => i),
      'cbf59c5116ff32b4': List<int>.generate(32, (i) => i),
      '0c535d1acafb8ead': List<int>.generate(33, (i) => i),
      '4cf75ee72cd8f4cc': List<int>.generate(100000, (i) => i % 251),
    };

    try {
      for (final entry in cases.entries) {
        final file = File('${tempDir.path}/${entry.key}.bin');
        await file.writeAsBytes(Uint8List.fromList(entry.value));
        final checksum = await service.computeXxHash64(file);
        expect(checksum, entry.key);
      }
    } finally {
      await tempDir.delete(recursive: true);
    }
  });
}
