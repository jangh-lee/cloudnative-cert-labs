# KCA 02 실습 Policy · Rule · YAML

| 항목 | 값 |
|---|---|
| 학습자 가이드 | `guide.html` (단일 파일, 외부 리소스 없음, 목차·한 화면 한 단계·복사 버튼·기대 출력·막힐 때·진행 체크) |
| 기준 | Kyverno v1.19.2 (chart 3.9.2) 단일, v1.20 이상은 ClusterPolicy 미실행 |
| 클러스터 | kind `kca02` |
| kubeconfig | `~/.kca-lab/kca02.kubeconfig` (`KCA_LAB_HOME`로 변경) |
| 격리 | `~/.kube/config`·현재 context·helm repo 설정 미변경, 소유 표식 `kube-system/kca-lab-owner` + 로컬 id |
| 지원 | macOS(bash 3.2)·Linux, Docker 4GiB 이상 |
| kubectl | v1.35.x 실습용 `~/.kca-lab/bin/kubectl` (node v1.35.8, 지원 1.34~1.36), 순서 `KCA_KUBECTL` → `~/.kca-lab/bin/kubectl` → PATH, 시스템 kubectl 미변경 |
| 검증 | `qa/KCA_02_qa.md` |
| 슬라이드 | S04·S09·S11~S13 (전후 장), S06·S07 (데모) |

## kubectl v1.35

```bash
OS=$(uname -s | tr A-Z a-z); ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/'); U=https://dl.k8s.io/release/v1.35.8/bin/$OS/$ARCH/kubectl
mkdir -p ~/.kca-lab/bin && (cd ~/.kca-lab/bin && T="$(mktemp kubectl.XXXXXX)" && { curl -fsSLo "$T" "$U" && echo "$(curl -fsSL "$U.sha256")  $T" | shasum -a 256 -c && chmod +x "$T" && mv "$T" kubectl || { rm -f "$T"; false; }; })
~/.kca-lab/bin/kubectl version --client
```

| 동작 | 내용 |
|---|---|
| 설치 조건 | 임시 파일로 받아 sha256 확인 성공 시에만 실행 권한 부여·`~/.kca-lab/bin/kubectl`로 이동, 실패하면 임시 파일 삭제 |

## 명령

| 명령 | 내용 |
|---|---|
| `./setup.sh` | 도구·버전 점검 → inotify 점검 → kind 생성 또는 재사용(소유 확인) → Kyverno v1.19.2 설치·이미지 태그 확인 → 정책 webhook 대기 → Namespace `kca02` |
| `source ./env.sh` | 현재 셸 KUBECONFIG·실습용 kubectl(PATH 앞) 지정, 실습 폴더로 이동, 소유 확인 실패 시 환경 미변경 |
| `./verify.sh` | reset 후 0~9단계 자동 실행·판정, 문항 KCA-D1-008 풀이(또는 `KCA_Q008_FILE`) 판정 |
| `./reset.sh` | 실습 외 리소스 있으면 중단, 없으면 라벨 정책 삭제·Namespace 재생성 |
| `./teardown.sh` | 소유 표식 일치 클러스터와 전용 kubeconfig만 삭제 |

## 단계

| 단계 | 파일 | 결과 | 거부 주체 | 전후 비교 | 슬라이드 |
|---|---|---|---|---|---|
| 0 | 01·02 Pod (정책 없음) | 모두 created, 삭제 | - | 적용 전 | S04 |
| 1 | 03 ClusterPolicy | created·Ready | - | - | S06 |
| 2 | 01·02 Pod | 01 거부(`require-app`), 02 created | validate.kyverno.svc-fail | 적용 후 (0 ↔ 2) | S04 |
| 3 | `kubectl explain` | name·match `-required-`, 유형 필드 4개 | - | - | S07 |
| 4 | 04 유형 0개 · 05 유형 2개 | 거부 `No operation` · `Multiple operations` | validate-policy.kyverno.svc | 적용 전 (4 ↔ 1) | S09 |
| 5 | 06 rule 아래 failureAction | 거부 `unknown field "spec.rules[0].failureAction"` | API 서버(strict) | 적용 전 | S11 |
| 6 | 07 validate 아래 → 02 Pod | created·Ready, 02 거부(`require-team`) | validate.kyverno.svc-fail | 적용 후 (5 ↔ 6) | S11 |
| 7 | 08 = 07에서 match만 뺌 | 거부 `spec.rules[0].match: Required value`, 기존 07 유지 | API 서버(스키마) | 적용 전 (7 ↔ 6) | S12 |
| 8 | 09 규칙 이름 중복 | 거부 `Duplicate rule name: 'require-label'` | validate-policy.kyverno.svc | 적용 전 | S13 |
| 9 | 10 이름 나눔 | created, `require-env require-tier` | - | 적용 후 (8 ↔ 9) | S13 |
| 과제 | 11 dry-run → `exams/items/KCA-D1-008.solution.yaml` → 11·12 dry-run | 정책 전 11 통과, 정책 후 11 거부(`require-owner`)·12 통과 | validate.kyverno.svc-fail | 적용 전후 (11) | S05 |

## 과제 판정

| 실행 | 결과 |
|---|---|
| `./verify.sh` | 학습자 패키지에는 풀이 `KCA-D1-008.solution.yaml`이 없음 → `SKIP: 문항 풀이 파일 없음`, 과제 외 단계만 판정 |
| `KCA_Q008_FILE=my-require-owner.yaml ./verify.sh` | 가이드 과제 조건대로 쓴 내 답안으로 과제까지 판정, 경로는 실습 폴더 기준 또는 절대 경로 |
| 지정한 파일이 없음 | `FAIL: KCA_Q008_FILE 없음` |

## 알려진 문제

| 항목 | 처리 |
|---|---|
| Kyverno v1.20 이상 | 레거시 정책 미실행, setup이 v1.19.2 고정·확인 |
| inotify `max_user_instances` < 512 | setup이 중단하고 OS별 해결 명령 출력(`KCA_SKIP_INOTIFY=1`로 무시) |
| 다른 kind 클러스터 실행 중 | 경고만, 건드리지 않음 |
| webhook 준비 지연 | 서버 dry-run 성공까지 최대 120초 대기 |
| 같은 이름 클러스터(소유 표식 불일치) | setup·teardown 중단 |
| kubectl `--validate=false` | unknown field가 거부되지 않고 버려질 수 있음, 실습은 kubectl 기본값(strict) |

## 가이드 생성

| 항목 | 경로 |
|---|---|
| 단계 정의 | `../_tools/KCA_02_steps.json` |
| 출력 수집 | `../_tools/guide_walk.py KCA_02 legacy` |
| HTML 생성 | `../_tools/KCA_02_guide_build.py` (골격 `templates/lab/guide_shell.py`) |
| UI 테스트 | `../_tools/guide_ui_test.mjs` |
