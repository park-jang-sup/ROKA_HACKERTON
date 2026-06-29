import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/weapon.dart';
import '../repositories/weapon_repository.dart';
import '../theme.dart';
import 'capture_screen.dart';
import 'inventory_list_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // ── Firestore 스트림 데이터 ────────────────────────────
  Map<String, Weapon> _weaponMap = Map.of(Weapon.fallbacks);

  /// weaponType(K-2 등) 키 → 해당 기종의 가장 최신 detectionRecords 문서
  Map<String, Map<String, dynamic>> _latestByType = {};

  StreamSubscription<Map<String, Weapon>>? _weaponSub;
  StreamSubscription<QuerySnapshot>? _recordsSub;

  static const _weaponOrder = ['K-2', 'K-1A', 'K2C1'];

  // ── 파생 수치 ────────────────────────────────────────────
  int get _inspectedCount => _latestByType.length;
  int get _uninspectedCount => _weaponOrder.length - _inspectedCount;
  int get _shortageTypeCount =>
      _latestByType.values
          .where((d) => (d['shortage'] as num? ?? 0) > 0)
          .length;

  int _confirmedQty(String displayName) =>
      (_latestByType[displayName]?['confirmedQuantity'] as num?)?.toInt() ?? 0;

  int _authorizedQty(String displayName) =>
      (_latestByType[displayName]?['authorizedQuantity'] as num?)?.toInt()
      ?? _weaponMap[displayName]?.authorizedQuantity
      ?? 0;

  bool _isShort(String displayName) =>
      ((_latestByType[displayName]?['shortage'] as num?)?.toInt() ?? 0) > 0;

  bool _isInspected(String displayName) =>
      _latestByType.containsKey(displayName);

  String get _todayStr {
    final now = DateTime.now();
    const wd = ['월', '화', '수', '목', '금', '토', '일'];
    final mm = now.month.toString().padLeft(2, '0');
    final dd = now.day.toString().padLeft(2, '0');
    return '${now.year}. $mm. $dd (${wd[now.weekday - 1]})';
  }

  // ── 라이프사이클 ─────────────────────────────────────────
  @override
  void initState() {
    super.initState();

    _weaponSub = WeaponRepository.watchAllByDisplayName().listen(
      (map) { if (mounted) setState(() => _weaponMap = map); },
      onError: (_) {},
    );

    _recordsSub = FirebaseFirestore.instance
        .collection('detectionRecords')
        .orderBy('capturedAt', descending: true)
        .snapshots()
        .listen((snap) {
          // 내림차순 정렬된 스냅샷에서 기종별 최신 문서 1개씩만 추출
          final latest = <String, Map<String, dynamic>>{};
          for (final doc in snap.docs) {
            final data = doc.data() as Map<String, dynamic>;
            final type = data['weaponType'] as String? ?? '';
            if (type.isNotEmpty && !latest.containsKey(type)) {
              latest[type] = data;
            }
          }
          if (mounted) setState(() => _latestByType = latest);
        }, onError: (_) {});
  }

  @override
  void dispose() {
    _weaponSub?.cancel();
    _recordsSub?.cancel();
    super.dispose();
  }

  // ── 빌드 ────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bg,
      child: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 108),
          children: [
            _header(),
            _primaryCta(context),
            _lowStock(),
            _byModel(),
          ],
        ),
      ),
    );
  }

  // ══ 헤더 ════════════════════════════════════════════════
  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('김보급 상사',
              style: T.sans(size: 23, weight: FontWeight.w800, letterSpacing: -0.2)),
          const SizedBox(height: 4),
          Text('행정보급관 · 제0000부대 보급대',
              style: T.sans(size: 13, weight: FontWeight.w500, color: AppColors.textSub)),
          const SizedBox(height: 18),
          _datePill(),
          const SizedBox(height: 18),
          _statTiles(),
        ],
      ),
    );
  }

  Widget _datePill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0x38000000),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.calendar_today_outlined, size: 15, color: AppColors.goldLight),
          const SizedBox(width: 9),
          Text(_todayStr, style: T.mono(size: 13.5, weight: FontWeight.w600)),
          const SizedBox(width: 6),
          const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: AppColors.textSub),
        ],
      ),
    );
  }

  Widget _statTiles() {
    return Row(
      children: [
        _tile('${_weaponOrder.length}', '총 기종'),
        const SizedBox(width: 8),
        _tile('$_inspectedCount', '점검 완료',
            accent: AppColors.gold,
            bg: AppColors.gold.withOpacity(0.16)),
        const SizedBox(width: 8),
        _tile('$_uninspectedCount', '미점검'),
        const SizedBox(width: 8),
        _tile('$_shortageTypeCount', '부족 기종',
            accent: AppColors.red,
            bg: AppColors.red.withOpacity(0.16)),
      ],
    );
  }

  Widget _tile(String value, String label, {Color? accent, Color? bg}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 13),
        decoration: BoxDecoration(
          color: bg ?? const Color(0x12FFFFFF),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: accent?.withOpacity(0.3) ?? const Color(0x12FFFFFF)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                style: T.mono(
                    size: 24,
                    weight: FontWeight.w700,
                    color: accent ?? AppColors.textPrimary)),
            const SizedBox(height: 6),
            Text(label,
                style: T.sans(
                    size: 11.5,
                    weight: FontWeight.w500,
                    color: AppColors.textSub)),
          ],
        ),
      ),
    );
  }

  // ══ CTA 버튼 ════════════════════════════════════════════
  Widget _primaryCta(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: GestureDetector(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
              builder: (_) => const CaptureScreen(), fullscreenDialog: true),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          decoration: BoxDecoration(
            color: AppColors.gold,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                  color: AppColors.gold.withOpacity(0.22),
                  blurRadius: 18,
                  offset: const Offset(0, 4)),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0x29121009),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(Icons.photo_camera_outlined,
                    size: 22, color: Color(0xFF2A2310)),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('사진으로 재고 등록',
                        style: T.sans(
                            size: 16,
                            weight: FontWeight.w800,
                            color: const Color(0xFF2A2310))),
                    const SizedBox(height: 2),
                    Text('촬영 → 자동 인식 → 수량 입력',
                        style: T.sans(
                            size: 12.5,
                            weight: FontWeight.w600,
                            color: const Color(0x992A2310))),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  size: 22, color: Color(0xFF2A2310)),
            ],
          ),
        ),
      ),
    );
  }

  // ══ 부족 재고 ════════════════════════════════════════════
  Widget _lowStock() {
    final shortageEntries = _latestByType.entries
        .where((e) => (e.value['shortage'] as num? ?? 0) > 0)
        .toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 11),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text('부족 재고',
                        style: T.sans(size: 16.5, weight: FontWeight.w800)),
                    const SizedBox(width: 8),
                    Text('${shortageEntries.length}',
                        style: T.mono(
                            size: 14,
                            weight: FontWeight.w700,
                            color: AppColors.terracotta)),
                  ],
                ),
                GestureDetector(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const InventoryListScreen()),
                  ),
                  child: Text('전체보기',
                      style: T.sans(
                          size: 13,
                          weight: FontWeight.w500,
                          color: AppColors.textSub)),
                ),
              ],
            ),
          ),
          if (shortageEntries.isEmpty)
            _noShortageState()
          else
            Container(
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.borderSoft),
              ),
              child: Column(
                children: [
                  for (int i = 0; i < shortageEntries.length; i++)
                    _lowRow(
                      shortageEntries[i].key,
                      shortageEntries[i].value,
                      divider: i < shortageEntries.length - 1,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _noShortageState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 22),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderSoft),
      ),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_outline_rounded,
                size: 16, color: AppColors.gold),
            const SizedBox(width: 8),
            Text('부족 재고 없음 · 편제 정수 충족',
                style: T.sans(
                    size: 13,
                    weight: FontWeight.w500,
                    color: AppColors.textSub)),
          ],
        ),
      ),
    );
  }

  Widget _lowRow(String displayName, Map<String, dynamic> data,
      {bool divider = false}) {
    final qty = (data['confirmedQuantity'] as num?)?.toInt() ?? 0;
    final authorized = (data['authorizedQuantity'] as num?)?.toInt()
        ?? _weaponMap[displayName]?.authorizedQuantity
        ?? 0;
    final officialName = _weaponMap[displayName]?.officialName ?? displayName;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        border: divider
            ? const Border(bottom: BorderSide(color: Color(0x0DFFFFFF)))
            : null,
      ),
      child: Row(
        children: [
          Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                  color: AppColors.terracotta, shape: BoxShape.circle)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(officialName,
                    style: T.sans(size: 15, weight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text('화기류 · 편제 $authorized정',
                    style: T.sans(
                        size: 12,
                        weight: FontWeight.w500,
                        color: AppColors.textSub)),
              ],
            ),
          ),
          Text.rich(TextSpan(children: [
            TextSpan(
                text: '$qty',
                style: T.mono(
                    size: 18,
                    weight: FontWeight.w700,
                    color: AppColors.terracotta)),
            TextSpan(
                text: ' 정',
                style: T.sans(
                    size: 12,
                    weight: FontWeight.w500,
                    color: AppColors.textSub)),
          ])),
        ],
      ),
    );
  }

  // ══ 기종별 재고 바 차트 ═══════════════════════════════════
  Widget _byModel() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 13),
            child: Text.rich(TextSpan(children: [
              TextSpan(
                  text: '기종별 재고 ',
                  style: T.sans(size: 16.5, weight: FontWeight.w800)),
              TextSpan(
                  text: '보유 / 편제',
                  style: T.sans(
                      size: 12.5,
                      weight: FontWeight.w600,
                      color: AppColors.textSub)),
            ])),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.borderSoft),
            ),
            child: Column(
              children: [
                for (int i = 0; i < _weaponOrder.length; i++) ...[
                  _bar(_weaponOrder[i]),
                  if (i < _weaponOrder.length - 1) const SizedBox(height: 16),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bar(String displayName) {
    final qty = _confirmedQty(displayName);
    final auth = _authorizedQty(displayName);
    final ratio = auth > 0 ? (qty / auth).clamp(0.0, 1.0) : 0.0;

    // 미점검: 회색 / 부족: 테라코타 / 정수 일치: 골드
    final Color barColor;
    if (!_isInspected(displayName)) {
      barColor = AppColors.textMute;
    } else if (_isShort(displayName)) {
      barColor = AppColors.terracotta;
    } else {
      barColor = AppColors.gold;
    }

    final officialName = _weaponMap[displayName]?.officialName ?? displayName;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 7),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(officialName,
                      style: T.sans(size: 14, weight: FontWeight.w600)),
                  if (!_isInspected(displayName)) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.textMute.withOpacity(0.16),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text('미점검',
                          style: T.sans(
                              size: 10,
                              weight: FontWeight.w600,
                              color: AppColors.textMute)),
                    ),
                  ],
                ],
              ),
              Text.rich(TextSpan(children: [
                TextSpan(
                    text: '$qty',
                    style: T.mono(
                        size: 14, weight: FontWeight.w700, color: barColor)),
                TextSpan(
                    text: ' / $auth',
                    style: T.mono(
                        size: 13,
                        weight: FontWeight.w400,
                        color: AppColors.textSub)),
              ])),
            ],
          ),
        ),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 6,
            backgroundColor: const Color(0x12FFFFFF),
            valueColor: AlwaysStoppedAnimation(barColor),
          ),
        ),
      ],
    );
  }
}
