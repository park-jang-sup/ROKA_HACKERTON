"""
Firebase Admin SDK 초기화 모듈.
db/ 안의 다른 스크립트들은 이 모듈의 get_db(), get_bucket()을 통해서만 Firebase에 접근한다.
"""
import os
import firebase_admin
from firebase_admin import credentials, firestore, storage

# serviceAccountKey.json은 레포에 절대 커밋하지 않는다 (.gitignore 처리 필수)
SERVICE_ACCOUNT_PATH = os.environ.get("FIREBASE_SERVICE_ACCOUNT", "serviceAccountKey.json")
STORAGE_BUCKET = os.environ.get("FIREBASE_STORAGE_BUCKET", "roka-hackathon.appspot.com")

_app = None


def init_firebase():
    global _app
    if _app is None:
        if not os.path.exists(SERVICE_ACCOUNT_PATH):
            raise FileNotFoundError(
                f"서비스 계정 키를 찾을 수 없습니다: {SERVICE_ACCOUNT_PATH}\n"
                "Firebase 콘솔 > 프로젝트 설정 > 서비스 계정에서 발급받아 두세요."
            )
        cred = credentials.Certificate(SERVICE_ACCOUNT_PATH)
        _app = firebase_admin.initialize_app(cred, {"storageBucket": STORAGE_BUCKET})
    return _app


def get_db():
    init_firebase()
    return firestore.client()


def get_bucket():
    init_firebase()
    return storage.bucket()