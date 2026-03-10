import 'package:soft_egg_packager/src/data/catalog_api_client.dart';
import 'package:soft_egg_packager/src/models/packaging_models.dart';

class CatalogRepository {
  const CatalogRepository({required CatalogApiClient apiClient})
    : _apiClient = apiClient;

  final CatalogApiClient _apiClient;

  Future<CompanyCatalog> fetchCatalog(String companyCode) async {
    final catalog = await _apiClient.fetchCatalog(companyCode);
    if (catalog.softwarePackages.isEmpty) {
      throw const CatalogException(
        message: '할당된 소프트웨어가 없습니다.',
        error: 'no_software_assigned',
        requestId: '',
        statusCode: 404,
      );
    }
    if (catalog.desktopPackages.isEmpty) {
      throw const CatalogException(
        message: '데스크톱 패키징 가능한 소프트웨어가 없습니다.',
        error: 'no_desktop_software',
        requestId: '',
        statusCode: 404,
      );
    }
    return catalog;
  }
}
