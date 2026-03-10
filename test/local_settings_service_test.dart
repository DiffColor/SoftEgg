import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soft_egg_packager/src/services/local_settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('마지막 export root를 저장하고 다시 불러온다', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    final tempDirectory = await Directory.systemTemp.createTemp(
      'soft_egg_output_test_',
    );
    try {
      const service = LocalSettingsService();
      final updated = await service.updateExportRoot(tempDirectory.path);
      final reloaded = await service.load();

      expect(updated.exportRootPath, tempDirectory.path);
      expect(reloaded.exportRootPath, tempDirectory.path);
    } finally {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    }
  });

  test('기본 export root는 Documents/SoftEgg를 사용한다', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    const service = LocalSettingsService();
    final settings = await service.load();

    expect(
      settings.exportRootPath.replaceAll('\\', '/'),
      endsWith('/Documents/SoftEgg'),
    );
  });

  test('macOS 샌드박스 Documents 경로는 실제 사용자 Documents로 교정한다', () async {
    if (!Platform.isMacOS) {
      return;
    }

    const service = LocalSettingsService();
    final homeDirectory = service.resolveHomeDirectory().replaceAll('\\', '/');

    SharedPreferences.setMockInitialValues(<String, Object>{
      'softegg.last_export_root':
          '$homeDirectory/Library/Containers/com.example.softEggPackager/Data/Documents/SoftEgg',
    });

    final settings = await service.load();

    expect(
      settings.exportRootPath.replaceAll('\\', '/'),
      '$homeDirectory/Documents/SoftEgg',
    );
  });
}
