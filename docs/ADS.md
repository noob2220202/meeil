# 보상형 광고 (AdMob) 설정

SPEC 7.1: 보상형 광고만 쓰고, 포인트는 **AdMob 서버측 검증(SSV) 콜백으로만** 지급한다.

## 흐름

1. 앱이 `RewardedAd`를 불러 `ServerSideVerificationOptions(userId: <우리 사용자 id>)`를 설정하고 보여 준다.
2. 끝까지 보면 AdMob이 `GET https://api.<도메인>/ads/reward-callback?...&signature=...&key_id=...`를 부른다.
3. 서버는 서명을 구글 공개키(`https://www.gstatic.com/admob/reward/verifier-keys.json`, 하루 캐시)로 검증하고,
   `transaction_id`로 한 번만, 하루 5회까지 +2P를 원장에 기록한다.
4. 앱은 `GET /ads/status`를 잠시 확인해 늘어난 횟수를 보고 "+2P"를 보여 준다.

## 개발 중

- 앱의 광고 단위 기본값은 구글 **테스트 광고**(`ca-app-pub-3940256099942544/5224354917`), 앱 ID도 테스트 ID다.
- 테스트 광고는 SSV 콜백이 오지 않으므로, 개발 서버(`AUTH_DEV_LOGIN=true`)에서는 디버그 앱이 `POST /ads/dev-reward`로
  같은 지급 경로(같은 상한)를 부른다. production 서버에는 이 라우트가 없다.

## 출시 전 할 일

1. AdMob 콘솔에서 앱과 보상형 광고 단위를 만들고, 광고 단위의 "서버측 확인" URL에 `https://api.<도메인>/ads/reward-callback`을 넣는다(콘솔의 확인 요청은 쿼리 없이 와서 200을 돌려준다).
2. 서버 `.env`의 `ADMOB_AD_UNIT_IDS`에 광고 단위 ID를 넣는다(다른 광고 단위의 콜백은 거절).
3. 릴리스 빌드: `flutter build appbundle --dart-define=ADMOB_APP_ID=ca-app-pub-...~... --dart-define=ADMOB_REWARDED_UNIT_ID=ca-app-pub-.../...`
4. Play Console 데이터 보안·광고 ID 선언(google_mobile_ads가 AD_ID 권한을 추가한다).

## 미성년 보호

- 모든 요청은 비맞춤형 광고, 콘텐츠 등급 상한 T.
- 서버가 `/me`의 `ads.underAge`(만 19세 미만)를 알려 주면 등급 상한 PG와 `ageRestrictedTreatment.teen`을 적용한다. 생년월일은 앱에 보내지 않는다.
