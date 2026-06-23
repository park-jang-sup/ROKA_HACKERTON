"""
탐지 결과를 detectionRecords 컬렉션에 저장하는 모듈.
아직 src/app.py와는 연동하지 않음 (통합은 다음 단계에서).
"""
from datetime import datetime, timezone

from firebase_config import get_db


def save_detection_record(image_storage_path: str, confirmed_detections: list, model_version: str) -> str:
    """
    confirmed_detections 예시:
    [{"class": "K2", "confidence": 0.91}, {"class": "K2", "confidence": 0.87}]
    """
    summary = {}
    for det in confirmed_detections:
        summary[det["class"]] = summary.get(det["class"], 0) + 1

    record = {
        "imageStoragePath": image_storage_path,
        "capturedAt": datetime.now(timezone.utc).isoformat(),
        "confirmedDetections": confirmed_detections,
        "summary": summary,
        "modelVersion": model_version,
    }

    db = get_db()
    _, doc_ref = db.collection("detectionRecords").add(record)
    return doc_ref.id
