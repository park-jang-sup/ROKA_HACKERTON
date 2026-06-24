# ROKA_HACKERTON

YOLOv8 기반 총기류(소총) 탐지 및 종류별 카운팅 프로젝트. 사진을 입력하면 학습된 YOLO 모델이 이미지를 분석해서, 사진에서 확인된 총기 종류와 개수를 출력합니다.

```
입력(사진) → 학습된 YOLOv8 모델이 이미지 분석 → 출력(총기 종류 + 개수)
```

## 현재 배포 모델: `firearms_yolo_no_m16`

- 위치: [models/firearms_yolo_no_m16/best.pt](models/firearms_yolo_no_m16/best.pt)
- 베이스: YOLOv8n (`yolov8n.pt`, COCO 사전학습 가중치에서 transfer learning)
- 클래스 (3개): `k1`, `k2c1`, `k2`
- 입력 이미지 크기: 640x640
- 학습 환경: NVIDIA RTX 2060, epochs 100, batch 8, optimizer auto(AdamW)

### 클래스별 라벨 수 (train 기준)
| 클래스 | 의미 | train 인스턴스 |
|---|---|---|
| k1 | K1 기관단총 | 479 |
| k2c1 | K2C1 소총(개머리판 폴딩형 변형) | 517 |
| k2 | K2 소총 | 453장(이미지 기준, 별도 데이터셋) |

### 최종 검증(validation) 성능
| 클래스 | 인스턴스 | Precision | Recall | mAP50 | mAP50-95 |
|---|---|---|---|---|---|
| 전체 | 131 | 0.874 | 0.835 | **0.879** | **0.752** |
| k1 | 46 | 0.886 | 0.783 | 0.871 | 0.711 |
| k2c1 | 38 | 0.911 | 0.921 | 0.935 | 0.847 |
| k2 | 47 | 0.825 | 0.800 | 0.832 | 0.699 |

### 왜 m16 클래스가 없는가
원래 데이터셋(v1~v3)에는 `m16` 클래스도 포함되어 있었지만, 학습 결과 m16은 모든 데이터셋 버전(단일 클래스일 때 포함)에서 일관되게 가장 낮은 성능(mAP50 0.28~0.39 수준)을 보였습니다. m16 라벨이 항상 다른 클래스와 섞이지 않고 단독으로만 존재해, m16 전용 이미지(492장)를 데이터셋에서 완전히 제외하고 `k1`/`k2c1`/`k2` 3클래스로 재학습한 결과 전체 mAP50이 0.716 → **0.879**로 크게 개선됐습니다. m16 라벨/이미지 품질 자체에 문제가 있었던 것으로 보이며, 추후 재라벨링 시 다시 추가할 수 있습니다.

## 데이터셋 구성

| 폴더 | 출처 | 클래스 | 비고 |
|---|---|---|---|
| `m16image/My First Project.v1i.yolov8` | Roboflow `my-first-project-tvjej` v1 | m16 (1클래스) | 132장, 초기 버전 |
| `m16image/My First Project.v2i.yolov8` | 동일 프로젝트 v2 | m16 (1클래스) | 495장 |
| `m16image/My First Project.v3i.yolov8` | 동일 프로젝트 v3 | k1, k2c1, m16 (3클래스) | 1356장, k1/k2c1 라벨링 대량 추가 |
| `m16image/My First Project.v3i.yolov8_no_m16` | v3에서 m16 전용 이미지 제외 | k1, k2c1 | 843장(train), 최종 모델에 사용 |
| `m16image/K2dataset.v1i.yolov8` | Roboflow `k2dataset` v1 | K2 (1클래스) | 453장(train) |
| `m16image/K2dataset.v1i.yolov8_remapped_to2` | 위 K2dataset을 class id 2로 리매핑 | k2 | 최종 모델에 사용 |
| `m16image/K2dataset.v1i.yolov8_remapped(_to3)` | 과거 실험용 리매핑(레거시) | k2 | `firearms_yolo_combined`, `firearms_yolo_v3_combined`에서 사용 |

데이터셋 원본 이미지(`m16image/`)는 `.gitignore`로 제외되어 있어 이 저장소에는 포함되지 않습니다 (Roboflow에서 직접 export 필요).

### data/*.yaml 정리
| yaml | 클래스 | 사용 모델 |
|---|---|---|
| `data/data.yaml` | m16 | `firearms_yolo` |
| `data/data_v2.yaml` | m16 | `firearms_yolo_v2` |
| `data/data_combined.yaml` | m16, k2 | `firearms_yolo_combined` |
| `data/data_v3.yaml` | k1, k2c1, m16 | `firearms_yolo_v3` |
| `data/data_v3_combined.yaml` | k1, k2c1, m16, k2 | `firearms_yolo_v3_combined` |
| `data/data_no_m16.yaml` | k1, k2c1, k2 | **`firearms_yolo_no_m16` (현재 배포 모델)** |

## 모델 학습 히스토리

| 모델 | 클래스 | mAP50 | mAP50-95 | 비고 |
|---|---|---|---|---|
| firearms_yolo (v1) | m16 | 0.283 | 0.158 | |
| firearms_yolo_v2 | m16 | 0.333 | 0.215 | |
| firearms_yolo_combined | m16, k2 | 0.593 | 0.428 | |
| firearms_yolo_v3 | k1, k2c1, m16 | 0.727 | 0.600 | m16 mAP50 0.385로 여전히 약함 |
| firearms_yolo_v3_combined | k1, k2c1, m16, k2 | 0.716 | 0.615 | m16 mAP50 0.342로 여전히 약함 |
| **firearms_yolo_no_m16** | **k1, k2c1, k2** | **0.879** | **0.752** | **m16 제거 후 최종 채택** |

학습 산출물(가중치, 학습 곡선, confusion matrix 등)은 `runs/detect/models/<실험명>/`에 로컬로 남아있으며 `.gitignore`로 저장소에는 포함되지 않습니다. 배포용 최종 모델 가중치만 `models/firearms_yolo_no_m16/best.pt`로 별도 커밋되어 있습니다.

## 프로젝트 구조

```
src/
  pipeline.py      # 입력→모델 분석→출력(클래스별 개수) 공유 파이프라인 (load_model, detect_firearms)
  train.py         # YOLO 학습 스크립트
  detect_count.py  # CLI: 이미지/폴더 경로 → 클래스별 개수 출력
  app.py           # Streamlit 웹앱: 이미지 업로드 → 탐지결과 시각화 + 개수 표
  count_utils.py   # YOLO 결과를 클래스별 개수로 집계
data/              # 데이터셋 조합별 data.yaml
models/            # 배포용(커밋된) 모델 가중치
runs/detect/       # 로컬 학습 산출물 (gitignore, 미커밋)
m16image/          # Roboflow 데이터셋 원본 (gitignore, 미커밋)
db/                # Firebase 연동 (무기/이미지/탐지기록 저장) — 자세한 내용은 db/README.md 참고
```

## 사용 방법

### 1. 학습
```bash
python src/train.py --data data/data_no_m16.yaml --model yolov8n.pt --epochs 100 --imgsz 640 --batch 8 --name firearms_yolo_no_m16 --device 0
```

### 2. CLI로 탐지
```bash
python src/detect_count.py "이미지_또는_폴더_경로"
python src/detect_count.py "이미지.jpg" --save   # 박스 그려진 결과 이미지도 저장
```

### 3. 웹앱으로 탐지 (Streamlit)
```bash
streamlit run src/app.py
```
브라우저에서 이미지를 업로드하면 원본/탐지결과 이미지와 클래스별 개수 표를 바로 확인할 수 있습니다.

### 의존성 설치
```bash
pip install -r requirements.txt
```
