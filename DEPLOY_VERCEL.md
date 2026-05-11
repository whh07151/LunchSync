# LSPOS Vercel 배포 가이드

## 사전 준비
- GitHub 계정 (whh07151)에 이미 LunchSync repo + LSPOS 브랜치 push 완료 ✓
- LSPOS Next.js 14 + TypeScript + Tailwind 빌드 완료 (`npx next build` exit 0)
- 백엔드 AWS 배포가 끝나 있어야 함 (또는 임시로 localhost 로 시작 가능)

## 1단계: Vercel 계정 + 프로젝트 import (2분)

1. https://vercel.com 접속 → **Continue with GitHub** 클릭 (OAuth 1회만)
2. Dashboard → **Add New** → **Project** 클릭
3. `whh07151/LunchSync` 저장소를 찾아 **Import** 클릭

## 2단계: 프로젝트 설정 (3분)

| 항목 | 값 |
|---|---|
| **Project Name** | `lunchsync-pos` (또는 원하는 이름) |
| **Framework Preset** | `Next.js` (자동 감지) |
| **Root Directory** | `LunchSync-LSPOS` ⚠️ 중요 |
| **Build Command** | `npm run build` (기본값) |
| **Output Directory** | `.next` (기본값) |
| **Install Command** | `npm install` (기본값) |
| **Production Branch** | `LSPOS` |

> **Root Directory 변경 필수**: 기본값은 repo 루트(`./`)지만 LSPOS는 하위 디렉토리.
> "Edit" → `LunchSync-LSPOS` 입력 후 **Continue**.

## 3단계: 환경 변수 설정 (2분)

**Environment Variables** 섹션에서 추가:

```
NEXT_PUBLIC_BACKEND_BASE_URL=https://<EC2_퍼블릭_도메인_또는_IP>/api
NEXT_PUBLIC_POLLING_INTERVAL_MS=3000
```

> 백엔드가 HTTPS 가 아니면 (`http://13.125.165.80/api` 같이) Vercel 도메인에서 호출 시
> Mixed Content 경고. EC2 에 Let's Encrypt + nginx 로 HTTPS 적용 권장 (DevOps 가이드 참조).

## 4단계: 첫 배포 (1~2분)

**Deploy** 클릭 → Vercel 이 자동으로:
1. GitHub 에서 LSPOS 브랜치 clone
2. `LunchSync-LSPOS/` 디렉토리로 이동
3. `npm install` 실행
4. `npm run build` 실행 (Next.js 정적 + 동적 라우트 빌드)
5. CDN 배포 → URL 발급

배포 완료 시 `https://lunchsync-pos.vercel.app` 같은 도메인 발급됨.

## 5단계: 백엔드 CORS 화이트리스트 추가 (2분)

EC2 백엔드 `.env` 에 다음 추가:

```bash
NODE_ENV=production
CORS_ALLOWED_ORIGINS=https://lunchsync-pos.vercel.app
```

PM2 재시작:
```bash
pm2 restart lunchsync-backend
```

이제 LSPOS 가 백엔드 API 를 호출 가능 (Preflight + Origin 검증 통과).

## 자동 배포 (이후)

LSPOS 브랜치 push → Vercel 자동 감지 → 새 배포 → URL 갱신.

```bash
git push origin LSPOS  # → 60초 내 새 배포 완료
```

Pull Request 라면 **Preview Deployment** 가 자동 생성됨 (별도 URL). 머지 시 Production 으로 승격.

## 도메인 커스터마이징 (선택)

Vercel Dashboard → 프로젝트 → **Settings** → **Domains** → 원하는 도메인 추가.
무료 도메인은 `*.vercel.app` 만 가능. 커스텀 도메인은 DNS 설정 추가 필요.

## 문제 해결

### "API 호출 실패 (CORS)"
- 백엔드 `.env` 의 `CORS_ALLOWED_ORIGINS` 에 Vercel 도메인이 포함됐는지 확인.
- 백엔드를 PM2 재시작 했는지 확인 (`pm2 restart lunchsync-backend`).

### "Mixed Content"
- 백엔드가 HTTP 인데 LSPOS 가 HTTPS 면 브라우저가 차단.
- 해결: EC2 에 Let's Encrypt 인증서 + nginx 리버스 프록시.

### "환경 변수 안 먹힘"
- `NEXT_PUBLIC_` 접두사가 붙은 변수만 브라우저에서 접근 가능 (Next.js 규칙).
- Vercel 환경 변수 변경 후 **Redeploy** 필수.

### "Root Directory 못 찾음"
- Vercel Settings → General → **Root Directory** 가 `LunchSync-LSPOS` 인지 재확인.
- 잘못됐으면 수정 후 **Redeploy**.

## 비용

- **Hobby (무료 플랜)**:
  - 100 GB 트래픽/월
  - 무제한 빌드
  - SSL 무료
  - 캡스톤 시연 + 학교 발표 트래픽 충분히 수용

---

## 캡스톤 발표 어필 포인트

> "LSPOS 는 Vercel 에 자동 배포돼서, 사장님이 별도 설치 없이 웹브라우저만으로 매장 POS를 즉시 사용할 수 있습니다. Git push 한 번으로 CI/CD 가 자동 동작합니다."

배포 URL: `https://lunchsync-pos.vercel.app/login`
