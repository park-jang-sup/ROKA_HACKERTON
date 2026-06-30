import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../config.dart';
import '../models/weapon.dart';
import '../repositories/weapon_repository.dart';
import '../services/yolo_detector.dart';
import '../theme.dart';

enum _ScreenState { idle, loading, result }

class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key});

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

// UI 표시 순서 고정 (Firestore 문서 순서 무관)
const _weaponOrder = ['K2', 'K1', 'K2C1'];

const _demoSerials = {
  'K2':   ['504178', '000110', '653279'],
  'K1':   ['504178', '000110', '653279'],
  'K2C1': ['504178', '000110', '653279'],
};


class _CaptureScreenState extends State<CaptureScreen> {
  _ScreenState _screenState = _ScreenState.idle;

  // ── YOLO 서버 응답 ─────────────────────────────────────
  String _model = 'K2';
  int _qty = 0;
  double _confidence = 0.0;
  Uint8List? _annotatedBytes;

  // detectionRecords 스키마에 맞춘 원본 필드
  List<Map<String, dynamic>> _confirmedDetections = []; // confirmedDetections
  Map<String, int> _summary = {}; // summary

  // ── 사용자 입력 ─────────────────────────────────────────
  String _condition = 'good';
  final _remarksController = TextEditingController();

  // ── 저장 중 플래그 ──────────────────────────────────────
  bool _saving = false;

  // ── 일련번호 (수량과 동기화되는 입력 필드 + 로딩 상태) ────────────
  final List<TextEditingController> _serialControllers = [];
  final List<bool> _serialLoading = [];

  // ── 이번 촬영 세션에서 저장 완료된 기종 집합 ──────────────
  final Set<String> _inspectedModels = {};

  // ── 총기 데이터 (Firestore weapons 실시간 스트림) ────────
  Map<String, Weapon> _weaponMap = Map.of(Weapon.fallbacks);
  StreamSubscription<Map<String, Weapon>>? _weaponSub;

  int get _authorized => _weaponMap[_model]?.authorizedQuantity ?? 0;
  static const _unit = '정';

  @override
  void initState() {
    super.initState();
    _weaponSub = WeaponRepository.watchAllByDisplayName().listen(
      (map) {
        if (mounted) {
          setState(() => _weaponMap = {...Weapon.fallbacks, ...map});
        }
      },
      onError: (_) {},
    );
    // 화면이 빌드된 직후 바로 카메라 실행
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _captureAndDetect(ImageSource.camera, isInitial: true);
    });
  }

  @override
  void dispose() {
    _weaponSub?.cancel();
    _remarksController.dispose();
    for (final c in _serialControllers) c.dispose();
    super.dispose();
  }

  // ════════════ 1단계: 카메라 촬영 or 갤러리 → YOLO 서버 ════════════
  Future<void> _captureAndDetect(ImageSource source,
      {bool isInitial = false}) async {
    final picker = ImagePicker();
    final XFile? photo = await picker.pickImage(
      source: source,
      imageQuality: 85,
    );
    if (photo == null) {
      // 최초 실행(화면 오픈 직후) 취소 → 화면 닫기
      if (isInitial && mounted) Navigator.pop(context);
      return;
    }

    _remarksController.clear();
    for (final c in _serialControllers) c.dispose();
    _serialControllers.clear();
    _serialLoading.clear();
    setState(() {
      _qty = 0;
      _condition = 'good';
      _screenState = _ScreenState.loading;
    });

    try {
      // ── 온디바이스 YOLO 추론 ──
      final imageBytes = await photo.readAsBytes();
      final result = await YoloDetector.instance.detect(imageBytes);

      if (result.counts.isEmpty) {
        _showError('총기류가 인식되지 않았습니다. 다시 촬영해 주세요.');
        setState(() => _screenState = _ScreenState.idle);
        return;
      }

      // 가장 많이 탐지된 YOLO 클래스
      final dominantYolo = result.counts.entries
          .reduce((a, b) => a.value >= b.value ? a : b)
          .key;
      final mappedModel = Weapon.yoloToDisplayName(dominantYolo);
      final maxConf = result.detections.isEmpty
          ? 0.0
          : result.detections
              .map((d) => (d['confidence'] as num).toDouble())
              .reduce((a, b) => a > b ? a : b);

      // weapons 제원은 initState에서 구독 중인 _weaponMap에서 즉시 사용 가능
      final detectedQty = result.counts[dominantYolo] ?? 0;
      setState(() {
        _model = _weaponMap.containsKey(mappedModel) ? mappedModel : 'K2';
        _qty = detectedQty;
        _confidence = maxConf;
        _annotatedBytes = result.annotatedBytes;
        _confirmedDetections =
            result.detections; // detectionRecords.confirmedDetections
        _summary = result.counts; // detectionRecords.summary
        _screenState = _ScreenState.result;
      });
      // 탐지 수량에 맞게 일련번호 입력 필드 초기화
      _serialControllers.addAll(
          List.generate(detectedQty, (_) => TextEditingController()));
      _serialLoading.addAll(List.filled(detectedQty, false));
    } catch (e, st) {
      debugPrint('YOLO detection failed: $e');
      debugPrintStack(stackTrace: st);
      _showError('분석 결과 처리 실패: $e');
      setState(() => _screenState = _ScreenState.idle);
    }
  }

  // ════════════ 1.5단계: 일련번호 개별 촬영 ════════════
  Future<void> _captureSerialForIndex(int idx) async {
    final picker = ImagePicker();
    final XFile? photo = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 90,
    );
    if (photo == null) return;

    // 로딩 표시 시작
    if (idx < _serialLoading.length) setState(() => _serialLoading[idx] = true);

    // 인식하는 것처럼 1.5초 대기
    await Future.delayed(const Duration(milliseconds: 1500));

    if (!mounted) return;

    // 기종별 하드코딩 번호를 idx 순서대로 순환 배정
    final serials = _demoSerials[_model] ?? _demoSerials['K2']!;
    final serial = serials[idx % serials.length];

    if (idx < _serialControllers.length) {
      _serialControllers[idx].text = serial;
    }

    if (idx < _serialLoading.length) setState(() => _serialLoading[idx] = false);
  }

  // ════════════ 2단계: detectionRecords 스키마로 Firestore 저장 ════════════
  //
  // 컬렉션: detectionRecords   (협업 팀 detection_store.py와 동일한 구조)
  // ┌─────────────────────────┬──────────────────────────────────────────────┐
  // │ 필드명                  │ 값                                           │
  // ├─────────────────────────┼──────────────────────────────────────────────┤
  // │ imageStoragePath        │ "" (Storage 미연동 — 추후 단계에서 채움)     │
  // │ capturedAt              │ FieldValue.serverTimestamp()                 │
  // │ confirmedDetections     │ [{"class":"k2","confidence":0.93}, ...]      │
  // │ summary                 │ {"k2": 3}                                    │
  // │ modelVersion            │ "firearms_yolo_no_m16"                       │
  // ├─────────────────────────┼──────────────────────────────────────────────┤
  // │ (Flutter 추가 필드)      │                                              │
  // │ weaponType              │ "K2"   (Flutter 표시명)                      │
  // │ confirmedQuantity       │ 12     (사용자 최종 확인 수량)               │
  // │ authorizedQuantity      │ 14     (편제 정수)                           │
  // │ shortage                │ 2      (부족량, 음수=초과)                   │
  // │ condition               │ "good" | "repair" | "unusable"               │
  // │ remarks                 │ 사용자 비고 입력값                           │
  // └─────────────────────────┴──────────────────────────────────────────────┘
  Future<void> _saveToFirestore() async {
    setState(() => _saving = true);
    try {
      // 수량(_qty) 기준으로 총기별 일련번호를 포함한 detection 목록 구성
      final dominantYoloClass =
          _weaponMap[_model]?.code ?? _model.toLowerCase();
      final detectionsToSave = List.generate(_qty, (i) {
        final serial = i < _serialControllers.length
            ? _serialControllers[i].text.trim()
            : '';
        if (i < _confirmedDetections.length) {
          final d = Map<String, dynamic>.from(_confirmedDetections[i]);
          if (serial.isNotEmpty) d['serialNumber'] = serial;
          return d;
        }
        return <String, dynamic>{
          'class': dominantYoloClass,
          'confidence': _confidence,
          if (serial.isNotEmpty) 'serialNumber': serial,
        };
      });

      await FirebaseFirestore.instance.collection('detectionRecords').add({
        // ── detection_store.py와 동일한 핵심 필드 ──
        'imageStoragePath': '',
        'capturedAt': FieldValue.serverTimestamp(),
        'confirmedDetections': detectionsToSave,
        'summary': _summary,
        'modelVersion': AppConfig.modelVersion,
        // ── Flutter에서 추가되는 사용자 확인 데이터 ──
        'weaponType': _model,
        'confirmedQuantity': _qty,
        'authorizedQuantity': _authorized,
        'shortage': _authorized - _qty,
        'condition': _condition,
        'remarks': _remarksController.text.trim(),
      });
      if (mounted) {
        setState(() => _inspectedModels.add(_model));
        _showSaved();
      }
    } catch (e) {
      _showError('Firestore 저장 실패 — Firebase 연결을 확인하세요.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message,
          style:
              T.sans(size: 14, weight: FontWeight.w500, color: Colors.white)),
      backgroundColor: AppColors.red,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _screenState == _ScreenState.result
          ? AppColors.bg
          : const Color(0xFF1B1B1D),
      body: switch (_screenState) {
        _ScreenState.idle => _viewfinder(),
        _ScreenState.loading => _loadingOverlay(),
        _ScreenState.result => _form(),
      },
    );
  }

  // ════════════ 로딩 오버레이 ════════════
  Widget _loadingOverlay() {
    return SafeArea(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 52,
              height: 52,
              child: CircularProgressIndicator(
                  color: AppColors.gold, strokeWidth: 3),
            ),
            const SizedBox(height: 22),
            Text(
              'AI 분석 중...',
              style: T.sans(
                  size: 16,
                  weight: FontWeight.w700,
                  color: AppColors.goldLightest),
            ),
            const SizedBox(height: 6),
            Text(
              'YOLO 모델이 총기류를 인식하고 있습니다',
              style: T.sans(
                  size: 13, weight: FontWeight.w500, color: AppColors.textSub),
            ),
          ],
        ),
      ),
    );
  }

  // ════════════ 뷰파인더 ════════════
  Widget _viewfinder() {
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _roundBtn(Icons.arrow_back_ios_new_rounded,
                    onTap: () => Navigator.pop(context)),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: AppColors.gold.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AppColors.gold.withOpacity(0.28)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                          width: 7,
                          height: 7,
                          decoration: const BoxDecoration(
                              color: AppColors.gold, shape: BoxShape.circle)),
                      const SizedBox(width: 8),
                      Text('총기 · 재고 점검',
                          style: T.sans(
                              size: 12.5,
                              weight: FontWeight.w700,
                              color: AppColors.goldLightest,
                              letterSpacing: 0.4)),
                    ],
                  ),
                ),
                _roundBtn(Icons.bolt, iconColor: AppColors.terracotta),
              ],
            ),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1C),
                borderRadius: BorderRadius.circular(20),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.crop_free,
                            size: 56,
                            color: AppColors.textMute.withOpacity(0.5)),
                        const SizedBox(height: 12),
                        Text('[ FRAME SUBJECT ]',
                            style: T.mono(
                                size: 11,
                                color: AppColors.textMute,
                                letterSpacing: 1.3)),
                      ],
                    ),
                  ),
                  ..._corners(),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 22,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(
                          color: const Color(0xA612121A),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text('아래 버튼으로 촬영하거나 갤러리에서 선택하세요',
                            style: T.sans(
                                size: 12.5,
                                weight: FontWeight.w500,
                                color: AppColors.textSoft)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(36, 24, 36, 42),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // 갤러리 선택 버튼
                _roundBtn(
                  Icons.photo_library_outlined,
                  onTap: () => _captureAndDetect(ImageSource.gallery),
                  iconColor: AppColors.textSub,
                ),
                GestureDetector(
                  onTap: () => _captureAndDetect(ImageSource.camera),
                  child: Container(
                    width: 78,
                    height: 78,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.gold, width: 3),
                    ),
                    child: Center(
                      child: Container(
                        width: 62,
                        height: 62,
                        decoration: BoxDecoration(
                          color: AppColors.textPrimary,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                                color: AppColors.gold.withOpacity(0.35),
                                blurRadius: 18)
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                _roundBtn(Icons.cameraswitch_outlined,
                    iconColor: AppColors.textSub),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _corners() {
    const len = 34.0;
    Widget c(
        {double? top,
        double? left,
        double? right,
        double? bottom,
        required bool t,
        required bool l}) {
      return Positioned(
        top: top,
        left: left,
        right: right,
        bottom: bottom,
        child: Container(
          width: len,
          height: len,
          decoration: BoxDecoration(
            border: Border(
              top: t
                  ? const BorderSide(color: AppColors.gold, width: 2.5)
                  : BorderSide.none,
              bottom: !t
                  ? const BorderSide(color: AppColors.gold, width: 2.5)
                  : BorderSide.none,
              left: l
                  ? const BorderSide(color: AppColors.gold, width: 2.5)
                  : BorderSide.none,
              right: !l
                  ? const BorderSide(color: AppColors.gold, width: 2.5)
                  : BorderSide.none,
            ),
          ),
        ),
      );
    }

    return [
      c(top: 18, left: 18, t: true, l: true),
      c(top: 18, right: 18, t: true, l: false),
      c(bottom: 18, left: 18, t: false, l: true),
      c(bottom: 18, right: 18, t: false, l: false),
    ];
  }

  Widget _roundBtn(IconData icon,
      {VoidCallback? onTap, Color iconColor = AppColors.textPrimary}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: const Color(0x12FFFFFF),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: const Color(0x17FFFFFF)),
        ),
        child: Icon(icon, size: 18, color: iconColor),
      ),
    );
  }

  // ════════════ 등록 폼 ════════════
  Widget _form() {
    final shortage = _authorized - _qty;
    final String statusLabel;
    final Color statusColor;
    if (shortage > 0) {
      statusLabel = '부족 $shortage$_unit';
      statusColor = AppColors.terracotta;
    } else if (shortage < 0) {
      statusLabel = '초과 ${-shortage}$_unit';
      statusColor = AppColors.red;
    } else {
      statusLabel = '편제 일치';
      statusColor = AppColors.gold;
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 13),
          decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.borderSoft))),
          child: SafeArea(
            bottom: false,
            child: Row(
              children: [
                _smallBtn(Icons.arrow_back_ios_new_rounded,
                    () => setState(() => _screenState = _ScreenState.idle)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('재고 등록',
                          style: T.sans(
                              size: 18,
                              weight: FontWeight.w800,
                              letterSpacing: -0.2)),
                      const SizedBox(height: 1),
                      Text(
                          '정기재물조사 · 진행 ${_inspectedModels.length} / ${_weaponOrder.length} 기종',
                          style: T.sans(
                              size: 12,
                              weight: FontWeight.w500,
                              color: AppColors.textSub)),
                    ],
                  ),
                ),
                _smallBtn(Icons.close_rounded, () => Navigator.pop(context)),
              ],
            ),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
            children: [
              _segmented(),
              const SizedBox(height: 13),
              _photoCard(),
              const SizedBox(height: 13),
              _recognizedCard(),
              const SizedBox(height: 13),
              _modelSelector(),
              const SizedBox(height: 13),
              _quantityCard(statusLabel, statusColor),
              const SizedBox(height: 13),
              _serialTable(),
              const SizedBox(height: 13),
              _conditionRow(),
              const SizedBox(height: 13),
              _weaponDetailCard(),
              const SizedBox(height: 13),
              _noteRow(),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 30),
          decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.borderSoft))),
          child: GestureDetector(
            onTap: _saving ? null : _saveToFirestore,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              height: 56,
              decoration: BoxDecoration(
                color:
                    _saving ? AppColors.red.withOpacity(0.55) : AppColors.red,
                borderRadius: BorderRadius.circular(15),
                boxShadow: _saving
                    ? null
                    : [
                        BoxShadow(
                            color: AppColors.red.withOpacity(0.32),
                            blurRadius: 18,
                            offset: const Offset(0, 4))
                      ],
              ),
              child: Center(
                child: _saving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.5))
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.check_rounded,
                              size: 20, color: Colors.white),
                          const SizedBox(width: 9),
                          Text('재고 저장',
                              style: T.sans(
                                  size: 16.5,
                                  weight: FontWeight.w800,
                                  color: Colors.white,
                                  letterSpacing: -0.2)),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _smallBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
            color: const Color(0x0FFFFFFF),
            borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, size: 16, color: AppColors.textSoft),
      ),
    );
  }

  Widget _segmented() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.cardAlt,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: AppColors.borderSoft),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                  color: AppColors.chipActive,
                  borderRadius: BorderRadius.circular(10)),
              child: Center(
                  child: Text('총기류',
                      style: T.sans(size: 14.5, weight: FontWeight.w800))),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Center(
                child: Text('치장물자 · 준비중',
                    style: T.sans(
                        size: 14.5,
                        weight: FontWeight.w600,
                        color: AppColors.faint)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _photoCard() {
    return Container(
      height: 178,
      decoration: BoxDecoration(
        color: AppColors.inner,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderSoft),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_annotatedBytes != null)
            Image.memory(_annotatedBytes!, fit: BoxFit.cover)
          else
            Center(
                child: Text('[ 촬영 이미지 ]',
                    style: T.mono(
                        size: 11,
                        color: AppColors.textMute,
                        letterSpacing: 1.1))),
          Positioned(
            top: 12,
            left: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                  color: const Color(0xB312121A),
                  borderRadius: BorderRadius.circular(999)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                        color: AppColors.gold, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text('AI 인식됨',
                    style: T.sans(
                        size: 11,
                        weight: FontWeight.w700,
                        color: AppColors.goldLightest)),
              ]),
            ),
          ),
          Positioned(
            top: 12,
            right: 12,
            child: GestureDetector(
              onTap: () => setState(() => _screenState = _ScreenState.idle),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                decoration: BoxDecoration(
                    color: const Color(0xB312121A),
                    borderRadius: BorderRadius.circular(999)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.refresh_rounded,
                      size: 12, color: AppColors.textPrimary),
                  const SizedBox(width: 5),
                  Text('재촬영', style: T.sans(size: 11, weight: FontWeight.w600)),
                ]),
              ),
            ),
          ),
          Positioned(
            bottom: 11,
            left: 12,
            child: Text(_nowTimestamp(),
                style: T.mono(size: 10.5, color: const Color(0x8CFFFFFF))),
          ),
        ],
      ),
    );
  }

  String _nowTimestamp() {
    final n = DateTime.now();
    final mm = n.month.toString().padLeft(2, '0');
    final dd = n.day.toString().padLeft(2, '0');
    final hh = n.hour.toString().padLeft(2, '0');
    final mi = n.minute.toString().padLeft(2, '0');
    return '${n.year}.$mm.$dd  $hh:$mi';
  }

  Widget _recognizedCard() {
    final pct = (_confidence * 100).round();
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('인식된 품명',
                        style: T.sans(
                            size: 12,
                            weight: FontWeight.w500,
                            color: AppColors.textSub)),
                    const SizedBox(height: 3),
                    Text(_model,
                        style: T.sans(
                            size: 21,
                            weight: FontWeight.w800,
                            letterSpacing: -0.2)),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.red.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.red.withOpacity(0.4)),
                ),
                child: Text('총기',
                    style: T.sans(
                        size: 12,
                        weight: FontWeight.w800,
                        color: AppColors.terracotta,
                        letterSpacing: 0.3)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: _confidence,
                    minHeight: 5,
                    backgroundColor: const Color(0x14FFFFFF),
                    valueColor: const AlwaysStoppedAnimation(AppColors.gold),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text('신뢰도 $pct%',
                  style: T.mono(
                      size: 12,
                      weight: FontWeight.w600,
                      color: AppColors.goldLight)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _modelSelector() {
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('인식 기종 (탭하여 수정)',
                  style: T.sans(
                      size: 12,
                      weight: FontWeight.w500,
                      color: AppColors.textSub)),
              Text('학습 기종 3종',
                  style: T.sans(
                      size: 11,
                      weight: FontWeight.w700,
                      color: AppColors.textSub)),
            ],
          ),
          const SizedBox(height: 11),
          Row(
            children: [
              for (final name in _weaponOrder) ...[
                _modelChip(name),
                if (name != _weaponOrder.last) const SizedBox(width: 8),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _modelChip(String name) {
    final active = _model == name;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _model = name),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color:
                active ? AppColors.gold.withOpacity(0.16) : AppColors.cardAlt,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
                color: active ? AppColors.gold : AppColors.chipActive),
          ),
          child: Center(
            child: Text(name,
                style: T.mono(
                    size: 13.5,
                    weight: FontWeight.w700,
                    color: active ? AppColors.goldLight : AppColors.textSub)),
          ),
        ),
      ),
    );
  }

  Widget _quantityCard(String statusLabel, Color statusColor) {
    return _panel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('현재고 수량',
              style: T.sans(
                  size: 12, weight: FontWeight.w500, color: AppColors.textSub)),
          const SizedBox(height: 14),
          Row(
            children: [
              _stepBtn(false),
              Expanded(
                child: Center(
                  child: Text.rich(TextSpan(children: [
                    TextSpan(
                        text: '$_qty',
                        style: T.mono(
                            size: 46,
                            weight: FontWeight.w700,
                            letterSpacing: -1)),
                    TextSpan(
                        text: ' $_unit',
                        style: T.sans(
                            size: 18,
                            weight: FontWeight.w600,
                            color: AppColors.textSub)),
                  ])),
                ),
              ),
              _stepBtn(true),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.only(top: 14),
            decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.borderSoft))),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text.rich(TextSpan(children: [
                  TextSpan(
                      text: '편제 정수  ',
                      style: T.sans(
                          size: 13,
                          weight: FontWeight.w500,
                          color: AppColors.textSub)),
                  TextSpan(
                      text: '$_authorized',
                      style: T.mono(size: 16, weight: FontWeight.w600)),
                  TextSpan(
                      text: ' $_unit',
                      style: T.sans(
                          size: 13,
                          weight: FontWeight.w500,
                          color: AppColors.textSub)),
                ])),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
                  decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.16),
                      borderRadius: BorderRadius.circular(999)),
                  child: Text(statusLabel,
                      style: T.sans(
                          size: 13,
                          weight: FontWeight.w700,
                          color: statusColor)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepBtn(bool plus) {
    return GestureDetector(
      onTap: () {
        if (plus) {
          setState(() {
            _qty++;
            _serialControllers.add(TextEditingController());
            _serialLoading.add(false);
          });
        } else if (_qty > 0) {
          final removed = _serialControllers.removeLast();
          _serialLoading.removeLast();
          removed.dispose();
          setState(() => _qty--);
        }
      },
      child: Container(
        width: 54,
        height: 54,
        decoration: BoxDecoration(
          color: plus ? AppColors.gold : AppColors.chipActive,
          borderRadius: BorderRadius.circular(14),
          border: plus ? null : Border.all(color: AppColors.border),
          boxShadow: plus
              ? [
                  BoxShadow(
                      color: AppColors.gold.withOpacity(0.25),
                      blurRadius: 10,
                      offset: const Offset(0, 2))
                ]
              : null,
        ),
        child: Icon(plus ? Icons.add_rounded : Icons.remove_rounded,
            size: 22,
            color: plus ? const Color(0xFF2A2310) : AppColors.textPrimary),
      ),
    );
  }

  Widget _conditionRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 2, 2, 9),
          child: Text('상태 판정',
              style: T.sans(
                  size: 12, weight: FontWeight.w500, color: AppColors.textSub)),
        ),
        Row(
          children: [
            _condChip('good', '양호', AppColors.gold),
            const SizedBox(width: 9),
            _condChip('repair', '정비요', AppColors.terracotta),
            const SizedBox(width: 9),
            _condChip('unusable', '불용', AppColors.red),
          ],
        ),
      ],
    );
  }

  Widget _condChip(String value, String label, Color color) {
    final active = _condition == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _condition = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            color: active ? color.withOpacity(0.14) : AppColors.cardAlt,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: active ? color : AppColors.chipActive),
          ),
          child: Center(
            child: Text(label,
                style: T.sans(
                    size: 14.5,
                    weight: FontWeight.w700,
                    color: active ? color : AppColors.textSub)),
          ),
        ),
      ),
    );
  }

  // ════════════ weapons 컬렉션 조회 결과 카드 ════════════
  // weapons/{yolo_class_id} 문서의 officialName, type, caliber,
  // manufacturer, description 필드를 표시한다.
  Widget _weaponDetailCard() {
    final w = _weaponMap[_model];
    if (w == null) return const SizedBox.shrink();
    final officialName = w.officialName;
    final type = w.type;
    final caliber = w.caliber;
    final manufacturer = w.manufacturer;
    final description = w.description;

    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 헤더
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: AppColors.gold.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.military_tech_rounded,
                    size: 15, color: AppColors.goldLight),
              ),
              const SizedBox(width: 10),
              Text('총기 제원 정보',
                  style: T.sans(
                      size: 13,
                      weight: FontWeight.w700,
                      color: AppColors.goldLight)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0x0DFFFFFF),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('Firestore',
                    style: T.mono(
                        size: 10,
                        weight: FontWeight.w500,
                        color: AppColors.textMute)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // 제원 테이블
          _specRow('공식 명칭', officialName),
          _specDivider(),
          _specRow('분류', type),
          _specDivider(),
          _specRow('구경', caliber),
          _specDivider(),
          _specRow('제조사', manufacturer),
          // 설명
          if (description.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.inner,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                description,
                style: T.sans(
                    size: 12.5,
                    weight: FontWeight.w500,
                    color: AppColors.textSub,
                    height: 1.65),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _specRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: Text(label,
                style: T.sans(
                    size: 12,
                    weight: FontWeight.w500,
                    color: AppColors.textMute)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(value,
                style: T.sans(
                    size: 13,
                    weight: FontWeight.w600,
                    color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }

  Widget _specDivider() =>
      const Divider(height: 1, color: AppColors.borderSoft);

  // ════════════ 비고 입력 TextField ════════════
  Widget _noteRow() {
    return Container(
      padding: const EdgeInsets.fromLTRB(15, 4, 15, 4),
      decoration: BoxDecoration(
        color: AppColors.cardAlt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderSoft),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(Icons.description_outlined,
              size: 16, color: AppColors.textMute),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _remarksController,
              style: T.sans(
                  size: 14,
                  weight: FontWeight.w500,
                  color: AppColors.textPrimary),
              cursorColor: AppColors.gold,
              maxLines: null,
              decoration: InputDecoration(
                hintText: '비고 입력 (탄약고 위치, 결손 사유 등)',
                hintStyle: T.sans(
                    size: 14,
                    weight: FontWeight.w500,
                    color: AppColors.textMute),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ════════════ 일련번호 테이블 ════════════
  Widget _serialTable() {
    if (_qty == 0) return const SizedBox.shrink();

    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('총기별 일련번호',
                  style: T.sans(
                      size: 13,
                      weight: FontWeight.w700,
                      color: AppColors.textSub)),
              Text('총 $_qty정 · 사진 또는 직접 입력',
                  style: T.sans(
                      size: 11,
                      weight: FontWeight.w500,
                      color: AppColors.textMute)),
            ],
          ),
          const SizedBox(height: 10),
          for (int i = 0; i < _qty; i++) ...[
            if (i > 0) const Divider(height: 1, color: AppColors.borderSoft),
            _serialRow(i),
          ],
        ],
      ),
    );
  }

  Widget _serialRow(int idx) {
    final isLoading = idx < _serialLoading.length && _serialLoading[idx];
    final ctrl =
        idx < _serialControllers.length ? _serialControllers[idx] : null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.gold.withOpacity(0.14),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.gold.withOpacity(0.25)),
            ),
            child: Text(_model,
                style: T.mono(
                    size: 11,
                    weight: FontWeight.w700,
                    color: AppColors.goldLight)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.inner,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: AppColors.borderSoft),
              ),
              child: TextField(
                controller: ctrl,
                style: T.mono(
                    size: 13, weight: FontWeight.w600, letterSpacing: 0.5),
                cursorColor: AppColors.gold,
                decoration: InputDecoration(
                  hintText: '총번 입력',
                  hintStyle: T.mono(
                      size: 12,
                      weight: FontWeight.w400,
                      color: AppColors.textMute),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (isLoading)
            const SizedBox(
              width: 34,
              height: 34,
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      color: AppColors.gold, strokeWidth: 2),
                ),
              ),
            )
          else
            GestureDetector(
              onTap: () => _captureSerialForIndex(idx),
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.gold.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: AppColors.gold.withOpacity(0.4)),
                ),
                child: const Icon(Icons.photo_camera_outlined,
                    size: 16, color: AppColors.goldLight),
              ),
            ),
        ],
      ),
    );
  }

  Widget _panel({required Widget child, EdgeInsets? padding}) {
    return Container(
      padding: padding ?? const EdgeInsets.fromLTRB(16, 15, 16, 15),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderSoft),
      ),
      child: child,
    );
  }

  // ════════════ 저장 완료 다이얼로그 ════════════
  void _showSaved() {
    showDialog(
      context: context,
      barrierColor: const Color(0xC70E0E10),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(28),
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 30, 24, 22),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  color: AppColors.gold.withOpacity(0.16),
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.gold.withOpacity(0.4)),
                ),
                child: const Icon(Icons.check_rounded,
                    size: 32, color: AppColors.goldLight),
              ),
              const SizedBox(height: 18),
              Text('저장 완료', style: T.sans(size: 21, weight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text('$_model · $_qty$_unit\n재물조사 대장에 기록되었습니다',
                  textAlign: TextAlign.center,
                  style: T.sans(
                      size: 14,
                      weight: FontWeight.w500,
                      color: AppColors.textSub,
                      height: 1.5)),
              const SizedBox(height: 22),
              GestureDetector(
                onTap: () {
                  Navigator.pop(ctx);
                  for (final c in _serialControllers) c.dispose();
                  _serialControllers.clear();
                  _serialLoading.clear();
                  setState(() {
                    _screenState = _ScreenState.idle;
                    _annotatedBytes = null;
                    _confidence = 0.0;
                    _qty = 0;
                    _confirmedDetections = [];
                    _summary = {};
                    _remarksController.clear();
                  });
                },
                child: Container(
                  height: 52,
                  decoration: BoxDecoration(
                      color: AppColors.gold,
                      borderRadius: BorderRadius.circular(14)),
                  child: Center(
                      child: Text('다음 품목 촬영',
                          style: T.sans(
                              size: 15.5,
                              weight: FontWeight.w800,
                              color: const Color(0xFF2A2310)))),
                ),
              ),
              const SizedBox(height: 9),
              GestureDetector(
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.pop(context);
                },
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                      color: const Color(0x0DFFFFFF),
                      borderRadius: BorderRadius.circular(14)),
                  child: Center(
                      child: Text('조사 목록 보기',
                          style: T.sans(
                              size: 15,
                              weight: FontWeight.w600,
                              color: AppColors.textSoft))),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
