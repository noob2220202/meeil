# 관리자 웹 운영 (SPEC 9.4)

## 관리자 계정 만들기

로그인은 아이디·비밀번호·TOTP(인증 앱 6자리) 세 가지가 모두 맞아야 한다.

```bash
# 개발
ADMIN_PASSWORD='12자 이상 비밀번호' pnpm --filter @meeil/server admin:create boss ADMIN
# 운영 컨테이너
docker compose exec -e ADMIN_PASSWORD='...' api node dist/admin/cli.js boss ADMIN
```

- 출력되는 `otpauth://` URI(또는 수동 입력 키)를 Google Authenticator 등에 등록한다.
- `ADMIN_PASSWORD`를 주지 않으면 무작위 비밀번호를 만들어 한 번 출력한다.
- 같은 아이디로 다시 실행하면 비밀번호와 TOTP를 재설정한다(분실 시).
- 역할: `ADMIN`(최고 관리자) / `MODERATOR`(운영자). 영구 정지·해제, 공지·푸시, 특급 배달, 공식 계정 글, 감사 로그는 ADMIN만.
- TOTP 시크릿은 `ADMIN_SECRET_KEY`(32자 이상, production 필수)로 AES-256-GCM 암호화해 저장한다. 키를 바꾸면 모든 관리자를 다시 만들어야 한다.

## 배포 (Caddy)

관리자 SPA는 `/admin/`, API 호출은 `/api/*`(접두사를 떼고 서버로)로 보낸다. 앱용 API는 그대로 루트.

```caddyfile
api.<도메인> {
    handle_path /api/* {
        reverse_proxy api:3000
    }
    handle /admin* {
        root * /srv/admin          # apps/admin/dist 를 복사
        uri strip_prefix /admin
        try_files {path} /index.html
        file_server
        header X-Frame-Options DENY
        header Cache-Control "no-store"
    }
    handle {
        reverse_proxy api:3000
    }
}
```

빌드: `pnpm --filter @meeil/admin build` → `apps/admin/dist`.

## 화면

- **대시보드**: 가입자, 오늘 접속·편지, 처리 대기 신고, 미확인 사진, 오늘 먹힌 편지, 7일 추이.
- **신고 큐**: 오래된 것부터. 🐐 먹기(삭제) / 기각 / 사용자 제재로 이동. 같은 대상의 신고 수 표시.
- **사진 검수**: 최신순 미확인 사진. ✓ 확인 완료 / 🐐 먹기. 배달 중이면 도착 예정 시각이 보인다(그 전에 먹으면 받는 사람에게 가지 않는다).
- **사용자**: 닉네임·ID 검색, 상세(생년월일·소셜 ID는 보이지 않고 나이 확인 여부만), 경고 → 7일 정지 → 영구 정지, 해제.
- **롤링페이퍼**: 레벨·지역(`*`=전체)·이번/다음 장 주제, 공식 계정("메에일 우체국") 환영 글.
- **공지·푸시**: 공지 게시(고정), 알림을 켠 사용자에게 푸시.
- **감사 로그**: 로그인과 모든 변경.

## 염소가 먹어버리는 이벤트 (SPEC 9.3)

- 배달 전: 받는 사람에게 도착하지 않고, 보낸 사람에게 "염소가 편지를 먹어버렸어요" 알림. 앱은 먹는 연출을 보여 준다.
- 도착 후: 보관함 항목이 "염소가 먹어버린 편지"로 바뀐다.
- 롤링 글: 두루마리에서 그 글 자리에 먹는 연출.
- 관련 신고는 자동으로 처리됨, 사진 검수도 끝난 것으로 표시. 원본(본문·사진)은 30일 뒤 매일 정리 작업이 지운다.
