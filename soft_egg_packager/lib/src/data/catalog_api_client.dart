import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:soft_egg_packager/src/models/packaging_models.dart';

class CatalogApiClient {
  const CatalogApiClient({required this.baseUrl});

  final String baseUrl;

  Future<void> probeServer() async {
    final uri = Uri.parse('$baseUrl/api/health');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.getUrl(uri);
      request.headers.set(
        HttpHeaders.acceptHeader,
        ContentType.json.toString(),
      );
      final response = await request.close();
      if (response.statusCode >= 200 && response.statusCode < 300) {
        await response.drain<void>();
        return;
      }
      final rawBody = await response.transform(utf8.decoder).join();
      throw CatalogException(
        message: rawBody.trim().isEmpty
            ? '카탈로그 서버 상태 확인에 실패했습니다.'
            : rawBody.trim(),
        error: 'healthcheck_failed',
        requestId: '',
        statusCode: response.statusCode,
      );
    } on TimeoutException catch (error) {
      throw CatalogException(
        message: '카탈로그 서버 응답 시간이 초과되었습니다.',
        error: 'timeout',
        statusCode: 0,
        requestId: '',
        cause: error,
      );
    } on SocketException catch (error) {
      throw CatalogException(
        message: '카탈로그 서버에 연결하지 못했습니다.',
        error: 'network_error',
        statusCode: 0,
        requestId: '',
        cause: error,
      );
    } on HandshakeException catch (error) {
      throw CatalogException(
        message: '카탈로그 서버 TLS 연결에 실패했습니다.',
        error: 'tls_error',
        statusCode: 0,
        requestId: '',
        cause: error,
      );
    } on HttpException catch (error) {
      throw CatalogException(
        message: '카탈로그 상태 응답을 처리하지 못했습니다.',
        error: 'http_error',
        statusCode: 0,
        requestId: '',
        cause: error,
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<CompanyCatalog> fetchCatalog(String companyCode) async {
    final sanitizedCode = companyCode.trim().toUpperCase();
    final uri = Uri.parse(
      '$baseUrl/api/public/software-catalog/$sanitizedCode',
    );
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.getUrl(uri);
      request.headers.contentType = ContentType.json;
      final response = await request.close();
      final rawBody = await response.transform(utf8.decoder).join();
      final payload = rawBody.trim().isEmpty
          ? const <String, dynamic>{}
          : (jsonDecode(rawBody) as Map<String, dynamic>);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return CompanyCatalog.fromJson(payload);
      }

      throw CatalogException(
        message: (payload['message'] ?? '카탈로그 조회에 실패했습니다.').toString(),
        error: (payload['error'] ?? 'catalog_request_failed').toString(),
        requestId: (payload['requestId'] ?? '').toString(),
        statusCode: response.statusCode,
      );
    } on SocketException catch (error) {
      throw CatalogException(
        message: '카탈로그 서버에 연결하지 못했습니다.',
        error: 'network_error',
        statusCode: 0,
        requestId: '',
        cause: error,
      );
    } on TimeoutException catch (error) {
      throw CatalogException(
        message: '카탈로그 서버 응답 시간이 초과되었습니다.',
        error: 'timeout',
        statusCode: 0,
        requestId: '',
        cause: error,
      );
    } on HandshakeException catch (error) {
      throw CatalogException(
        message: '카탈로그 서버 TLS 연결에 실패했습니다.',
        error: 'tls_error',
        statusCode: 0,
        requestId: '',
        cause: error,
      );
    } on HttpException catch (error) {
      throw CatalogException(
        message: '카탈로그 응답을 처리하지 못했습니다.',
        error: 'http_error',
        statusCode: 0,
        requestId: '',
        cause: error,
      );
    } on FormatException catch (error) {
      throw CatalogException(
        message: '카탈로그 응답 형식이 올바르지 않습니다.',
        error: 'invalid_response',
        statusCode: 0,
        requestId: '',
        cause: error,
      );
    } finally {
      client.close(force: true);
    }
  }
}

class CatalogException implements Exception {
  const CatalogException({
    required this.message,
    required this.error,
    required this.requestId,
    required this.statusCode,
    this.cause,
  });

  final String message;
  final String error;
  final String requestId;
  final int statusCode;
  final Object? cause;

  @override
  String toString() {
    return 'CatalogException(statusCode: $statusCode, error: $error, message: $message, requestId: $requestId, cause: $cause)';
  }
}
