import 'dart:io';

import 'package:soft_egg_packager/src/data/catalog_api_client.dart';
import 'package:soft_egg_packager/src/data/catalog_repository.dart';
import 'package:soft_egg_packager/src/services/checksum_service.dart';
import 'package:soft_egg_packager/src/services/ftp_download_service.dart';
import 'package:soft_egg_packager/src/services/local_settings_service.dart';
import 'package:soft_egg_packager/src/services/package_builder_service.dart';

Future<void> main(List<String> args) async {
  final companyCode = args.isNotEmpty
      ? args.first.trim().toUpperCase()
      : 'U4HHP';
  final settings = await const LocalSettingsService().load();
  final repository = CatalogRepository(
    apiClient: CatalogApiClient(baseUrl: settings.apiBaseUrl),
  );
  final catalog = await repository.fetchCatalog(companyCode);
  final selectedPackage = catalog.softwarePackages.firstWhere(
    (item) => item.mainBinary.hasUri,
    orElse: () => throw StateError('패키징 가능한 메인 바이너리가 없습니다.'),
  );

  final selectedDependencies = selectedPackage.dependencies
      .where((item) => item.hasUri)
      .toList(growable: false);

  final builder = PackageBuilderService(
    ftpDownloadService: const FtpDownloadService(),
    checksumService: const ChecksumService(),
  );

  stdout.writeln('SoftEgg smoke packaging start');
  stdout.writeln(
    'Company: ${catalog.company.companyName} (${catalog.company.companyCode})',
  );
  stdout.writeln('Package: ${selectedPackage.name} ${selectedPackage.version}');
  stdout.writeln('Dependencies: ${selectedDependencies.length}');

  final result = await builder.build(
    settings: settings,
    company: catalog.company,
    softwarePackage: selectedPackage,
    selectedDependencies: selectedDependencies,
    onProgress: (update) {
      if (update.loggable) {
        stdout.writeln('[${update.level}] ${update.task} :: ${update.message}');
      }
    },
  );

  stdout.writeln('Package file: ${result.packageFilePath}');
  stdout.writeln('Package size: ${result.packageSizeBytes}');
}
