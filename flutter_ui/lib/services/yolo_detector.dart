import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

class YoloResult {
  YoloResult({
    required this.counts,
    required this.detections,
    required this.annotatedBytes,
  });

  final Map<String, int> counts;
  final List<Map<String, dynamic>> detections;
  final Uint8List annotatedBytes;
}

class _Detection {
  _Detection(this.x1, this.y1, this.x2, this.y2, this.score, this.classId);

  final double x1, y1, x2, y2, score;
  final int classId;
}

/// firearms_yolo_no_m16 모델(k1/k2c1/k2, 640 입력) 전용 온디바이스 추론기.
/// 정지 이미지 1장씩 처리하는 용도라 실시간 카메라 스트림 최적화는 하지 않음.
class YoloDetector {
  YoloDetector._();
  static final YoloDetector instance = YoloDetector._();

  static const _modelAsset = 'assets/models/firearms_yolo_no_m16_fp16.tflite';
  static const _inputSize = 640;
  static const _classNames = ['k1', 'k2c1', 'k2'];
  static const _confThreshold = 0.7;
  static const _iouThreshold = 0.45;
  static final _boxColor = img.ColorRgb8(216, 169, 74); // 앱 브랜드 골드(#D8A94A)

  Interpreter? _interpreter;

  Future<Interpreter> _loadInterpreter() async {
    return _interpreter ??= await Interpreter.fromAsset(_modelAsset);
  }

  Future<YoloResult> detect(Uint8List imageBytes) async {
    final interpreter = await _loadInterpreter();

    final decoded = img.decodeImage(imageBytes);
    if (decoded == null) {
      throw const FormatException('이미지를 디코딩할 수 없습니다.');
    }
    final oriented = img.bakeOrientation(decoded);
    final srcW = oriented.width;
    final srcH = oriented.height;

    // letterbox: 비율 유지 리사이즈 + 회색(114) 패딩으로 640x640 채우기
    final scale = math.min(_inputSize / srcW, _inputSize / srcH);
    final resizedW = (srcW * scale).round();
    final resizedH = (srcH * scale).round();
    final padX = (_inputSize - resizedW) / 2;
    final padY = (_inputSize - resizedH) / 2;

    final resized = img.copyResize(
      oriented,
      width: resizedW,
      height: resizedH,
      interpolation: img.Interpolation.linear,
    );
    final canvas = img.fill(
      img.Image(width: _inputSize, height: _inputSize),
      color: img.ColorRgb8(114, 114, 114),
    );
    img.compositeImage(canvas, resized, dstX: padX.round(), dstY: padY.round());

    final input = List.generate(
      1,
      (_) => List.generate(
        _inputSize,
        (y) => List.generate(_inputSize, (x) {
          final p = canvas.getPixel(x, y);
          return [p.r / 255.0, p.g / 255.0, p.b / 255.0];
        }),
      ),
    );
    final output = List.generate(
      1,
      (_) => List.generate(7, (_) => List.filled(8400, 0.0)),
    );
    interpreter.run(input, output);

    final raw = output[0]; // [7][8400], 행 0-3=xywh(0~1 정규화), 행 4-6=클래스 점수(sigmoid 적용됨)
    final candidates = <_Detection>[];
    for (var i = 0; i < raw[0].length; i++) {
      var bestScore = 0.0;
      var bestClass = -1;
      for (var c = 0; c < _classNames.length; c++) {
        final s = raw[4 + c][i];
        if (s > bestScore) {
          bestScore = s;
          bestClass = c;
        }
      }
      if (bestScore < _confThreshold) continue;

      final cx = raw[0][i] * _inputSize;
      final cy = raw[1][i] * _inputSize;
      final w = raw[2][i] * _inputSize;
      final h = raw[3][i] * _inputSize;

      // letterbox 역변환으로 원본 이미지 좌표 복원
      final x1 = ((cx - w / 2) - padX) / scale;
      final y1 = ((cy - h / 2) - padY) / scale;
      final x2 = ((cx + w / 2) - padX) / scale;
      final y2 = ((cy + h / 2) - padY) / scale;

      candidates.add(_Detection(
        x1.clamp(0, srcW.toDouble()),
        y1.clamp(0, srcH.toDouble()),
        x2.clamp(0, srcW.toDouble()),
        y2.clamp(0, srcH.toDouble()),
        bestScore,
        bestClass,
      ));
    }

    final kept = _nms(candidates);

    final counts = <String, int>{};
    final detections = <Map<String, dynamic>>[];
    for (final d in kept) {
      final name = _classNames[d.classId];
      counts[name] = (counts[name] ?? 0) + 1;
      detections.add({'class': name, 'confidence': d.score});

      img.drawRect(
        oriented,
        x1: d.x1.round(),
        y1: d.y1.round(),
        x2: d.x2.round(),
        y2: d.y2.round(),
        color: _boxColor,
        thickness: 3,
      );
      img.drawString(
        oriented,
        '$name ${(d.score * 100).toStringAsFixed(0)}%',
        font: img.arial24,
        x: d.x1.round(),
        y: math.max(0, d.y1.round() - 26),
        color: _boxColor,
      );
    }

    final annotatedBytes = Uint8List.fromList(img.encodeJpg(oriented, quality: 85));

    return YoloResult(counts: counts, detections: detections, annotatedBytes: annotatedBytes);
  }

  List<_Detection> _nms(List<_Detection> boxes) {
    final sorted = [...boxes]..sort((a, b) => b.score.compareTo(a.score));
    final kept = <_Detection>[];
    for (final candidate in sorted) {
      final overlaps = kept.any((k) => _iou(k, candidate) > _iouThreshold);
      if (!overlaps) kept.add(candidate);
    }
    return kept;
  }

  double _iou(_Detection a, _Detection b) {
    final x1 = math.max(a.x1, b.x1);
    final y1 = math.max(a.y1, b.y1);
    final x2 = math.min(a.x2, b.x2);
    final y2 = math.min(a.y2, b.y2);
    final interArea = math.max(0.0, x2 - x1) * math.max(0.0, y2 - y1);
    final areaA = (a.x2 - a.x1) * (a.y2 - a.y1);
    final areaB = (b.x2 - b.x1) * (b.y2 - b.y1);
    return interArea / (areaA + areaB - interArea);
  }
}
