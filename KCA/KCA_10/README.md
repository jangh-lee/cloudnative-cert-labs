# KCA 10 실습 Policy · ClusterPolicy

| 항목 | 값 |
|---|---|
| 학습자 가이드 | `guide.html` (단일 파일, 외부 리소스 없음, 목차·한 화면 한 단계·복사 버튼·기대 출력·막힐 때·진행 체크) |
| 기준 | Kyverno v1.19.2 (chart 3.9.2) 단일, v1.20 이상은 ClusterPolicy·Policy 미실행 |
| 클러스터 | kind `kca10` |
| Namespace | `kca10-blue`, `kca10-green` |
| kubeconfig | `~/.kca-lab/kca10.kubeconfig` (`KCA_LAB_HOME`로 변경) |
| 격리 | `~/.kube/config`·현재 context·helm repo 설정 미변경, 소유 표식 `kube-system/kca-lab-owner` + 로컬 id |
| 지원 | macOS(bash 3.2)·Linux, Docker 4GiB 이상 |
| kubectl | v1.35.x 실습용 `~/.kca-lab/bin/kubectl` (node v1.35.8, 지원 1.34~1.36), 순서 `KCA_KUBECTL` → `~/.kca-lab/bin/kubectl` → PATH, 시스템 kubectl 미변경 |
| 검증 | `qa/KCA_10_qa.md` |
| 슬라이드 | 기준 덱 `revised/KCA_10` 25장: S09·S12·S13·S17~S20 (전후 장), S08·S11·S16·S24 (준비·개념·데모), S25 (과제) |

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
| `./setup.sh` | 도구·버전 점검 → inotify 점검 → kind 생성 또는 재사용(소유 확인) → Kyverno v1.19.2 설치·이미지 태그 확인 → 정책 webhook 대기 → Namespace 2개 |
| `source ./env.sh` | 현재 셸 KUBECONFIG·실습용 kubectl(PATH 앞) 지정, 실습 폴더로 이동, 소유 확인 실패 시 환경 미변경 |
| `./verify.sh` | reset 후 0~7단계 자동 실행·판정, 문항 KCA-D4-007 풀이(또는 `KCA_Q007_FILE`) 판정 |
| `./reset.sh` | 실습 외 리소스 있으면 중단, 없으면 라벨 정책·Pod 삭제 후 빈 Namespace 2개 |
| `./teardown.sh` | 소유 표식 일치 클러스터와 전용 kubeconfig만 삭제 |

## 단계

| 단계 | 파일 | 결과 | 전후 비교 | 슬라이드 |
|---|---|---|---|---|
| 0 | 01·02 (정책 없음) | 두 Pod 모두 created, 삭제 | 적용 전 | S09 |
| 1 | 03 Policy | 생성 직후 READY는 조회 시점에 따라 빈칸 또는 True(관측 예시), wait `condition met` 이후 READY True, `Ready=True Succeeded Ready` | - | S11 |
| 2 | 조회 | `get pol -A` NAMESPACE kca10-blue, `get cpol` 없음 | - | S11 |
| 3 | 01·02 | blue 거부(`require-team`), green created | 적용 후 (0 ↔ 3) | S12·S13 |
| 4 | 08 → 04 ClusterPolicy | 08 `Unsupported value: "Deny"`, wait NotFound → 04 created, `condition met`, READY True | Ready 전후 (08 ↔ 04) | S16 |
| 5 | 02·01·07 | green 거부, blue 두 정책 모두 거부, with-team created | 적용 후 (3 ↔ 5) | S17~S19 |
| 6 | 05·06 Policy | `namespaces`·`kinds: [Namespace]` 생성 거부, 조회 NotFound | 적용 후 (4 ↔ 6) | S20 |
| 7 | 조회 | 남은 Pod with-team, 두 정책 READY True | - | S24 |
| 과제 | `q007-template.yaml` → 답안, 판정 풀이 `exams/items/KCA-D4-007.solution.yaml` | green Policy Ready, team 없는 green Pod 거부, with-team created | 적용 후 (3 ↔ 과제) | S25 |

## 과제 판정

| 실행 | 결과 |
|---|---|
| `./verify.sh` | 학습자 패키지에는 풀이 `KCA-D4-007.solution.yaml`이 없음 → `SKIP: 문항 풀이 파일 없음`, 과제 외 단계만 판정 |
| `KCA_Q007_FILE=q007-template.yaml ./verify.sh` | 가이드 과제 조건대로 쓴 내 답안으로 과제까지 판정, 경로는 실습 폴더 기준 또는 절대 경로 |
| 지정한 파일이 없음 | `FAIL: KCA_Q007_FILE 없음` |

## 알려진 문제

| 항목 | 처리 |
|---|---|
| Kyverno v1.20 이상 | 레거시 정책 미실행, setup이 v1.19.2 고정·확인 |
| inotify `max_user_instances` < 512 | setup이 중단하고 OS별 해결 명령 출력(`KCA_SKIP_INOTIFY=1`로 무시) |
| 다른 kind 클러스터 실행 중 | 경고만, 건드리지 않음 |
| webhook 준비 지연 | 서버 dry-run 성공까지 최대 120초 대기 |
| 같은 이름 클러스터(소유 표식 불일치) | setup·teardown 중단 |
| ClusterPolicy 범위 | 실습 안전을 위해 `namespaces: ["kca10-*"]`로 한정(match 상세는 11회차) |

## 가이드 생성

| 항목 | 경로 |
|---|---|
| 단계 정의 | `../_tools/KCA_10_steps.json` |
| 출력 수집 | `../_tools/guide_walk.py KCA_10 legacy` |
| HTML 생성 | `../_tools/KCA_10_guide_build.py` (골격 `templates/lab/guide_shell.py`) |
| UI 테스트 | `../_tools/guide_ui_test.mjs` (`LESSON=KCA_10 PORT=9350`) |
