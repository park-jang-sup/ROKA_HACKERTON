import io
from fastapi import FastAPI, UploadFile, File, Header, HTTPException
from fastapi.responses import HTMLResponse
from PIL import Image
from ultralytics import YOLO

app = FastAPI()
model = YOLO("best.pt")

CONF_THRESHOLD = 0.5
API_KEY = "팀에서만_아는_임의의_긴_문자열"  # 나중에 직접 정해서 바꾸세요


@app.get("/health")
def health():
    return {"status": "ok"}


@app.get("/", response_class=HTMLResponse)
def home():
    return """
<!DOCTYPE html>
<html lang="ko">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>화기 탐지 테스트</title>
<style>
  body { font-family: -apple-system, sans-serif; max-width: 480px; margin: 0 auto; padding: 20px; }
  h1 { font-size: 20px; }
  input[type=file] { width: 100%; padding: 16px; margin: 16px 0; }
  button { width: 100%; padding: 14px; font-size: 16px; background: #1a73e8; color: white;
           border: none; border-radius: 8px; }
  button:disabled { background: #ccc; }
  #preview { width: 100%; margin-top: 12px; border-radius: 8px; display: none; }
  #result { margin-top: 20px; }
  .item { padding: 10px; border-bottom: 1px solid #eee; }
  .loading { text-align: center; color: #888; margin-top: 20px; }
</style>
</head>
<body>
  <h1>화기 종류/수량 탐지 테스트</h1>
  <input type="file" id="fileInput" accept="image/*" capture="environment">
  <img id="preview">
  <button id="submitBtn" disabled>분석하기</button>
  <div id="result"></div>

<script>
  const fileInput = document.getElementById('fileInput');
  const preview = document.getElementById('preview');
  const submitBtn = document.getElementById('submitBtn');
  const result = document.getElementById('result');
  const API_KEY = "팀에서만_아는_임의의_긴_문자열";

  fileInput.addEventListener('change', () => {
    if (fileInput.files[0]) {
      preview.src = URL.createObjectURL(fileInput.files[0]);
      preview.style.display = 'block';
      submitBtn.disabled = false;
      result.innerHTML = '';
    }
  });

  submitBtn.addEventListener('click', async () => {
    submitBtn.disabled = true;
    result.innerHTML = '<div class="loading">분석 중...</div>';

    const formData = new FormData();
    formData.append('file', fileInput.files[0]);

    try {
      const res = await fetch('/detect', {
        method: 'POST',
        headers: { 'x-api-key': API_KEY },
        body: formData
      });
      const data = await res.json();

      const counts = {};
      data.detections.forEach(d => {
        counts[d.class] = (counts[d.class] || 0) + 1;
      });

      if (Object.keys(counts).length === 0) {
        result.innerHTML = '<div class="item">탐지된 화기가 없습니다.</div>';
      } else {
        result.innerHTML = Object.entries(counts).map(([cls, count]) =>
          `<div class="item">${cls} (${count}정)</div>`
        ).join('');
      }
    } catch (e) {
      result.innerHTML = '<div class="item">오류 발생: ' + e.message + '</div>';
    } finally {
      submitBtn.disabled = false;
    }
  });
</script>
</body>
</html>
"""


@app.post("/detect")
async def detect(file: UploadFile = File(...), x_api_key: str = Header(None)):
    if x_api_key != API_KEY:
        raise HTTPException(status_code=401, detail="Unauthorized")

    image_bytes = await file.read()
    image = Image.open(io.BytesIO(image_bytes)).convert("RGB")

    result = model(image)[0]
    detections = []
    for box in result.boxes:
        confidence = float(box.conf[0])
        if confidence < CONF_THRESHOLD:
            continue
        class_id = int(box.cls[0])
        detections.append({
            "class": model.names[class_id],
            "confidence": confidence,
        })

    return {"detections": detections}