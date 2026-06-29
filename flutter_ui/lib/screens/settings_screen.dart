import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../theme.dart';

/// capturedAt 필드는 Timestamp 또는 ISO 8601 String 두 형태가 혼재할 수 있음
DateTime? _parseTs(dynamic v) {
  if (v is Timestamp) return v.toDate();
  if (v is String) return DateTime.tryParse(v);
  return null;
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _noti = true;

  // ── 활동 통계 (detectionRecords 집계) ──────────────────
  int _totalCount = 0;
  int _todayCount = 0;
  DateTime? _firstRecordDate;
  StreamSubscription<QuerySnapshot>? _recordsSub;

  String get _daysSinceStr {
    if (_firstRecordDate == null) return 'D+0';
    final days = DateTime.now().difference(_firstRecordDate!).inDays;
    return 'D+$days';
  }

  // ── 라이프사이클 ─────────────────────────────────────────
  @override
  void initState() {
    super.initState();

    _recordsSub = FirebaseFirestore.instance
        .collection('detectionRecords')
        .orderBy('capturedAt', descending: true)
        .snapshots()
        .listen((snap) {
          final now = DateTime.now();
          final todayStart = DateTime(now.year, now.month, now.day);

          int todayCount = 0;
          DateTime? firstDate;

          for (final doc in snap.docs) {
            final data = doc.data() as Map<String, dynamic>;
            final dt = _parseTs(data['capturedAt']);
            if (dt != null) {
              if (!dt.isBefore(todayStart)) todayCount++;
              if (firstDate == null || dt.isBefore(firstDate!)) {
                firstDate = dt;
              }
            }
          }

          if (mounted) {
            setState(() {
              _totalCount = snap.docs.length;
              _todayCount = todayCount;
              _firstRecordDate = firstDate;
            });
          }
        }, onError: (_) {});
  }

  @override
  void dispose() {
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
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
              child: Text('설정',
                  style: T.sans(
                      size: 26,
                      weight: FontWeight.w800,
                      letterSpacing: -0.3)),
            ),
            _myPageCard(),
            _activityStats(),
            _group('재고 · 조사', [
              _navItem(Icons.gps_fixed, '관리 기종 설정',
                  sub: 'K-2 · K-1A · K2C1', trailing: '3종'),
              _navItem(Icons.grid_view_rounded, '편제 정수 관리',
                  sub: '기종별 인가 수량 편집'),
              _navItem(Icons.file_download_outlined, '데이터 내보내기',
                  sub: '조사 결과 Excel · PDF', last: true),
            ]),
            _group('앱 설정', [
              _toggleItem(
                  Icons.notifications_none_rounded, '부족 재고 알림', '정수 미달 시 푸시 알림'),
            ]),
            _group('정보 · 지원', [
              _navItem(Icons.help_outline_rounded, '도움말 · 사용 가이드'),
              _navItem(Icons.chat_bubble_outline_rounded, '문의 · 오류 신고'),
              _navItem(Icons.info_outline_rounded, '버전 정보',
                  trailing: 'v1.0.0', last: true),
            ]),
            _logout(),
          ],
        ),
      ),
    );
  }

  // ══ 마이페이지 카드 ══════════════════════════════════════
  Widget _myPageCard() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.gold.withOpacity(0.18)),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 62,
                  height: 62,
                  decoration: BoxDecoration(
                    color: AppColors.gold.withOpacity(0.22),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.gold.withOpacity(0.4)),
                  ),
                  child: const Icon(Icons.person_outline_rounded,
                      size: 30, color: AppColors.goldLightest),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text('김보급',
                              style: T.sans(
                                  size: 19, weight: FontWeight.w800)),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 9, vertical: 3),
                            decoration: BoxDecoration(
                                color: AppColors.gold.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(7)),
                            child: Text('상사',
                                style: T.sans(
                                    size: 11,
                                    weight: FontWeight.w700,
                                    color: AppColors.goldLightest)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text('행정보급관 · 제0000부대 보급대',
                          style: T.sans(
                              size: 13,
                              weight: FontWeight.w500,
                              color: AppColors.textSub)),
                      const SizedBox(height: 3),
                      Text('군번 00-00000000',
                          style: T.mono(
                              size: 12,
                              weight: FontWeight.w400,
                              color: AppColors.textMute)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _myPageBtn(Icons.edit_outlined, '프로필 수정'),
                const SizedBox(width: 9),
                _myPageBtn(Icons.lock_outline_rounded, '비밀번호 변경'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _myPageBtn(IconData icon, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: const Color(0x38000000),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: const Color(0x1AFFFFFF)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: AppColors.goldLightest),
            const SizedBox(width: 6),
            Text(label,
                style: T.sans(
                    size: 13.5,
                    weight: FontWeight.w700,
                    color: AppColors.goldLightest)),
          ],
        ),
      ),
    );
  }

  // ══ 활동 통계 ════════════════════════════════════════════
  Widget _activityStats() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Row(
        children: [
          _stat('$_totalCount', '누적 점검'),
          const SizedBox(width: 9),
          _stat('$_todayCount', '오늘 등록'),
          const SizedBox(width: 9),
          _stat(_daysSinceStr, '조사 기간'),
        ],
      ),
    );
  }

  Widget _stat(String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.borderSoft),
        ),
        child: Column(
          children: [
            Text(value,
                style: T.mono(
                    size: 22,
                    weight: FontWeight.w700,
                    color: AppColors.goldLight)),
            const SizedBox(height: 5),
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

  // ══ 설정 그룹 ════════════════════════════════════════════
  Widget _group(String title, List<Widget> rows) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 9),
            child: Text(title,
                style: T.sans(
                    size: 12.5,
                    weight: FontWeight.w700,
                    color: AppColors.textSub,
                    letterSpacing: 0.2)),
          ),
          Container(
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.borderSoft),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(children: rows),
          ),
        ],
      ),
    );
  }

  Widget _navItem(IconData icon, String title,
      {String? sub, String? trailing, bool last = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(
                bottom: BorderSide(color: Color(0x0DFFFFFF))),
      ),
      child: Row(
        children: [
          _iconBox(icon),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: T.sans(size: 15, weight: FontWeight.w600)),
                if (sub != null) ...[
                  const SizedBox(height: 2),
                  Text(sub,
                      style: T.sans(
                          size: 12,
                          weight: FontWeight.w500,
                          color: AppColors.textSub)),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            Text(
                trailing,
                style: trailing.startsWith('v')
                    ? T.mono(
                        size: 12.5,
                        weight: FontWeight.w400,
                        color: AppColors.textSub)
                    : T.sans(
                        size: 13,
                        weight: FontWeight.w600,
                        color: AppColors.goldLight)),
            const SizedBox(width: 8),
          ],
          const Icon(Icons.chevron_right_rounded,
              size: 18, color: AppColors.faint),
        ],
      ),
    );
  }

  Widget _toggleItem(IconData icon, String title, String sub) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      child: Row(
        children: [
          _iconBox(icon),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: T.sans(size: 15, weight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(sub,
                    style: T.sans(
                        size: 12,
                        weight: FontWeight.w500,
                        color: AppColors.textSub)),
              ],
            ),
          ),
          _switch(_noti, () => setState(() => _noti = !_noti)),
        ],
      ),
    );
  }

  Widget _switch(bool on, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 46,
        height: 28,
        decoration: BoxDecoration(
          color: on ? AppColors.gold : AppColors.chipActive,
          borderRadius: BorderRadius.circular(999),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 180),
          alignment: on ? Alignment.centerRight : Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: on ? const Color(0xFF2A2310) : AppColors.textSub,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _iconBox(IconData icon) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
          color: AppColors.inner, borderRadius: BorderRadius.circular(10)),
      child: Icon(icon, size: 17, color: AppColors.goldLight),
    );
  }

  // ══ 로그아웃 ═════════════════════════════════════════════
  Widget _logout() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        children: [
          Container(
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.red.withOpacity(0.3)),
            ),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.logout_rounded,
                      size: 16, color: AppColors.terracotta),
                  const SizedBox(width: 8),
                  Text('로그아웃',
                      style: T.sans(
                          size: 15,
                          weight: FontWeight.w700,
                          color: AppColors.terracotta)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text('재물조사 앱 v1.0.0 · 군용 (총기류)',
              style: T.mono(size: 11, color: AppColors.faint)),
        ],
      ),
    );
  }
}
