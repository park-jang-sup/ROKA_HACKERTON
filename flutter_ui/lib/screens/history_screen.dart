import 'package:flutter/material.dart';
import '../theme.dart';

// ── 더미 데이터 모델 ──────────────────────────────────────────

enum ItemCondition { good, repair, unusable }

class SupplyItem {
  final String name;
  final int held;
  final int authorized;
  final ItemCondition condition;
  final int unusableCount;

  const SupplyItem({
    required this.name,
    required this.held,
    required this.authorized,
    required this.condition,
    this.unusableCount = 0,
  });
}

class Warehouse {
  final String id;
  final String label;
  final String subtitle;
  final IconData icon;
  final List<SupplyItem> items;

  const Warehouse({
    required this.id,
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.items,
  });
}

const _warehouses = [
  Warehouse(
    id: 'A',
    label: '창고A',
    subtitle: '화생방 장비',
    icon: Icons.coronavirus_outlined,
    items: [
      SupplyItem(name: '방독면', held: 45, authorized: 50, condition: ItemCondition.good),
      SupplyItem(name: '화생방 보호의', held: 48, authorized: 50, condition: ItemCondition.good),
      SupplyItem(name: '제독장비', held: 10, authorized: 12, condition: ItemCondition.repair),
    ],
  ),
  Warehouse(
    id: 'B',
    label: '창고B',
    subtitle: '감시장비',
    icon: Icons.visibility_outlined,
    items: [
      SupplyItem(name: '쌍안경', held: 8, authorized: 10, condition: ItemCondition.good),
      SupplyItem(name: '야간투시경', held: 3, authorized: 5, condition: ItemCondition.repair),
      SupplyItem(name: '열상감시장비', held: 2, authorized: 2, condition: ItemCondition.good),
    ],
  ),
  Warehouse(
    id: 'C',
    label: '창고C',
    subtitle: '군장/개인장비',
    icon: Icons.backpack_outlined,
    items: [
      SupplyItem(name: '전투조끼', held: 48, authorized: 50, condition: ItemCondition.good),
      SupplyItem(name: '방탄헬멧', held: 50, authorized: 50, condition: ItemCondition.good),
      SupplyItem(name: '군장', held: 47, authorized: 50, condition: ItemCondition.unusable, unusableCount: 1),
    ],
  ),
];

// ── 화면 ─────────────────────────────────────────────────────

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  String? _selectedId;

  Warehouse? get _selected =>
      _selectedId == null ? null : _warehouses.firstWhere((w) => w.id == _selectedId);

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
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 108),
                child: Column(
                  children: [
                    _siteMap(),
                    if (_selected != null) ...[
                      const SizedBox(height: 20),
                      _itemList(_selected!),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 헤더 ─────────────────────────────────────────────────
  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('창고별 물자 관리',
              style: T.sans(size: 22, weight: FontWeight.w800, letterSpacing: -0.2)),
          const SizedBox(height: 2),
          Text(
            _selected == null ? '창고를 선택하세요' : '${_selected!.label} · ${_selected!.subtitle}',
            style: T.sans(size: 12.5, weight: FontWeight.w500, color: AppColors.textSub),
          ),
        ],
      ),
    );
  }

  // ── 배치도 ────────────────────────────────────────────────
  Widget _siteMap() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.map_outlined, size: 14, color: AppColors.textSub),
              const SizedBox(width: 6),
              Text('부대 창고 배치도',
                  style: T.sans(size: 12, weight: FontWeight.w600, color: AppColors.textSub)),
            ],
          ),
          const SizedBox(height: 14),
          // 도로 배경 + 창고 배치
          _mapLayout(),
          const SizedBox(height: 12),
          // 범례
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _legend(AppColors.gold, '선택됨'),
              const SizedBox(width: 16),
              _legend(AppColors.cardAlt, '미선택'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _mapLayout() {
    return Container(
      height: 220,
      decoration: BoxDecoration(
        color: const Color(0xFF111410),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderSoft),
      ),
      child: Stack(
        children: [
          // 도로 (가로)
          Positioned(
            top: 100, left: 0, right: 0,
            child: Container(height: 20, color: const Color(0xFF1E2016)),
          ),
          // 도로 (세로)
          Positioned(
            left: 130, top: 0, bottom: 0,
            child: Container(width: 20, color: const Color(0xFF1E2016)),
          ),
          // 창고A (좌상)
          Positioned(
            top: 20, left: 20,
            child: _warehouseCard(_warehouses[0]),
          ),
          // 창고B (우상)
          Positioned(
            top: 20, right: 20,
            child: _warehouseCard(_warehouses[1]),
          ),
          // 창고C (하단 중앙)
          Positioned(
            bottom: 20, left: 0, right: 0,
            child: Center(child: _warehouseCard(_warehouses[2])),
          ),
        ],
      ),
    );
  }

  Widget _warehouseCard(Warehouse w) {
    final isSelected = _selectedId == w.id;
    final shortage = w.items.fold<int>(
        0, (sum, i) => sum + (i.authorized - i.held).clamp(0, 999));

    return GestureDetector(
      onTap: () => setState(() => _selectedId = isSelected ? null : w.id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 100,
        height: 76,
        decoration: BoxDecoration(
          color: isSelected ? AppColors.gold.withOpacity(0.12) : AppColors.cardAlt,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.gold : AppColors.borderSoft,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [BoxShadow(color: AppColors.gold.withOpacity(0.25), blurRadius: 12)]
              : [],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(w.icon, size: 22, color: isSelected ? AppColors.gold : AppColors.textSub),
            const SizedBox(height: 4),
            Text(w.label,
                style: T.mono(
                    size: 12,
                    weight: FontWeight.w700,
                    color: isSelected ? AppColors.goldLight : AppColors.textPrimary)),
            const SizedBox(height: 2),
            Text(
              shortage > 0 ? '부족 $shortage' : '${w.items.length}품목',
              style: T.sans(
                  size: 10,
                  weight: FontWeight.w500,
                  color: shortage > 0 ? AppColors.terracotta : AppColors.textSub),
            ),
          ],
        ),
      ),
    );
  }

  Widget _legend(Color color, String label) {
    return Row(
      children: [
        Container(
          width: 10, height: 10,
          decoration: BoxDecoration(
            color: color.withOpacity(0.3),
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: color, width: 1.5),
          ),
        ),
        const SizedBox(width: 5),
        Text(label, style: T.sans(size: 11, weight: FontWeight.w500, color: AppColors.textSub)),
      ],
    );
  }

  // ── 품목 목록 ─────────────────────────────────────────────
  Widget _itemList(Warehouse w) {
    final totalHeld = w.items.fold<int>(0, (s, i) => s + i.held);
    final totalAuth = w.items.fold<int>(0, (s, i) => s + i.authorized);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 창고 요약 헤더
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.gold.withOpacity(0.08),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            border: Border.all(color: AppColors.gold.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              Icon(w.icon, size: 18, color: AppColors.gold),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(w.label,
                        style: T.mono(size: 14, weight: FontWeight.w700, color: AppColors.goldLight)),
                    Text(w.subtitle,
                        style: T.sans(size: 11.5, weight: FontWeight.w500, color: AppColors.textSub)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text.rich(TextSpan(children: [
                    TextSpan(
                        text: '$totalHeld',
                        style: T.mono(size: 16, weight: FontWeight.w700, color: AppColors.goldLight)),
                    TextSpan(
                        text: ' / $totalAuth',
                        style: T.sans(size: 12, weight: FontWeight.w500, color: AppColors.textSub)),
                  ])),
                  Text('전체 보유/편제',
                      style: T.sans(size: 10.5, weight: FontWeight.w500, color: AppColors.textMute)),
                ],
              ),
            ],
          ),
        ),
        // 품목 카드 목록
        Container(
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
            border: Border(
              left: BorderSide(color: AppColors.borderSoft),
              right: BorderSide(color: AppColors.borderSoft),
              bottom: BorderSide(color: AppColors.borderSoft),
            ),
          ),
          child: Column(
            children: [
              for (int i = 0; i < w.items.length; i++)
                _itemRow(w.items[i], divider: i < w.items.length - 1),
            ],
          ),
        ),
      ],
    );
  }

  Widget _itemRow(SupplyItem item, {required bool divider}) {
    final shortage = item.authorized - item.held;
    final condLabel = switch (item.condition) {
      ItemCondition.repair => '정비요',
      ItemCondition.unusable => '불용',
      ItemCondition.good => '양호',
    };
    final condColor = switch (item.condition) {
      ItemCondition.repair => AppColors.terracotta,
      ItemCondition.unusable => AppColors.red,
      ItemCondition.good => AppColors.gold,
    };
    final condIcon = switch (item.condition) {
      ItemCondition.repair => Icons.build_outlined,
      ItemCondition.unusable => Icons.block_outlined,
      ItemCondition.good => Icons.shield_outlined,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        border: divider
            ? const Border(bottom: BorderSide(color: AppColors.borderSoft))
            : null,
      ),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: condColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(condIcon, size: 17, color: condColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name,
                    style: T.sans(size: 14, weight: FontWeight.w700)),
                const SizedBox(height: 2),
                if (item.unusableCount > 0)
                  Text('불용 ${item.unusableCount}개 포함',
                      style: T.sans(
                          size: 11, weight: FontWeight.w500, color: AppColors.red)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text.rich(TextSpan(children: [
                TextSpan(
                    text: '${item.held}',
                    style: T.mono(
                        size: 15,
                        weight: FontWeight.w700,
                        color: shortage > 0 ? AppColors.terracotta : AppColors.goldLight)),
                TextSpan(
                    text: ' / ${item.authorized}',
                    style: T.sans(size: 11, weight: FontWeight.w400, color: AppColors.textSub)),
              ])),
              const SizedBox(height: 3),
              _badge(condLabel, condColor),
            ],
          ),
        ],
      ),
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.16),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text,
          style: T.sans(size: 10.5, weight: FontWeight.w700, color: color)),
    );
  }
}
