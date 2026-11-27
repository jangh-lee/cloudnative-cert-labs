# KCA 03 실습 Admission Enforce · Audit

| 항목 | 값 |
|---|---|
| 학습자 가이드 | `guide.html` (단일 파일, 외부 리소스 없음, 목차·한 화면 한 단계·복사 버튼·기대 출력·막힐 때·진행 체크) |
| 기준 | Kyverno v1.19.2 (chart 3.9.2) 단일, v1.20 이상은 ClusterPolicy 미실행 |
| 커리큘럼 | KCA_Curriculum.pdf fff366a0 (2024-11-28) |
| 클러스터 | kind `kca03` |
| kubeconfig | `~/.kca-lab/kca03.kubeconfig` (`KCA_LAB_HOME`로 변경) |
| 격리 | `~/.kube/config`·현재 context·helm repo 설정 미변경, 소유 표식 `kube-system/kca-lab-owner` + 로컬 id |
| 지원 | macOS(bash 3.2)·Linux, Docker 4GiB 이상 |
| kubectl | v1.35.x 실습용 `~/.kca-lab/bin/kubectl` (node v1.35.8, 지원 1.34~1.36), 순서 `KCA_KUBECTL` → `~/.kca-lab/bin/kubectl` → PATH, 시스템 kubectl 미변경 |
| 검증 | `qa/KCA_03_qa.md` |
| 슬라이드 | S04·S08·S09 (전후 장), S06·S10·S11 |

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
| `./setup.sh` | 도구·버전 점검 → inotify 점검 → kind 생성 또는 재사용(소유 확인) → Kyverno v1.19.2 설치·이미지 태그 확인 → 정책 webhook 대기 → Namespace `kca03` |
| `source ./env.sh` | 현재 셸 KUBECONFIG·실습용 kubectl(PATH 앞) 지정, 실습 폴더로 이동, 소유 확인 실패 시 환경 미변경 |
| `./verify.sh` | reset 후 0~5단계 자동 실행·판정, 문항 KCA-D1-018 풀이(또는 `KCA_Q018_FILE`) 판정 |
| `./reset.sh` | 실습 외 리소스 있으면 중단, 없으면 라벨 정책·Pod 삭제 후 빈 Namespace |
| `./teardown.sh` | 소유 표식 일치 클러스터와 전용 kubeconfig만 삭제 |

## 단계

| 단계 | 파일 | 결과 | 전후 비교 | 슬라이드 |
|---|---|---|---|---|
| 0 | 01 (정책 없음) | `pod/no-app created`, Ready, 삭제 | Enforce 적용 전 | S04 |
| 1 | 02 Enforce → 01 | `was blocked`, `NotFound`, polr 없음 | Enforce 적용 후 (0 ↔ 1) | S04·S06·S09 |
| 2 | 03 Audit → 01 | `configured`, `pod/no-app created` | Audit 적용 후 (1 ↔ 2) | S08 |
| 3 | 이벤트 조회 | `PolicyViolation pod/no-app` | - | S10 |
| 4 | `kubectl get polr` | no-app FAIL 1 | 보고서 (1 ↔ 4) | S09 |
| 5 | 04 옛 필드 `spec.validationFailureAction: Enforce` → 01 | ClusterPolicy 공통 경고 1줄, `was blocked` | 옛 필드 적용 후 (2 ↔ 5) | S11 |
| 과제 | `exams/items/KCA-D1-018.solution.yaml` + 05 | with-app: `kca03-require-app app-label pass`, `kca03-require-team team-label fail` | - | - |

## 파일

| 파일 | 내용 |
|---|---|
| `00-namespace.yaml` | Namespace `kca03` |
| `01-pod-no-app.yaml` | app 라벨 없는 Pod `no-app`(전후 공통 파일) |
| `02-cpol-enforce.yaml` | `kca03-require-app`, 규칙 `app-label`, `failureAction: Enforce` |
| `03-cpol-audit.yaml` | 02와 `failureAction: Audit` 한 줄만 다름 |
| `04-cpol-legacy-field.yaml` | 옛 필드 `spec.validationFailureAction: Enforce`, 규칙 failureAction 없음 |
| `05-pod-app.yaml` | app 라벨만 있는 Pod `with-app`(과제) |

## 과제 판정

| 실행 | 결과 |
|---|---|
| `./verify.sh` | 학습자 패키지에는 풀이 `KCA-D1-018.solution.yaml`이 없음 → `SKIP: 문항 풀이 파일 없음`, 과제 외 단계만 판정 |
| `KCA_Q018_FILE=my-require-team.yaml ./verify.sh` | 가이드 과제 조건대로 쓴 내 답안으로 과제까지 판정, 경로는 실습 폴더 기준 또는 절대 경로 |
| 지정한 파일이 없음 | `FAIL: KCA_Q018_FILE 없음` |

## 알려진 문제

| 항목 | 처리 |
|---|---|
| Kyverno v1.20 이상 | 레거시 정책 미실행, setup이 v1.19.2 고정·확인 |
| inotify `max_user_instances` < 512 | setup이 중단하고 OS별 해결 명령 출력(`KCA_SKIP_INOTIFY=1`로 무시) |
| 다른 kind 클러스터 실행 중 | 경고만, 건드리지 않음 |
| webhook 준비 지연 | 서버 dry-run 성공까지 최대 120초 대기 |
| PolicyReport 지연 | 비동기 생성, verify는 최대 60초 재조회 |
| 같은 이름 클러스터(소유 표식 불일치) | setup·teardown 중단 |

## 가이드 생성

| 항목 | 경로 |
|---|---|
| 단계 정의 | `../_tools/KCA_03_steps.json` |
| 출력 수집 | `../_tools/guide_walk.py KCA_03 legacy` |
| HTML 생성 | `../_tools/KCA_03_guide_build.py` (골격 `templates/lab/guide_shell.py`) |
| UI 테스트 | `../_tools/guide_ui_test.mjs` (`LESSON=KCA_03 PORT=9343`) |
