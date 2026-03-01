import 'package:flutter/material.dart';

import '../domain/installer_models.dart';
import '../state/softegg_controller.dart';

class SoftEggPage extends StatefulWidget {
  const SoftEggPage({super.key, required this.controller});

  final SoftEggController controller;

  @override
  State<SoftEggPage> createState() => _SoftEggPageState();
}

class _SoftEggPageState extends State<SoftEggPage> {
  late final TextEditingController _partnerController;

  SoftEggController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _partnerController = TextEditingController(text: controller.partnerCode);
  }

  @override
  void dispose() {
    _partnerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        if (_partnerController.text != controller.partnerCode) {
          _partnerController.value = _partnerController.value.copyWith(
            text: controller.partnerCode,
            selection: TextSelection.collapsed(
              offset: controller.partnerCode.length,
            ),
          );
        }

        return Scaffold(
          body: ColoredBox(
            color: const Color(0xFF0B1220),
            child: Center(
              child: SizedBox(
                width: 1280,
                height: 1024,
                child: ColoredBox(
                  color: const Color(0xFF0F172A),
                  child: Column(
                    children: <Widget>[
                      _buildHeader(),
                      _buildStepBar(),
                      Expanded(child: _buildBody()),
                      _buildFooter(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 88,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.egg_alt_rounded, color: Color(0xFF0DCCF2)),
          const SizedBox(width: 8),
          const Text(
            'SoftEgg',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: const Color(0xFF0DCCF2).withValues(alpha: 0.12),
            ),
            child: const Text('Windows / macOS · .segg 오프라인 패키지 생성기'),
          ),
        ],
      ),
    );
  }

  Widget _buildStepBar() {
    const labels = <String>[
      '1 파트너 필터',
      '2 메인 선택',
      '3 패키징',
      '4 완료',
    ];

    return Container(
      height: 66,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF1E293B))),
      ),
      child: Row(
        children: List<Widget>.generate(labels.length, (index) {
          final active = controller.currentStep == index;
          final done = controller.currentStep > index;
          return Expanded(
            child: InkWell(
              onTap: () => controller.moveToStep(index),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(
                    done
                        ? Icons.check_circle
                        : (active
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked),
                    color: done || active
                        ? const Color(0xFF0DCCF2)
                        : const Color(0xFF64748B),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    labels[index],
                    style: TextStyle(
                      color: done || active
                          ? const Color(0xFF0DCCF2)
                          : const Color(0xFF94A3B8),
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildBody() {
    switch (controller.currentStep) {
      case 0:
        return _buildStep1();
      case 1:
        return _buildStep2();
      case 2:
        return _buildStep3();
      case 3:
        return _buildStep4();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildStep1() {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'Step 1/4 · 파트너 필터 입력',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          const Text(
            '파트너 로그인 후 권한 범위 내 메인 SW를 선택해 바이너리 포함 .segg를 생성하거나 기존 파일을 수정합니다.',
            style: TextStyle(color: Color(0xFF94A3B8)),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: 360,
            child: TextField(
              controller: _partnerController,
              maxLength: 4,
              style: const TextStyle(
                fontSize: 32,
                letterSpacing: 18,
                fontWeight: FontWeight.w700,
              ),
              textCapitalization: TextCapitalization.characters,
              onChanged: controller.updatePartnerCode,
              decoration: InputDecoration(
                labelText: 'Partner Code',
                hintText: 'PA01',
                counterText: '',
                filled: true,
                fillColor: const Color(0xFF1E293B),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            controller.partnerCodeFormatValid
                ? '형식 확인됨: 영문+숫자 4자리'
                : '형식 요구사항: 영문+숫자 4자리',
            style: TextStyle(
              color: controller.partnerCodeFormatValid
                  ? const Color(0xFF22C55E)
                  : const Color(0xFFF59E0B),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: <Widget>[
              const Text(
                '기존 .segg 파일 불러오기',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: '목록 새로고침',
                onPressed: controller.isBusy
                    ? null
                    : () => controller.refreshSnapshots(),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (controller.snapshots.isEmpty)
            const Text(
              '불러올 .segg 파일이 없습니다.',
              style: TextStyle(color: Color(0xFFF59E0B)),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: controller.selectedSnapshotPath,
                  hint: const Text('편집할 스냅샷 선택'),
                  dropdownColor: const Color(0xFF0F172A),
                  items: controller.snapshots.map((item) {
                    return DropdownMenuItem<String>(
                      value: item.path,
                      child: Text(
                        '${item.fileName}  (${_formatDateTime(item.modifiedAt)})',
                      ),
                    );
                  }).toList(growable: false),
                  onChanged: (value) => controller.selectSnapshotPath(value),
                ),
              ),
            ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: controller.isBusy
                ? null
                : () async {
                    final error = await controller.loadSnapshotForEdit();
                    if (error != null && mounted) {
                      _showSnack(error);
                    }
                  },
            icon: const Icon(Icons.file_open),
            label: const Text('선택 파일 불러와 수정'),
          ),
        ],
      ),
    );
  }

  Widget _buildStep2() {
    final selectedMain = controller.selectedMainSoftware;
    final selectedVersion = controller.selectedVersionDefinition;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        children: <Widget>[
          Expanded(
            child: ListView(
              children: <Widget>[
                const Text(
                  'Step 2/4 · 메인 SW 및 버전 선택',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                const Text(
                  '파트너 권한 범위 내 메인 SW 1개와 의존 SW 버전을 확정합니다.',
                  style: TextStyle(color: Color(0xFF94A3B8)),
                ),
                const SizedBox(height: 18),
                _buildDropdownBox(
                  label: '메인 SW',
                  value: controller.selectedMainSoftwareId,
                  items: controller.filteredMainSoftware
                      .map(
                        (software) => DropdownMenuItem<String>(
                          value: software.id,
                          child: Text(software.name),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) => controller.selectMainSoftware(value),
                ),
                const SizedBox(height: 14),
                _buildDropdownBox(
                  label: '메인 SW 버전',
                  value: controller.selectedMainVersion,
                  items:
                      (selectedMain?.versions ?? <SoftwareVersionDefinition>[])
                          .map(
                            (version) => DropdownMenuItem<String>(
                              value: version.version,
                              child: Text(version.version),
                            ),
                          )
                          .toList(growable: false),
                  onChanged: (value) => controller.selectMainVersion(value),
                ),
                const SizedBox(height: 22),
                const Text(
                  '의존 SW 버전 선택',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                ...((selectedVersion?.dependencies ?? <DependencyOption>[])
                    .map((dep) {
                      final selected =
                          controller.selectedDependencyVersions[dep.id] ??
                          dep.defaultVersion;
                      return Card(
                        color: const Color(0xFF1E293B),
                        margin: const EdgeInsets.only(bottom: 10),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: <Widget>[
                              Expanded(child: Text(dep.name)),
                              const SizedBox(width: 12),
                              SizedBox(
                                width: 210,
                                child: _buildDropdownBox(
                                  label: null,
                                  value: selected,
                                  background: const Color(0xFF0F172A),
                                  items: dep.supportedVersions
                                      .map(
                                        (version) => DropdownMenuItem<String>(
                                          value: version,
                                          child: Text(version),
                                        ),
                                      )
                                      .toList(growable: false),
                                  onChanged: (value) => controller
                                      .selectDependencyVersion(dep.id, value),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    })
                    .toList(growable: false)),
              ],
            ),
          ),
          const SizedBox(width: 18),
          SizedBox(width: 360, child: _buildSnapshotSummary()),
        ],
      ),
    );
  }

  Widget _buildStep3() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Step 3/4 · 패키징 진행',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 16),
                LinearProgressIndicator(
                  value: controller.isBusy ? controller.progress : 0,
                  minHeight: 10,
                  backgroundColor: const Color(0xFF334155),
                  color: const Color(0xFF0DCCF2),
                ),
                const SizedBox(height: 12),
                Text(
                  controller.isBusy
                      ? '패키징 진행 중 ${(controller.progress * 100).toStringAsFixed(0)}%'
                      : '패키징 실행 대기 중',
                  style: const TextStyle(color: Color(0xFF94A3B8)),
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xFF111827),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF1E293B)),
                    ),
                    child: ListView.builder(
                      padding: const EdgeInsets.all(14),
                      itemCount: controller.logs.length,
                      itemBuilder: (context, index) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            controller.logs[index],
                            style: const TextStyle(
                              color: Color(0xFFCBD5E1),
                              fontFamily: 'monospace',
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 18),
          SizedBox(width: 360, child: _buildSnapshotSummary()),
        ],
      ),
    );
  }

  Widget _buildStep4() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Card(
              color: const Color(0xFF111827),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text(
                      'Step 4/4 · 완료',
                      style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '.segg 단일 파일 생성이 완료되었습니다. InstallHub에서 오프라인 설치로 바로 로드 가능합니다.',
                      style: TextStyle(color: Color(0xFF94A3B8)),
                    ),
                    const SizedBox(height: 18),
                    if (controller.generatedSnapshotPath != null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0DCCF2).withValues(alpha: 0.12),
                          border: Border.all(
                            color: const Color(0xFF0DCCF2).withValues(alpha: 0.4),
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text('생성 파일: ${controller.generatedSnapshotPath}'),
                      ),
                    const SizedBox(height: 14),
                    const Text(
                      '같은 파트너 코드로 기존 파일을 불러와 스냅샷을 수정할 수 있습니다.',
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 18),
          SizedBox(width: 360, child: _buildSnapshotSummary(showList: true)),
        ],
      ),
    );
  }

  Widget _buildSnapshotSummary({bool showList = false}) {
    return Card(
      color: const Color(0xFF111827),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'SoftEgg 스냅샷 요약',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            if (controller.currentSnapshot == null)
              const Text(
                '아직 생성/로드된 스냅샷이 없습니다.',
                style: TextStyle(color: Color(0xFF94A3B8)),
              )
            else ...<Widget>[
              Text(
                '${controller.currentSnapshot!.softwareName} '
                '${controller.currentSnapshot!.version}',
              ),
              const SizedBox(height: 4),
              Text(
                'Partner ${controller.currentSnapshot!.partnerCode}',
                style: const TextStyle(color: Color(0xFF94A3B8)),
              ),
              const SizedBox(height: 4),
              Text(
                '의존성 ${controller.currentSnapshot!.dependencyVersions.length}개',
                style: const TextStyle(color: Color(0xFF94A3B8)),
              ),
              const SizedBox(height: 4),
              Text(
                '바이너리 ${controller.currentSnapshot!.binaryFiles.length}개 · '
                '오프라인 설치 ${controller.currentSnapshot!.isOfflineInstallReady ? '가능' : '불가'}',
                style: const TextStyle(color: Color(0xFF94A3B8)),
              ),
            ],
            if (showList) ...<Widget>[
              const SizedBox(height: 14),
              const Divider(color: Color(0xFF334155)),
              const SizedBox(height: 8),
              const Text(
                '최근 생성 파일',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: controller.snapshots.isEmpty
                    ? const Text('파일 없음', style: TextStyle(color: Color(0xFF94A3B8)))
                    : ListView(
                        children: controller.snapshots.map((item) {
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(item.fileName),
                            subtitle: Text(_formatDateTime(item.modifiedAt)),
                            onTap: () => controller.selectSnapshotPath(item.path),
                          );
                        }).toList(growable: false),
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      height: 78,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFF1E293B))),
      ),
      child: Row(
        children: <Widget>[
          Text(
            controller.isBusy ? '작업 진행 중...' : '대기 중',
            style: const TextStyle(color: Color(0xFF94A3B8)),
          ),
          const Spacer(),
          OutlinedButton(
            onPressed: controller.currentStep > 0 && !controller.isBusy
                ? () => controller.moveToStep(controller.currentStep - 1)
                : null,
            child: const Text('이전'),
          ),
          const SizedBox(width: 10),
          FilledButton(
            onPressed: controller.isBusy ? null : _onPrimaryPressed,
            child: Text(_primaryLabel()),
          ),
        ],
      ),
    );
  }

  Future<void> _onPrimaryPressed() async {
    switch (controller.currentStep) {
      case 0:
        final error = controller.applyPartnerFilter();
        if (error != null) {
          _showSnack(error);
        }
        return;
      case 1:
        controller.moveToStep(2);
        return;
      case 2:
        final error = await controller.generateSnapshot();
        if (error != null) {
          _showSnack(error);
        }
        return;
      case 3:
        _showSnack('생성된 .segg 파일을 InstallHub에서 로드해 설치를 진행하세요.');
        return;
    }
  }

  String _primaryLabel() {
    switch (controller.currentStep) {
      case 0:
        return '필터 적용 후 다음';
      case 1:
        return '패키징 단계로';
      case 2:
        return '스냅샷 생성';
      case 3:
        return '완료';
      default:
        return '다음';
    }
  }

  Widget _buildDropdownBox({
    required String? label,
    required String? value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String> onChanged,
    Color background = const Color(0xFF1E293B),
  }) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: background,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          dropdownColor: const Color(0xFF0F172A),
          items: items,
          onChanged: (next) {
            if (next != null) {
              onChanged(next);
            }
          },
        ),
      ),
    );
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _formatDateTime(DateTime dateTime) {
    final local = dateTime.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}
