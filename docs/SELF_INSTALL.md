# 내 폰에 직접 설치해 보기

스토어도 소셜 로그인 키도 없이, **내 PC의 서버 + 내 Galaxy 폰**만으로 전부 써 보는 방법이다.
(스토어용 정식 배포는 `docs/RELEASE.md`, `docs/OPERATIONS.md`, `docs/CLOSED_TEST.md`)

|             | 길 A. 디버그 앱 + PC 서버 (추천)  | 길 B. 릴리스 앱 + 서버 호스팅  |
| ----------- | --------------------------------- | ------------------------------ |
| 걸리는 시간 | 30분                              | 반나절 이상                    |
| 필요한 것   | PC, USB 케이블, 같은 Wi-Fi        | 위에 더해 도메인·VPS·업로드 키 |
| 로그인      | **개발용 로그인**(소셜 키 불필요) | 카카오/구글 키 필요            |
| 푸시 알림   | 안 옴(Firebase 키 없음)           | Firebase 키 넣으면 옴          |
| PC 끄면     | 앱이 서버에 못 붙음               | 24시간 동작                    |

## 길 A. 디버그 앱 + PC 서버

### 0. 준비물 (한 번만)

| 도구                            | 확인 명령            | 설치                                 |
| ------------------------------- | -------------------- | ------------------------------------ |
| Node 22 + pnpm 10               | `node -v`, `pnpm -v` | nodejs.org, `corepack enable`        |
| Docker                          | `docker -v`          | Docker Desktop                       |
| Flutter 3.47.6 + Android SDK 36 | `flutter doctor`     | docs.flutter.dev/get-started/install |
| (Windows) Git                   | `git --version`      | git-scm.com                          |

`flutter doctor`에서 **Android toolchain**에 ✓가 있어야 한다.

### 1. 코드 받기

```bash
git clone https://github.com/noob2220202/meeil.git && cd meeil
git checkout ccr-49ac8be2-cb4lg6        # PR이 합쳐지기 전이면. 합친 뒤엔 main
pnpm install
```

### 2. 서버 켜기 (PC에서)

```bash
docker compose up -d postgres                       # DB
cp apps/server/.env.example apps/server/.env        # AUTH_DEV_LOGIN=true 가 이미 들어 있다
pnpm --filter @meeil/server db:deploy               # 테이블 만들기
pnpm --filter @meeil/server db:seed                 # 지역·염소·업적
pnpm --filter @meeil/server dev                     # 서버 시작(이 창은 계속 켜 둔다)
```

다른 창에서 확인: `curl http://localhost:3000/health` → `{"ok":true,...}`

### 3. PC의 IP 알아내기

폰이 PC를 찾으려면 PC의 같은 Wi-Fi 안 주소가 필요하다.

- Windows: `ipconfig` → "IPv4 주소" (예: `192.168.0.12`)
- Mac: `ipconfig getifaddr en0`
- Linux: `hostname -I`

**Windows 방화벽**이 3000번 포트를 막으면 폰이 못 붙는다. 처음 서버를 켰을 때 뜨는 "허용" 창에서 **개인 네트워크 허용**을 누른다.
폰 브라우저에서 `http://<PC IP>:3000/health`를 열어 `{"ok":true}`가 보이면 준비 끝이다.

### 4. 폰 준비

1. 설정 → 휴대전화 정보 → 소프트웨어 정보 → **빌드번호**를 7번 눌러 개발자 모드 켜기
2. 설정 → 개발자 옵션 → **USB 디버깅** 켜기
3. USB로 PC에 연결 → 폰에 뜨는 "USB 디버깅 허용"에서 **허용**
4. PC에서 `flutter devices`에 내 폰이 보이는지 확인

### 5. 앱 설치

**방법 1 — 바로 실행(가장 쉬움)**

```bash
cd apps/mobile
flutter pub get
flutter run --dart-define=API_BASE_URL=http://<PC IP>:3000
```

폰에 설치되고 바로 실행된다. 첫 빌드는 5~10분 걸린다. 끝나면 USB를 뽑아도 앱은 남는다
(다만 `flutter run`으로 설치한 디버그 앱은 PC 없이 켜면 조금 느릴 수 있다).

**방법 2 — APK 파일을 만들어 설치**

```bash
cd apps/mobile
flutter build apk --debug --dart-define=API_BASE_URL=http://<PC IP>:3000
```

결과 파일: `apps/mobile/build/app/outputs/flutter-apk/app-debug.apk`

- USB 연결 상태에서 `adb install -r build/app/outputs/flutter-apk/app-debug.apk`
- 또는 파일을 폰으로 보내(카카오톡 "나에게", 드라이브, USB 복사) 폰에서 열어 설치 → "출처를 알 수 없는 앱" 허용

### 6. 써 보기

1. 앱 실행 → 권한 안내 → **위치 권한은 "대략적 위치", "앱 사용 중에만 허용"**
2. 로그인 화면의 **"개발용 로그인"** 버튼 → 아무 ID(예: `me1`) 입력
3. 약관 동의 → 생년월일(만 14세 이상) → 닉네임
4. 지도에서 내 시와 염소 확인

### 7. 편지 왕복을 혼자 해 보기

편지는 **다른 사람**에게만 보낼 수 있다. 계정이 하나 더 필요하다.

- 폰 하나로 `me1`과 `me2`를 번갈아 로그인하면 된다(로그아웃 → 다른 ID로 개발용 로그인). 폰이 두 대면 한 대씩.

흐름:

1. `me2`로 가입해 닉네임을 정한다(예: 받는염소) → 로그아웃
2. `me1`로 로그인 → **염소가 내 시에 있을 때** 편지 맡기기 → 받는 사람 닉네임 검색
3. 염소가 걸어서 이동한다(수 시간~며칠). 빨리 보고 싶으면 아래 "시간 줄이기".
4. 도착하면 `me2`로 로그인해 편지함 확인 → 답장

**염소가 내 시에 없으면** 편지를 맡길 수 없다. 지금 어느 시에 염소가 있는지는 지도에 보인다.
내 시를 바꾸려면 PC에서(위치 모의):

```bash
# 내 계정을 염소가 있는 시로 옮기기(개발용). <시코드>는 지도의 염소가 있는 시
docker compose exec postgres psql -U meeil meeil -c \
  "update users set \"lastRegionCode\"='<시코드>', \"lastRegionReportedAt\"=now() where nickname='<내 닉네임>'"
```

**시간 줄이기**: 편지 도착을 앞당기려면 관리자 "특급 배달"을 쓴다(`docs/ADMIN.md`,
`ADMIN_PASSWORD=... pnpm --filter @meeil/server admin:create 내아이디 ADMIN` 으로 관리자를 만들고
`pnpm --filter @meeil/admin dev` → http://localhost:5173/admin/).

### 문제 해결

| 증상                                 | 원인·해결                                                                                                                           |
| ------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------- |
| 앱이 "서버에 연결할 수 없어요"       | 폰과 PC가 **같은 Wi-Fi**인지, 폰 브라우저로 `http://<PC IP>:3000/health`가 열리는지, 방화벽·VPN 확인. `--dart-define`의 IP가 맞는지 |
| 로그인 화면에 "개발용 로그인"이 없다 | **디버그 빌드**에서만 보인다(릴리스 빌드엔 없음). `flutter build apk --debug`로 만든 것인지 확인                                    |
| 개발용 로그인이 거절된다             | 서버 `.env`에 `AUTH_DEV_LOGIN=true`인지, 서버 재시작                                                                                |
| `flutter devices`에 폰이 없다        | USB 케이블(충전 전용 케이블 주의), USB 모드를 "파일 전송"으로, 디버깅 허용 팝업                                                     |
| 위치를 못 잡는다                     | 폰 위치 켜기, 앱 권한이 "대략적 위치"인지. 실내면 Wi-Fi 위치도 켜기                                                                 |
| 설치 중 "서명이 다르다"              | 예전에 설치한 앱과 서명이 달라서. 폰에서 메에일을 지우고 다시 설치                                                                  |
| PC IP가 바뀌었다                     | 공유기가 IP를 바꿔서. 다시 `--dart-define`으로 빌드(공유기에서 PC IP 고정 추천)                                                     |

---

## 길 B. 릴리스 앱 + 서버 호스팅

폰이 어디서든 쓸 수 있고, PC가 꺼져도 동작한다. 대신 **서버를 인터넷에 올려야** 한다.

### B-1. 서버 올리기

도메인과 VPS(Ubuntu 22.04+, 1코어/1GB 이상)가 필요하다. 전체 절차는 `docs/OPERATIONS.md` 1장.
요약:

```bash
# VPS에서
git clone … /srv/meeil && cd /srv/meeil
cp apps/server/.env.example apps/server/.env.production      # 편집
echo 'API_DOMAIN=api.<내도메인>' > .env
echo "POSTGRES_PASSWORD=$(openssl rand -base64 32)" >> .env
pnpm install && pnpm --filter @meeil/admin build
docker compose --profile full --profile prod up -d --build
```

`.env.production`에 최소로 필요한 값: `JWT_SECRET`, `ADMIN_SECRET_KEY`(각각 `openssl rand -base64 48`),
`PUBLIC_BASE_URL=https://api.<내도메인>`, `AUTH_DEV_LOGIN=false`(운영은 true면 서버가 안 켜진다).
사진을 쓰려면 R2 값도(`docs/PUSH_AND_STORAGE.md`).

DNS에서 `api.<내도메인>`을 VPS IP로 연결하면 HTTPS가 자동으로 붙는다.
확인: `https://api.<내도메인>/health`

### B-2. 로그인 키 만들기 (릴리스는 개발용 로그인이 없다)

- **카카오·구글** 둘 중 하나만 해도 된다 → `docs/SOCIAL_LOGIN.md`
- 키 해시/SHA-1은 **릴리스 서명 키 기준**으로 등록해야 한다(아래 B-3에서 만든 키).

### B-3. 서명 키 만들기 (한 번만, 잃어버리면 안 됨)

```bash
keytool -genkeypair -v -keystore ~/meeil-upload.jks -storetype PKCS12 \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

`apps/mobile/android/key.properties` (커밋 금지):

```properties
storeFile=/절대/경로/meeil-upload.jks
storePassword=...
keyAlias=upload
keyPassword=...
```

### B-4. APK 빌드·설치

스토어에 올리지 않고 내 폰에만 설치하려면 **APK**로 만든다(스토어용은 AAB).

```bash
cd apps/mobile
flutter build apk --release \
  --dart-define=API_BASE_URL=https://api.<내도메인> \
  --dart-define=KAKAO_NATIVE_APP_KEY=... \
  --dart-define=GOOGLE_SERVER_CLIENT_ID=...
```

결과: `build/app/outputs/flutter-apk/app-release.apk` → 폰으로 보내 설치(또는 `adb install`).
광고 ID는 기본값(테스트 광고)을 그대로 둔다. 푸시를 쓰려면 `FIREBASE_*` 값도 넣는다.

> 같은 폰에 길 A의 디버그 앱이 있으면 서명이 달라 덮어쓸 수 없다. 먼저 지운다.

### B-5. 확인

`docs/CLOSED_TEST.md` 4장의 "14일 테스트 계획" 1일차 항목을 그대로 따라 하면 된다.
