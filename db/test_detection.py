"""
detection_store.py가 정상 동작하는지 확인하는 테스트 스크립트.
실제 카메라/YOLO 연동 전에, 가짜 탐지 결과로 detectionRecords 컬렉션 동작만 검증한다.
"""
from detection_store import save_detection_record

doc_id = save_detection_record(
    image_storage_path="weapons/k2/test_dummy.jpg",
    confirmed_detections=[
        {"class": "k2", "confidence": 0.91},
        {"class": "k2", "confidence": 0.87},
        {"class": "k1", "confidence": 0.78},
    ],
    model_version="test-v0",
)

print(f"생성된 문서 ID: {doc_id}")