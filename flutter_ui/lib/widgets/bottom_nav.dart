import 'package:flutter/material.dart';
import '../theme.dart';

class AppBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final VoidCallback onCamera;

  const AppBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.onCamera,
  });

  @override
  Widget build(BuildContext context) {
    // 삼성 3버튼 내비게이션 바 등 시스템 UI 영역 높이를 동적으로 반영
    final systemBottom = MediaQuery.of(context).padding.bottom;
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.topCenter,
      children: [
        // 네비게이션 바 본체
        Container(
          padding: EdgeInsets.fromLTRB(14, 9, 14, 8 + systemBottom),
          decoration: const BoxDecoration(
            color: Color(0xFF1A1A1C),
            border: Border(top: BorderSide(color: Color(0x12FFFFFF))),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _navIcon(_homeIcon, active: currentIndex == 0, onTap: () => onTap(0)),
              _navIcon(_inventoryIcon, active: currentIndex == 1, onTap: () => onTap(1)),
              const Expanded(child: SizedBox()), // 가운데 FAB 자리
              _navIcon(_historyIcon, active: currentIndex == 2, onTap: () => onTap(2)),
              _navIcon(_settingsIcon, active: currentIndex == 3, onTap: () => onTap(3)),
            ],
          ),
        ),
        // 카메라 FAB — Stack으로 완전히 위로 띄움
        Positioned(
          top: -26,
          child: GestureDetector(
            onTap: onCamera,
            child: Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: AppColors.gold,
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF14160E), width: 4),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.gold.withOpacity(0.35),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const Icon(Icons.photo_camera_outlined, size: 24, color: Color(0xFF2A2310)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _navIcon(IconData icon, {required bool active, required VoidCallback onTap}) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Icon(icon, size: 24, color: active ? AppColors.gold : AppColors.textMute),
        ),
      ),
    );
  }

  static const _homeIcon = Icons.home_rounded;
  static const _inventoryIcon = Icons.inventory_2_outlined;
  static const _historyIcon = Icons.warehouse_outlined;
  static const _settingsIcon = Icons.tune_rounded;
}