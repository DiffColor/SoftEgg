import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

class SoftEggSettings {
  const SoftEggSettings({
    required this.apiBaseUrl,
    required this.ftpHost,
    required this.ftpUser,
    required this.ftpPassword,
    required this.exportRootPath,
  });

  final String apiBaseUrl;
  final String ftpHost;
  final String ftpUser;
  final String ftpPassword;
  final String exportRootPath;

  SoftEggSettings copyWith({
    String? apiBaseUrl,
    String? ftpHost,
    String? ftpUser,
    String? ftpPassword,
    String? exportRootPath,
  }) {
    return SoftEggSettings(
      apiBaseUrl: apiBaseUrl ?? this.apiBaseUrl,
      ftpHost: ftpHost ?? this.ftpHost,
      ftpUser: ftpUser ?? this.ftpUser,
      ftpPassword: ftpPassword ?? this.ftpPassword,
      exportRootPath: exportRootPath ?? this.exportRootPath,
    );
  }

  bool get hasFtpCredentials {
    return ftpHost.trim().isNotEmpty &&
        ftpUser.trim().isNotEmpty &&
        ftpPassword.trim().isNotEmpty;
  }

  String? get packagingBlocker {
    if (!hasFtpCredentials) {
      return 'FTP 설정이 없어 실제 패키징을 시작할 수 없습니다.';
    }
    return null;
  }
}

class LocalSettingsService {
  const LocalSettingsService();

  static const String _lastExportRootKey = 'softegg.last_export_root';

  String resolveHomeDirectory() => _resolveHomeDirectory();
  String resolveDefaultExportRoot() =>
      _resolveDefaultExportRootPath(_resolveHomeDirectory());

  Future<SoftEggSettings> load() async {
    final homeDirectory = _resolveHomeDirectory();
    final baseSettings = SoftEggSettings(
      apiBaseUrl: _AppEmbeddedConfig.apiBaseUrl.trim(),
      ftpHost: _AppEmbeddedConfig.ftpHost.trim(),
      ftpUser: _AppEmbeddedConfig.ftpUser.trim(),
      ftpPassword: _AppEmbeddedConfig.ftpPassword.trim(),
      exportRootPath: _resolveDefaultExportRootPath(homeDirectory),
    );

    final preferences = await SharedPreferences.getInstance();
    final persistedExportRoot =
        preferences.getString(_lastExportRootKey)?.trim() ?? '';
    if (persistedExportRoot.isEmpty) {
      return baseSettings;
    }

    final normalizedExportRoot = _normalizeExportRoot(
      persistedExportRoot,
      homeDirectory: homeDirectory,
    );
    if (normalizedExportRoot != persistedExportRoot) {
      await preferences.setString(_lastExportRootKey, normalizedExportRoot);
    }

    return baseSettings.copyWith(exportRootPath: normalizedExportRoot);
  }

  Future<SoftEggSettings> updateExportRoot(String rawPath) async {
    final settings = await load();
    final normalizedPath = _normalizeExportRoot(
      rawPath,
      homeDirectory: _resolveHomeDirectory(),
    );
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_lastExportRootKey, normalizedPath);
    return settings.copyWith(exportRootPath: normalizedPath);
  }

  Future<SoftEggSettings> resetExportRoot() async {
    final settings = await load();
    final homeDirectory = _resolveHomeDirectory();
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_lastExportRootKey);
    return settings.copyWith(
      exportRootPath: _resolveDefaultExportRootPath(homeDirectory),
    );
  }

  String _resolveHomeDirectory() {
    final home = _readEnv('HOME');
    if (Platform.isMacOS) {
      final sandboxHome = _extractMacOsUserHome(home);
      if (sandboxHome != null) {
        return sandboxHome;
      }
      final fixedHome = _readEnv('CFFIXED_USER_HOME');
      if (fixedHome != null && fixedHome.isNotEmpty) {
        return p.normalize(fixedHome);
      }
      final logName = _readEnv('LOGNAME') ?? _readEnv('USER');
      if (logName != null && logName.isNotEmpty) {
        final candidate = p.join('/Users', logName);
        if (Directory(candidate).existsSync()) {
          return candidate;
        }
      }
    }
    if (home != null && home.isNotEmpty) {
      return p.normalize(home);
    }
    final userProfile = _readEnv('USERPROFILE');
    if (userProfile != null && userProfile.isNotEmpty) {
      return p.normalize(userProfile);
    }
    return p.normalize(Directory.current.path);
  }

  String _resolveDefaultExportRootPath(String homeDirectory) {
    return p.join(homeDirectory, 'Documents', 'SoftEgg');
  }

  String _normalizeExportRoot(String rawPath, {required String homeDirectory}) {
    final trimmed = rawPath.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Export root 경로가 비어 있습니다.');
    }

    String resolvedPath;
    if (trimmed == '~') {
      resolvedPath = homeDirectory;
    } else if (trimmed.startsWith('~/') || trimmed.startsWith(r'~\')) {
      resolvedPath = p.join(homeDirectory, trimmed.substring(2));
    } else {
      resolvedPath = trimmed;
    }

    if (!p.isAbsolute(resolvedPath)) {
      throw const FormatException('Export root는 절대 경로로 입력해야 합니다.');
    }

    return _migrateSandboxedDocumentsPath(
      p.normalize(resolvedPath),
      homeDirectory: homeDirectory,
    );
  }

  String? _extractMacOsUserHome(String? homePath) {
    if (homePath == null || homePath.trim().isEmpty) {
      return null;
    }

    final normalized = p.normalize(homePath);
    final match = RegExp(
      r'^(/Users/[^/]+)/Library/Containers/[^/]+/Data(?:/.*)?$',
    ).firstMatch(normalized);
    if (match == null) {
      return null;
    }
    return match.group(1);
  }

  String _migrateSandboxedDocumentsPath(
    String resolvedPath, {
    required String homeDirectory,
  }) {
    if (!Platform.isMacOS) {
      return resolvedPath;
    }

    final normalizedHome = p.normalize(homeDirectory);
    final escapedHome = RegExp.escape(normalizedHome);
    final pattern = RegExp(
      '^$escapedHome/Library/Containers/[^/]+/Data/Documents(?:/(.*))?\$',
    );
    final match = pattern.firstMatch(resolvedPath);
    if (match == null) {
      return resolvedPath;
    }

    final suffix = match.group(1);
    return suffix == null || suffix.isEmpty
        ? p.join(normalizedHome, 'Documents')
        : p.join(normalizedHome, 'Documents', suffix);
  }

  String? _readEnv(String key) {
    final value = Platform.environment[key];
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    return value;
  }
}

class _AppEmbeddedConfig {
  const _AppEmbeddedConfig._();

  // 단일 실행 파일 배포를 위해 운영 연결 정보를 앱 내부에 포함합니다.
  static const String apiBaseUrl = String.fromEnvironment(
    'SOFTEGG_API_BASE_URL',
    defaultValue: 'https://licensehub.ilycode.app',
  );
  static const String ftpHost = String.fromEnvironment(
    'SOFTEGG_FTP_HOST',
    defaultValue: 'ilysrv.ddns.net',
  );
  static const String ftpUser = String.fromEnvironment(
    'SOFTEGG_FTP_USER',
    defaultValue: 'asdf',
  );
  static const String ftpPassword = String.fromEnvironment(
    'SOFTEGG_FTP_PASSWORD',
    defaultValue: 'Emfndhk!',
  );
}
