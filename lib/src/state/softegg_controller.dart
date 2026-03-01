import 'package:flutter/foundation.dart';

import '../domain/installer_models.dart';
import '../domain/software_seed.dart';
import '../services/install_runtime_service.dart';
import '../services/softegg_snapshot_service.dart';

class SoftEggController extends ChangeNotifier {
  SoftEggController({
    required SoftEggSnapshotService snapshotService,
    required InstallRuntimeService runtime,
  }) : _snapshotService = snapshotService,
       _runtime = runtime;

  final SoftEggSnapshotService _snapshotService;
  final InstallRuntimeService _runtime;

  bool _initialized = false;
  bool _isBusy = false;
  int _currentStep = 0;
  String _partnerCode = '';
  bool _partnerApplied = false;

  List<SoftwareDefinition> _filteredMainSoftware = <SoftwareDefinition>[];
  String? _selectedMainSoftwareId;
  String? _selectedMainVersion;
  Map<String, String> _selectedDependencyVersions = <String, String>{};

  List<SoftEggSnapshotRef> _snapshots = <SoftEggSnapshotRef>[];
  String? _selectedSnapshotPath;
  SoftEggSnapshot? _currentSnapshot;
  String? _generatedSnapshotPath;

  List<String> _logs = <String>[];
  double _progress = 0;

  bool get initialized => _initialized;
  bool get isBusy => _isBusy;
  int get currentStep => _currentStep;
  String get partnerCode => _partnerCode;
  bool get partnerApplied => _partnerApplied;
  List<SoftwareDefinition> get filteredMainSoftware => _filteredMainSoftware;
  String? get selectedMainSoftwareId => _selectedMainSoftwareId;
  String? get selectedMainVersion => _selectedMainVersion;
  Map<String, String> get selectedDependencyVersions =>
      _selectedDependencyVersions;
  List<SoftEggSnapshotRef> get snapshots => _snapshots;
  String? get selectedSnapshotPath => _selectedSnapshotPath;
  SoftEggSnapshot? get currentSnapshot => _currentSnapshot;
  String? get generatedSnapshotPath => _generatedSnapshotPath;
  List<String> get logs => _logs;
  double get progress => _progress;

  bool get partnerCodeFormatValid =>
      RegExp(r'^[A-Z0-9]{4}$').hasMatch(_partnerCode.toUpperCase());

  SoftwareDefinition? get selectedMainSoftware {
    if (_selectedMainSoftwareId == null) {
      return null;
    }
    for (final software in _filteredMainSoftware) {
      if (software.id == _selectedMainSoftwareId) {
        return software;
      }
    }
    return null;
  }

  SoftwareVersionDefinition? get selectedVersionDefinition {
    final software = selectedMainSoftware;
    final version = _selectedMainVersion;
    if (software == null || version == null) {
      return null;
    }
    for (final definition in software.versions) {
      if (definition.version == version) {
        return definition;
      }
    }
    return null;
  }

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _isBusy = true;
    notifyListeners();

    _snapshots = await _snapshotService.listSnapshots();

    _isBusy = false;
    _initialized = true;
    notifyListeners();
  }

  Future<void> refreshSnapshots() async {
    _snapshots = await _snapshotService.listSnapshots();
    if (_selectedSnapshotPath != null &&
        !_snapshots.any((item) => item.path == _selectedSnapshotPath)) {
      _selectedSnapshotPath = null;
    }
    notifyListeners();
  }

  void selectSnapshotPath(String? path) {
    _selectedSnapshotPath = path;
    notifyListeners();
  }

  void updatePartnerCode(String value) {
    _partnerCode = value.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (_partnerCode.length > 4) {
      _partnerCode = _partnerCode.substring(0, 4);
    }
    notifyListeners();
  }

  String? applyPartnerFilter() {
    if (!partnerCodeFormatValid) {
      return '파트너 코드는 영문+숫자 4자리여야 합니다.';
    }

    final allowedIds = kPartnerSoftwareAccess[_partnerCode.toUpperCase()];
    if (allowedIds == null || allowedIds.isEmpty) {
      return '등록되지 않은 파트너 코드입니다.';
    }

    _filteredMainSoftware = kMainSoftwareCatalog
        .where((software) => allowedIds.contains(software.id))
        .toList(growable: false);

    if (_filteredMainSoftware.isEmpty) {
      return '선택 가능한 메인 SW가 없습니다.';
    }

    _partnerApplied = true;
    _currentStep = 1;
    _setDefaultsForMain(_filteredMainSoftware.first);
    notifyListeners();
    return null;
  }

  Future<String?> loadSnapshotForEdit() async {
    if (!partnerCodeFormatValid) {
      return '파일 로드 전 파트너 코드를 먼저 입력해주세요.';
    }
    final path = _selectedSnapshotPath;
    if (path == null || path.isEmpty) {
      return '불러올 .segg 파일을 선택해주세요.';
    }

    SoftEggSnapshot snapshot;
    try {
      snapshot = await _snapshotService.loadSnapshot(path);
    } catch (e) {
      return '스냅샷을 읽을 수 없습니다: $e';
    }

    if (snapshot.partnerCode.toUpperCase() != _partnerCode.toUpperCase()) {
      return '해당 파일은 현재 파트너 코드와 일치하지 않습니다.';
    }

    final allowedIds = kPartnerSoftwareAccess[_partnerCode.toUpperCase()];
    if (allowedIds == null || !allowedIds.contains(snapshot.softwareId)) {
      return '현재 파트너 권한으로는 해당 스냅샷을 수정할 수 없습니다.';
    }

    final software = kMainSoftwareCatalog.firstWhereOrNull(
      (item) => item.id == snapshot.softwareId,
    );
    if (software == null) {
      return '현재 카탈로그에 없는 SW입니다.';
    }

    final selectedVersion =
        software.versions.firstWhereOrNull(
          (item) => item.version == snapshot.version,
        ) ??
        software.versions.first;

    _filteredMainSoftware = <SoftwareDefinition>[software];
    _selectedMainSoftwareId = software.id;
    _selectedMainVersion = selectedVersion.version;
    _partnerApplied = true;
    _currentStep = 1;
    _currentSnapshot = snapshot;

    final restored = <String, String>{};
    for (final dep in selectedVersion.dependencies) {
      final value = snapshot.dependencyVersions[dep.id];
      restored[dep.id] = dep.supportedVersions.contains(value)
          ? value!
          : dep.defaultVersion;
    }
    _selectedDependencyVersions = restored;

    notifyListeners();
    return null;
  }

  void selectMainSoftware(String softwareId) {
    final software = _filteredMainSoftware.firstWhere(
      (s) => s.id == softwareId,
      orElse: () => _filteredMainSoftware.first,
    );
    _setDefaultsForMain(software);
    notifyListeners();
  }

  void selectMainVersion(String version) {
    _selectedMainVersion = version;
    _rebuildDependencyDefaults();
    notifyListeners();
  }

  void selectDependencyVersion(String dependencyId, String version) {
    _selectedDependencyVersions = <String, String>{
      ..._selectedDependencyVersions,
      dependencyId: version,
    };
    notifyListeners();
  }

  void moveToStep(int step) {
    if (step < 0 || step > 3) {
      return;
    }
    if (step > 0 && !_partnerApplied) {
      return;
    }
    if (step > 1 && selectedVersionDefinition == null) {
      return;
    }
    if (step > 2 && _generatedSnapshotPath == null) {
      return;
    }
    _currentStep = step;
    notifyListeners();
  }

  Future<String?> generateSnapshot() async {
    final software = selectedMainSoftware;
    final version = selectedVersionDefinition;
    if (software == null || version == null) {
      return '메인 SW와 버전을 먼저 선택해주세요.';
    }

    _isBusy = true;
    _progress = 0;
    _logs = <String>[];
    notifyListeners();

    try {
      _appendLog('메인/의존 바이너리 수집 중...', 0.20);
      await Future<void>.delayed(const Duration(milliseconds: 180));
      _appendLog('오프라인 설치 메타데이터 구성 중...', 0.45);
      await Future<void>.delayed(const Duration(milliseconds: 180));
      _appendLog('전용 압축 모델(.segg) 생성 중...', 0.75);

      final snapshot = _runtime.buildSnapshot(
        partnerCode: _partnerCode,
        software: software,
        version: version,
        selectedDependencyVersions: _selectedDependencyVersions,
      );

      final ref = await _snapshotService.saveSnapshot(snapshot);
      _appendLog('스냅샷 파일 생성 완료: ${ref.fileName}', 1.0);

      _currentSnapshot = snapshot;
      _generatedSnapshotPath = ref.path;
      _currentStep = 3;
      _snapshots = await _snapshotService.listSnapshots();
      return null;
    } catch (e) {
      return '스냅샷 생성 중 오류가 발생했습니다: $e';
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  void _appendLog(String message, double nextProgress) {
    _logs = <String>[..._logs, message];
    _progress = nextProgress;
    notifyListeners();
  }

  void _setDefaultsForMain(SoftwareDefinition software) {
    _selectedMainSoftwareId = software.id;
    _selectedMainVersion = software.versions.first.version;
    _rebuildDependencyDefaults();
  }

  void _rebuildDependencyDefaults() {
    final selected = selectedVersionDefinition;
    if (selected == null) {
      _selectedDependencyVersions = <String, String>{};
      return;
    }

    final current = <String, String>{};
    for (final dep in selected.dependencies) {
      current[dep.id] = dep.defaultVersion;
    }
    _selectedDependencyVersions = current;
  }
}

extension<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T item) test) {
    for (final item in this) {
      if (test(item)) {
        return item;
      }
    }
    return null;
  }
}
