"""
라벨링된 사진 + 메타데이터를 Firebase에 업로드한다.
weaponClass 값은 YOLO 클래스명(소문자)과 정확히 일치시킨다.
"""
import glob
import os

from PIL import Image

from firebase_config import get_db, get_bucket

LOCAL_ROOT = "./raw_data"  # ./raw_data/k1/*.jpg 형태로 정리되어 있다고 가정
WEAPON_CLASSES = ["k1", "k2", "k2c1", "m16"]


def upload_class(weapon_class: str):
    db = get_db()
    bucket = get_bucket()

    files = sorted(glob.glob(os.path.join(LOCAL_ROOT, weapon_class, "*.jpg")))
    for idx, filepath in enumerate(files):
        filename = f"img_{idx:04d}.jpg"
        storage_path = f"weapons/{weapon_class}/{filename}"

        with Image.open(filepath) as img:
            width, height = img.size

        bucket.blob(storage_path).upload_from_filename(filepath)

        db.collection("images").add({
            "storagePath": storage_path,
            "weaponClass": weapon_class,
            "width": width,
            "height": height,
            "labelStatus": "labeled",
            "source": "직접촬영",
        })

    print(f"{weapon_class}: {len(files)}장 업로드 완료")


if __name__ == "__main__":
    for wc in WEAPON_CLASSES:
        upload_class(wc)