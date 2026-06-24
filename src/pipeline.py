from ultralytics import YOLO

from count_utils import count_by_class

DEFAULT_WEIGHTS = "models/firearms_yolo_no_m16/best.pt"


def load_model(weights_path: str = DEFAULT_WEIGHTS) -> YOLO:
    return YOLO(weights_path)


def detect_firearms(model: YOLO, source, conf: float = 0.7, save: bool = False):
    """입력 이미지를 YOLO 모델로 분석해 (클래스별 개수, raw 결과)를 반환한다."""
    results = model.predict(source=source, conf=conf, save=save)
    counts = count_by_class(results, model.names)
    return counts, results
