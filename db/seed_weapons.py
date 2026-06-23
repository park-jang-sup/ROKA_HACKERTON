"""
weapons 마스터 컬렉션 초기 등록 스크립트.
실행: python seed_weapons.py
specsVerified=False인 필드(길이/무게 등)는 공식 자료로 직접 확인 후 채울 것.
"""
from firebase_config import get_db

WEAPONS = [
    {
        "code": "K1",
        "officialName": "K1 기관단총",
        "type": "기관단총",
        "caliber": "5.56x45mm (KM193 / K100 혼용)",
        "manufacturer": "S&T모티브(구 대우정밀공업)",
        "developedBy": "국방과학연구소(ADD)",
        "description": "K2보다 앞서 개발된 국내 최초 독자 개발 소화기. "
                       "K2와 하부 총몸이 호환되며 특수전사령부 등에서 주로 운용된다.",
        "specsVerified": False,
        "overallLengthMm": None,
        "weightKg": None,
    },
    {
        "code": "K2",
        "officialName": "K2 소총",
        "type": "돌격소총",
        "caliber": "5.56x45mm NATO (KM193 / K100 혼용)",
        "manufacturer": "S&T모티브(구 대우정밀)",
        "developedBy": "국방과학연구소(ADD)",
        "description": "1984년 정식 제식명을 받아 1985년부터 전방 전투부대에 우선 보급된 "
                       "대한민국 육군의 주력 제식 돌격소총. M16 소총과 탄창이 호환된다.",
        "specsVerified": False,
        "overallLengthMm": None,
        "weightKg": None,
    },
    {
        "code": "K2C1",
        "officialName": "K2C1 소총",
        "type": "돌격소총(K2 개량형)",
        "caliber": "5.56x45mm NATO (K2와 동일)",
        "manufacturer": "S&T모티브",
        "developedBy": "S&T모티브 / 육군본부",
        "description": "2014년 개발에 착수해 2016년부터 전방부대에 보급된 K2의 개량형. "
                       "신축형 개머리판과 피카티니 레일이 추가됐고 내부 구조·성능은 K2와 동일하다.",
        "specsVerified": False,
        "overallLengthMm": None,
        "weightKg": None,
    },
    {
        "code": "M16A1",
        "officialName": "M16A1 소총",
        "type": "돌격소총",
        "caliber": "5.56x45mm (.223 Remington / KM193 기준)",
        "manufacturer": "Colt(원본) / 대우정밀(면허생산, 모델명 603K)",
        "developedBy": "Colt's Manufacturing Company",
        "description": "1968년 한국군에 처음 제식으로 지급되었고, 1974~1985년 사이 "
                       "대우정밀에서 콜트 모델 603을 면허생산했다. "
                       "현재는 대부분 예비군용·교육용으로 전환되었다.",
        "specsVerified": False,
        "overallLengthMm": None,
        "weightKg": None,
    },
]


def seed():
    db = get_db()
    for weapon in WEAPONS:
        db.collection("weapons").document(weapon["code"]).set(weapon)
        print(f"등록 완료: {weapon['code']} ({weapon['officialName']})")


if __name__ == "__main__":
    seed()