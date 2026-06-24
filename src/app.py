import cv2
import numpy as np
import streamlit as st
from PIL import Image

from pipeline import DEFAULT_WEIGHTS, detect_firearms, load_model

st.set_page_config(page_title="군수물자(총기류) 탐지", layout="wide")


@st.cache_resource
def get_model(weights_path: str):
    return load_model(weights_path)


st.title("YOLO 기반 군수품(총기류) 탐지 및 카운팅")

uploaded_file = st.file_uploader("사진을 업로드하세요", type=["jpg", "jpeg", "png"])
conf_threshold = st.slider("탐지 confidence 임계값", 0.0, 1.0, 0.7, 0.05)

if uploaded_file is not None:
    model = get_model(DEFAULT_WEIGHTS)

    image = Image.open(uploaded_file).convert("RGB")
    counts, results = detect_firearms(model, np.array(image), conf=conf_threshold)

    annotated_bgr = results[0].plot()
    annotated_rgb = cv2.cvtColor(annotated_bgr, cv2.COLOR_BGR2RGB)

    col1, col2 = st.columns(2)
    with col1:
        st.image(image, caption="원본 이미지", use_container_width=True)
    with col2:
        st.image(annotated_rgb, caption="탐지 결과", use_container_width=True)

    st.subheader("종류별 개수")
    if counts:
        st.table({"종류": list(counts.keys()), "개수": list(counts.values())})
        st.write(f"**총 개수: {sum(counts.values())}**")
    else:
        st.info("탐지된 객체가 없습니다.")
