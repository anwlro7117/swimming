VR실 TUIO 키트
==============

구조
  YTS.exe ──(TUIO / UDP 3333)──> bridge.js ──(웹)──> 크롬 벽 화면 3개 + 조작 모니터 관제 화면

준비 (VR실 PC 1회)
  1. Node.js LTS 설치 (nodejs.org). 인터넷 없으면 설치 파일 USB로 옮긴다.
  2. 이 폴더를 통째로 복사한다. 예: C:\vr-tuio-kit
  3. 씽킹플레이 콘텐츠는 끈다. 같은 3333 포트를 쓴다.

순서
  1. YTS.exe 실행. TUIO 켜짐 확인 ("TUIO UDP (T)" 버튼).
  2. 1_bridge_start.bat  → 검은 창 그대로 둔다. 닫으면 끊긴다.
  3. 0_monitor_number.bat → 모니터마다 큰 번호가 뜬다. 번호를 적는다.
  4. config.json 화면마다 "screen": {"x": 왼쪽 픽셀, "y": 위 픽셀} 이 있으면 그 위치 화면에 띄운다.
     (vr360 "화면 감지" 표의 left/top 값). "screen" 지우면 "monitor" 번호(윈도우 DISPLAY 번호)로 찾는다.
     조작 모니터 = "operatorScreen" 또는 "operatorMonitor".
     (조작 화면 표에서 고치고 "저장"을 눌러도 된다)
  5. 2_screens_open.bat  → 벽 화면 3개에 테스트 화면, 조작 모니터에 관제 화면.
  6. 관제 화면 "모서리 보정": 화면 골라 시작 → 그 화면 노란 원 좌상단 → 우하단 순서로 손바닥 대고 떼기.
     벽 화면 3개 다 하고 "저장". 화면들은 F5(또는 3번 닫고 2번 다시).
  7. 3_screens_close.bat → 화면 전부 닫기.

확인 포인트
  - 관제 화면 "TUIO 수신 중" 초록 → 센서 신호 들어옴.
    빨강이면: YTS TUIO 꺼짐 / 포트가 3333 아님 / 씽킹플레이가 포트 점유.
  - 보정 후 손 대는 곳에 원이 따라오면 성공.
  - 바닥 센서 고장 → 바닥 화면 2개는 config에서 뺐다. 벽 3면만 쓴다.
    바닥 카메라에서 이상한 점이 들어와도 벽 구역 밖이면 무시된다.
  - 가만히 서 있는 발은 1.5초 뒤 무시된다 (회색 "머무름 무시"). 관제 화면 "머무름 무시(ms)"에서 조정.

센서 없이 시험
  9_simulator.bat → 가짜 터치 신호를 보낸다. 집 PC에서 게임 만들 때 쓴다.
  마우스 클릭도 터치로 들어온다.

게임 만들기
  public 폴더에 game.html 넣고:
    <script src="/tuio-client.js"></script>
    const t = new TuioTouch();               // 화면은 주소 ?d=front 로 정해짐
    t.on('down', p => { /* p.x, p.y = 화면 픽셀 */ });
    t.on('move', p => {});
    t.on('up',   p => {});
  띄우기: 명령창에서  node launch.js game.html   → 벽 화면 3개에 game.html?d=화면id
  화면 하나만 쓰는 게임이면 그 화면 주소만 열면 된다.

파일
  bridge.js        TUIO 수신 + 웹 서버 (http://localhost:8080)
  launch.js        모니터별 크롬 키오스크 실행 (크롬 없으면 엣지)
  config.json      포트, 화면-모니터 번호, 화면별 센서 좌표 구역
  public/          관제(operator) · 화면 테스트(display) · 모니터 번호(identify) · tuio-client.js
  sim.js           가짜 TUIO 송신기
