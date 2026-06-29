import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../theme.dart';

/// capturedAt 필드는 Firestore Timestamp(Flutter 저장) 또는
/// ISO 8601 String(Python detection_store.py 저장) 두 형태가 혼재할 수 있음
DateTime? _parseTs(dynamic v) {
  if (v is Timestamp) return v.toDate();
  if (v is String) return DateTime.tryParse(v);
  return null;
}

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  static const _weaponOrder = ['K-2', 'K-1A', 'K2C1'];

  /// 현재 펼쳐진 기종 집합
  final Set<String> _open = {};

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bg,
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('detectionRecords')
                    .orderBy('capturedAt', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(
                          color: AppColors.gold, strokeWidth: 3),
                    );
                  }
                  if (snapshot.hasError) return _errorState();

                  final docs = snapshot.data?.docs ?? [];
                  if (docs.isEmpty) return _emptyState();

                  // capturedAt 내림차순 순서를 유지하며 기종별로 그룹핑
                  final byType = <String, List<Map<String, dynamic>>>{};
                  for (final doc in docs) {
                    final data = doc.data() as Map<String, dynamic>;
                    final type = data['weaponType'] as String? ?? '';
                    if (type.isEmpty) continue;
                    byType.putIfAbsent(type, () => []).add(data);
                  }

                  // _weaponOrder 기준으로 필터링 (기록이 있는 기종만)
                  final weapons =
                      _weaponOrder.where(byType.containsKey).toList();
                  if (weapons.isEmpty) return _emptyState();

                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 108),
                    itemCount: weapons.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, i) =>
                        _weaponGroup(weapons[i], byType[weapons[i]]!),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 헤더 ────────────────────────────────────────────────
  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('검사 내역',
              style: T.sans(
                  size: 22, weight: FontWeight.w800, letterSpacing: -0.2)),
          const SizedBox(height: 2),
          Text('기종별 점검 이력 · 탭하여 펼치기',
              style: T.sans(
                  size: 12.5,
                  weight: FontWeight.w500,
                  color: AppColors.textSub)),
        ],
      ),
    );
  }

  // ── 빈 상태 / 에러 ───────────────────────────────────────
  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.cardAlt,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.borderSoft),
            ),
            child: const Icon(Icons.assignment_outlined,
                size: 28, color: AppColors.textSub),
          ),
          const SizedBox(height: 16),
          Text('검사 기록이 없습니다',
              style: T.sans(size: 15, weight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text('촬영 후 저장하면 이곳에 기록됩니다',
              style: T.sans(
                  size: 13,
                  weight: FontWeight.w500,
                  color: AppColors.textSub)),
        ],
      ),
    );
  }

  Widget _errorState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_outlined,
              size: 36, color: AppColors.textSub),
          const SizedBox(height: 12),
          Text('데이터를 불러오지 못했습니다',
              style: T.sans(
                  size: 14,
                  weight: FontWeight.w600,
                  color: AppColors.textSub)),
        ],
      ),
    );
  }

  // ── 기종 그룹 카드 ───────────────────────────────────────
  Widget _weaponGroup(
      String weaponType, List<Map<String, dynamic>> records) {
    final latest = records.first; // 이미 capturedAt 내림차순 정렬됨
    final isOpen = _open.contains(weaponType);

    final qty = (latest['confirmedQuantity'] as num?)?.toInt() ?? 0;
    final authorized = (latest['authorizedQuantity'] as num?)?.toInt() ?? 0;
    final condition = latest['condition'] as String? ?? 'good';
    final shortage = authorized - qty;

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
    final conditionIcon = switch (condition) {
      'repair' => Icons.build_outlined,
      'unusable' => Icons.block_outlined,
      _ => Icons.shield_outlined,
    };

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderSoft),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // ── 그룹 헤더 (탭하면 토글) ──
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() =>
                isOpen ? _open.remove(weaponType) : _open.add(weaponType)),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: conditionColor.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(conditionIcon, size: 20, color: conditionColor),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(weaponType,
                                style: T.mono(
                                    size: 16, weight: FontWeight.w700)),
                            const SizedBox(width: 8),
                            _badge(conditionLabel, conditionColor),
                            const SizedBox(width: 6),
                            _badge('${records.length}건', AppColors.textSub,
                                bg: AppColors.inner),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '최근 점검 ${_fmtDate(_parseTs(latest['capturedAt']))}',
                          style: T.sans(
                              size: 12,
                              weight: FontWeight.w500,
                              color: AppColors.textSub),
                        ),
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
                                size: 18,
                                weight: FontWeight.w700,
                                color: shortage > 0
                                    ? AppColors.terracotta
                                    : AppColors.goldLight)),
                        TextSpan(
                            text: ' / $authorized',
                            style: T.sans(
                                size: 12,
                                weight: FontWeight.w500,
                                color: AppColors.textSub)),
                      ])),
                      const SizedBox(height: 1),
                      Text(
                        shortage > 0
                            ? '부족 $shortage정'
                            : shortage < 0
                                ? '초과 ${-shortage}정'
                                : '편제 일치',
                        style: T.sans(
                            size: 11,
                            weight: FontWeight.w500,
                            color: shortage != 0
                                ? AppColors.terracotta
                                : AppColors.textSub),
                      ),
                    ],
                  ),
                  const SizedBox(width: 8),
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
          // ── 펼침: 전체 이력 목록 ──
          if (isOpen)
            Container(
              decoration: const BoxDecoration(
                  border:
                      Border(top: BorderSide(color: AppColors.borderSoft))),
              child: Column(
                children: [
                  for (int i = 0; i < records.length; i++)
                    _historyRow(
                      records[i],
                      isLatest: i == 0,
                      divider: i < records.length - 1,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── 펼침 내 개별 이력 행 ─────────────────────────────────
  Widget _historyRow(
    Map<String, dynamic> data, {
    required bool isLatest,
    required bool divider,
  }) {
    final qty = (data['confirmedQuantity'] as num?)?.toInt() ?? 0;
    final authorized = (data['authorizedQuantity'] as num?)?.toInt() ?? 0;
    final condition = data['condition'] as String? ?? 'good';
    final remarks = (data['remarks'] as String? ?? '').trim();
    final dateStr = _fmtDate(_parseTs(data['capturedAt']));
    final shortage = authorized - qty;

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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isLatest ? AppColors.gold.withOpacity(0.06) : Colors.transparent,
        border: divider
            ? const Border(bottom: BorderSide(color: AppColors.borderSoft))
            : null,
      ),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration:
                BoxDecoration(color: conditionColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(dateStr,
                        style: T.mono(
                            size: 12.5,
                            weight: FontWeight.w500,
                            color: AppColors.textSub)),
                    if (isLatest) ...[
                      const SizedBox(width: 6),
                      _badge('최근', AppColors.goldLight,
                          bg: AppColors.gold.withOpacity(0.18)),
                    ],
                  ],
                ),
                if (remarks.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(remarks,
                      style: T.sans(
                          size: 12,
                          weight: FontWeight.w500,
                          color: AppColors.textMute),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
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
                        size: 14,
                        weight: FontWeight.w700,
                        color: shortage > 0
                            ? AppColors.terracotta
                            : AppColors.goldLight)),
                TextSpan(
                    text: ' / $authorized',
                    style: T.sans(
                        size: 11,
                        weight: FontWeight.w400,
                        color: AppColors.textSub)),
              ])),
              const SizedBox(height: 2),
              _badge(conditionLabel, conditionColor),
            ],
          ),
        ],
      ),
    );
  }

  // ── 공통 유틸 ────────────────────────────────────────────
  Widget _badge(String text, Color color, {Color? bg}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bg ?? color.withOpacity(0.16),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text,
          style: T.sans(size: 10.5, weight: FontWeight.w700, color: color)),
    );
  }

  String _fmtDate(DateTime? dt) {
    if (dt == null) return '-';
    final mm = dt.month.toString().padLeft(2, '0');
    final dd = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mi = dt.minute.toString().padLeft(2, '0');
    return '${dt.year}.$mm.$dd  $hh:$mi';
  }
}
