import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/weapon.dart';
import '../repositories/weapon_repository.dart';
import '../theme.dart';

DateTime? _parseTs(dynamic v) {
  if (v is Timestamp) return v.toDate();
  if (v is String) return DateTime.tryParse(v);
  return null;
}

class InventoryListScreen extends StatefulWidget {
  const InventoryListScreen({super.key});

  @override
  State<InventoryListScreen> createState() => _InventoryListScreenState();
}

class _InventoryListScreenState extends State<InventoryListScreen> {
  static const _weaponOrder = ['K-2', 'K-1A', 'K2C1'];

  // ── Firestore 실시간 데이터 ──────────────────────────────
  Map<String, Weapon> _weaponMap = Map.of(Weapon.fallbacks);

  /// 기종별 가장 최신 detectionRecord
  Map<String, Map<String, dynamic>> _latestByType = {};

  /// 기종별 전체 detectionRecord 목록 (최신순)
  Map<String, List<Map<String, dynamic>>> _recordsByType = {};

  StreamSubscription<Map<String, Weapon>>? _weaponSub;
  StreamSubscription<QuerySnapshot>? _recordsSub;

  // ── UI 상태 ──────────────────────────────────────────────
  String _filter = 'all';
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  final Set<String> _open = {};

  // ── 파생 수치 ─────────────────────────────────────────────
  int get _totalQty => _weaponOrder.fold(
        0,
        (sum, name) =>
            sum +
            ((_latestByType[name]?['confirmedQuantity'] as num?)?.toInt() ?? 0),
      );

  // 현재 필터·검색이 적용된 목록 기준 카운트
  int get _shortageCount => _filteredWeapons
      .where(
          (n) => ((_latestByType[n]?['shortage'] as num?)?.toInt() ?? 0) > 0)
      .length;

  int get _okCount => _filteredWeapons
      .where((n) =>
          _latestByType.containsKey(n) &&
          ((_latestByType[n]?['shortage'] as num?)?.toInt() ?? 0) <= 0)
      .length;

  // ── 라이프사이클 ─────────────────────────────────────────
  @override
  void initState() {
    super.initState();

    _weaponSub = WeaponRepository.watchAllByDisplayName().listen(
      (map) {
        if (mounted) setState(() => _weaponMap = map);
      },
      onError: (_) {},
    );

    _recordsSub = FirebaseFirestore.instance
        .collection('detectionRecords')
        .orderBy('capturedAt', descending: true)
        .snapshots()
        .listen((snap) {
      final latest = <String, Map<String, dynamic>>{};
      final byType = <String, List<Map<String, dynamic>>>{};

      for (final doc in snap.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final type = data['weaponType'] as String? ?? '';
        if (type.isEmpty) continue;
        if (!latest.containsKey(type)) latest[type] = data;
        byType.putIfAbsent(type, () => []).add(data);
      }

      if (mounted) {
        setState(() {
          _latestByType = latest;
          _recordsByType = byType;
        });
      }
    }, onError: (_) {});

    _searchController.addListener(
      () => setState(() => _searchQuery = _searchController.text),
    );
  }

  @override
  void dispose() {
    _weaponSub?.cancel();
    _recordsSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  // ── 필터 + 검색 적용 목록 ────────────────────────────────
  List<String> get _filteredWeapons {
    final q = _searchQuery.toLowerCase();

    var list = _weaponOrder.where((name) {
      if (q.isEmpty) return true;
      final official = (_weaponMap[name]?.officialName ?? '').toLowerCase();
      return name.toLowerCase().contains(q) || official.contains(q);
    }).toList();

    return switch (_filter) {
      'short' => list
          .where((n) =>
              ((_latestByType[n]?['shortage'] as num?)?.toInt() ?? 0) > 0)
          .toList(),
      'ok' => list
          .where((n) =>
              _latestByType.containsKey(n) &&
              ((_latestByType[n]?['shortage'] as num?)?.toInt() ?? 0) <= 0)
          .toList(),
      _ => list,
    };
  }

  // ── 빌드 ────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final weapons = _filteredWeapons;
    return Container(
      color: AppColors.bg,
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(),
            Expanded(
              child: weapons.isEmpty
                  ? _emptyState()
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 108),
                      itemCount: weapons.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (_, i) => _modelCard(weapons[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('기종별 재고',
              style:
                  T.sans(size: 22, weight: FontWeight.w800, letterSpacing: -0.2)),
          const SizedBox(height: 2),
          Text(
            '학습 기종 ${_weaponOrder.length}종 · 총 $_totalQty정 보유',
            style: T.sans(
                size: 12.5, weight: FontWeight.w500, color: AppColors.textSub),
          ),
          const SizedBox(height: 14),
          _searchField(),
          const SizedBox(height: 12),
          Row(
            children: [
              _chip('전체 ${_weaponOrder.length}', 'all'),
              const SizedBox(width: 8),
              _chip('부족 $_shortageCount', 'short'),
              const SizedBox(width: 8),
              _chip('정수일치 $_okCount', 'ok'),
            ],
          ),
        ],
      ),
    );
  }

  // ── 실제 동작하는 검색 필드 ──────────────────────────────
  Widget _searchField() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.search_rounded, size: 17, color: AppColors.textMute),
          const SizedBox(width: 9),
          Expanded(
            child: TextField(
              controller: _searchController,
              style: T.sans(
                  size: 14,
                  weight: FontWeight.w500,
                  color: AppColors.textPrimary),
              cursorColor: AppColors.gold,
              decoration: InputDecoration(
                hintText: '기종명 · 공식명 검색',
                hintStyle: T.sans(
                    size: 14,
                    weight: FontWeight.w500,
                    color: AppColors.textMute),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                suffixIcon: _searchQuery.isEmpty
                    ? null
                    : GestureDetector(
                        onTap: () => _searchController.clear(),
                        child: const Icon(Icons.close_rounded,
                            size: 16, color: AppColors.textMute),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    final isSearching = _searchQuery.isNotEmpty;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isSearching ? Icons.search_off_rounded : Icons.assignment_outlined,
            size: 36,
            color: AppColors.textSub,
          ),
          const SizedBox(height: 12),
          Text(
            isSearching ? '검색 결과가 없습니다' : '재고 데이터가 없습니다',
            style: T.sans(size: 15, weight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            isSearching
                ? '다른 검색어를 입력해 보세요'
                : '촬영 후 저장하면 이곳에 표시됩니다',
            style: T.sans(
                size: 13,
                weight: FontWeight.w500,
                color: AppColors.textSub),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, String value) {
    final active = _filter == value;
    return GestureDetector(
      onTap: () => setState(() => _filter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
        decoration: BoxDecoration(
          color: active ? AppColors.gold.withOpacity(0.16) : AppColors.card,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: active ? AppColors.gold : AppColors.border),
        ),
        child: Text(label,
            style: T.sans(
                size: 13,
                weight: FontWeight.w700,
                color: active ? AppColors.goldLight : AppColors.textSub)),
      ),
    );
  }

  // ── 기종 카드 ────────────────────────────────────────────
  Widget _modelCard(String displayName) {
    final latest = _latestByType[displayName];
    final weapon = _weaponMap[displayName];
    final qty = (latest?['confirmedQuantity'] as num?)?.toInt() ?? 0;
    final authorized = (latest?['authorizedQuantity'] as num?)?.toInt() ??
        weapon?.authorizedQuantity ??
        0;
    final shortage = authorized - qty;
    final isShort = shortage > 0;
    final isInspected = latest != null;

    final caliber = weapon != null ? '${weapon.caliber} · 화기류' : '화기류';
    final lastCheckDt = isInspected ? _parseTs(latest['capturedAt']) : null;
    final lastCheck = lastCheckDt != null
        ? '${lastCheckDt.month.toString().padLeft(2, '0')}.${lastCheckDt.day.toString().padLeft(2, '0')}'
        : '-';

    final statusColor = isShort ? AppColors.terracotta : AppColors.gold;
    final isOpen = _open.contains(displayName);
    final records = _recordsByType[displayName] ?? [];

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderSoft),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // ── 요약 행 ──
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(
                () => isOpen ? _open.remove(displayName) : _open.add(displayName)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: AppColors.inner,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.borderSoft),
                    ),
                    child: const Icon(Icons.gps_fixed,
                        size: 22, color: AppColors.goldLight),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(displayName,
                                style: T.mono(size: 16.5, weight: FontWeight.w700)),
                            const SizedBox(width: 8),
                            if (!isInspected)
                              _badge('미점검', AppColors.textSub,
                                  bg: AppColors.textMute.withOpacity(0.16))
                            else
                              _badge(
                                isShort ? '부족 $shortage' : '정수일치',
                                statusColor,
                                bg: statusColor.withOpacity(0.16),
                              ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(caliber,
                            style: T.sans(
                                size: 12.5,
                                weight: FontWeight.w500,
                                color: AppColors.textSub)),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text.rich(TextSpan(children: [
                        TextSpan(
                            text: '$qty',
                            style: T.mono(
                                size: 21,
                                weight: FontWeight.w700,
                                color: isShort
                                    ? AppColors.terracotta
                                    : AppColors.textPrimary)),
                        TextSpan(
                            text: ' / $authorized',
                            style: T.mono(
                                size: 13,
                                weight: FontWeight.w400,
                                color: AppColors.textSub)),
                      ])),
                      const SizedBox(height: 1),
                      Text('보유 / 편제',
                          style: T.sans(
                              size: 11,
                              weight: FontWeight.w500,
                              color: AppColors.textSub)),
                    ],
                  ),
                  const SizedBox(width: 10),
                  AnimatedRotation(
                    turns: isOpen ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.keyboard_arrow_down_rounded,
                        size: 20, color: AppColors.textSub),
                  ),
                ],
              ),
            ),
          ),
          // ── 점검 기록 목록 (펼침) ──
          if (isOpen)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 2, 14, 14),
              child: Container(
                padding: const EdgeInsets.only(top: 12),
                decoration: const BoxDecoration(
                    border:
                        Border(top: BorderSide(color: AppColors.borderSoft))),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(2, 0, 2, 9),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('점검 기록',
                              style: T.sans(
                                  size: 12,
                                  weight: FontWeight.w500,
                                  color: AppColors.textSub)),
                          Text('최종 점검 $lastCheck',
                              style: T.sans(
                                  size: 11.5,
                                  weight: FontWeight.w500,
                                  color: AppColors.textSub)),
                        ],
                      ),
                    ),
                    if (records.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          '점검 기록이 없습니다',
                          style: T.sans(
                              size: 13,
                              weight: FontWeight.w500,
                              color: AppColors.textMute),
                        ),
                      )
                    else
                      // 최근 5건만 표시
                      ...records.take(5).map(_recordRow),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── 점검 기록 행 (총번 행 대체) ──────────────────────────
  Widget _recordRow(Map<String, dynamic> data) {
    final condition = data['condition'] as String? ?? 'good';
    final qty = (data['confirmedQuantity'] as num?)?.toInt() ?? 0;
    final authorized = (data['authorizedQuantity'] as num?)?.toInt() ?? 0;
    final dt = _parseTs(data['capturedAt']);
    final dateStr = dt != null
        ? '${dt.month.toString().padLeft(2, '0')}.${dt.day.toString().padLeft(2, '0')}  '
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}'
        : '-';

    final conditionLabel = switch (condition) {
      'repair' => '정비요',
      'unusable' => '불용',
      _ => '양호',
    };
    final conditionColor = switch (condition) {
      'repair' => AppColors.terracotta,
      'unusable' => AppColors.red,
      _ => AppColors.gold,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
          color: AppColors.serialRow, borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                  color: conditionColor, shape: BoxShape.circle)),
          const SizedBox(width: 10),
          Expanded(
            child:
                Text(dateStr, style: T.mono(size: 13, weight: FontWeight.w500)),
          ),
          Text(
            '$qty / $authorized',
            style: T.mono(
                size: 12.5,
                weight: FontWeight.w600,
                color: AppColors.textSub),
          ),
          const SizedBox(width: 10),
          Text(conditionLabel,
              style: T.sans(
                  size: 12, weight: FontWeight.w600, color: conditionColor)),
        ],
      ),
    );
  }

  Widget _badge(String text, Color color, {Color? bg}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: bg ?? color.withOpacity(0.16),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(text,
          style: T.sans(size: 11, weight: FontWeight.w700, color: color)),
    );
  }
}