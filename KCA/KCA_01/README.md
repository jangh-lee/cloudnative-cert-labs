# KCA 01 실습 kind 실습 환경

| 항목 | 값 |
|---|---|
| 학습자 가이드 | `guide.html` (단일 파일, 외부 리소스 없음, 목차·한 화면 한 단계·복사 버튼·기대 출력·막힐 때·진행 체크) |
| 기준 | Kyverno v1.19.2 (chart 3.9.2) 단일, setup.sh 인자로 다른 버전 요청 시 거부, v1.20 이상은 ClusterPolicy 미실행 |
| 클러스터 | kind `kca01` |
| kubeconfig | `~/.kca-lab/kca01.kubeconfig` (`KCA_LAB_HOME`로 변경, 상대 경로는 실행 위치 기준 절대 경로로 변환) |
| 격리 | `~/.kube/config`·현재 context·helm repo 설정 미변경, 소유 표식 `kube-system/kca-lab-owner` + 로컬 id `~/.kca-lab/kca01.id` |
| 지원 | macOS(bash 3.2)·Linux, Docker 4GiB 이상 |
| kubectl | v1.35.x 실습용 `~/.kca-lab/bin/kubectl` (node v1.35.8, 지원 1.34~1.36), 순서 `KCA_KUBECTL` → `~/.kca-lab/bin/kubectl` → PATH, 시스템 kubectl 미변경 |
| 공통 | 이후 회차도 같은 스크립트 5개 + `lib.sh`, 클러스터 이름만 `kca<NN>` |
| 검증 | `qa/KCA_01_qa.md` |
| 슬라이드 | 기준 덱 `revised/KCA_01` 23장: S09~S11·S19 (전후 장), S06·S20 (버전·Helm), 8·10·11단계(webhook·정책 거부)는 대응 장 없음 |

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
| `./setup.sh` | 인자 거부(버전 고정) → 도구·버전 점검 → inotify 점검 → kind 생성 또는 재사용(소유 확인) → chart 3.9.2 appVersion 확인 → `--repo`로 Kyverno 설치 → Deployment 이미지 태그 전부 v1.19.2 확인 → 정책 webhook 대기(서버 dry-run, 3초 간격 최대 40회) → Namespace `kca01` |
| `source ./env.sh` | 현재 셸 KUBECONFIG·실습용 kubectl(PATH 앞) 지정, 실습 폴더로 이동, 소유 확인 실패 시 환경 미변경 |
| `./verify.sh` | reset 후 6~15단계·과제 KCA-D2-007 자동 실행·판정 |
| `./reset.sh` | Namespace `kca01`에 실습 외 리소스 있으면 아무것도 지우지 않고 중단, 없으면 실습 라벨 ClusterPolicy 삭제 후 `kca01`을 지우고 빈 Namespace로 다시 만듦 |
| `./teardown.sh` | 소유 표식 일치 클러스터와 전용 kubeconfig만 삭제 |

## 단계

| 단계 | 명령·파일 | 결과 | 전후 비교 | 슬라이드 |
|---|---|---|---|---|
| 1 | `kind get clusters \| grep -x kca01` | 출력 없음 | setup 적용 전 | S09 |
| 2~3 | `./setup.sh` 2회 | `kca01` 생성, 재실행 시 재사용 | setup 적용 후 (1 ↔ 2) | S10 |
| 4 | `echo "KUBECONFIG=${KUBECONFIG:-unset}"` | `KUBECONFIG=unset` | env.sh 적용 전 | S11 |
| 5 | `source ./env.sh` | 전용 kubeconfig, `kind-kca01`, `~/.kube/config`에 kca01 없음 | env.sh 적용 후 (4 ↔ 5) | S11 |
| 6 | `helm list -n kyverno` | `kyverno-3.9.2` · `v1.19.2` | - | S20 |
| 7 | `kubectl -n kyverno get deploy` | 컨트롤러 4개 1/1, 이미지 v1.19.2 | - | S06 |
| 8 | webhook 실패 정책 조회 → 01 서버 dry-run | `Fail ["CREATE","UPDATE"]`, `created (server dry run)` | - | - |
| 9 | `./setup.sh 1.20.0` | `버전 고정 ... 거부` | - | S06 |
| 10 | 02 (정책 없음) | `pod/web-no-team created` | 정책 적용 전 | - |
| 11 | 01 → 02 → 03 | 02 거부, 03 생성 | 정책 적용 후 (10 ↔ 11) | - |
| 12 | 소유 표식 조회 | `kca01/kca01/<id>` = 로컬 id | - | S09 |
| 13 | `H="$(mktemp -d "${TMPDIR:-/tmp}/kca01-home.XXXXXX")" && KCA_LAB_HOME="$H" ./teardown.sh` | 소유 확인 실패, kca01 유지, `$H`만 삭제(H가 비면 첫 줄부터 다시) | - | S19 |
| 14 | 실습 라벨 리소스 조회 | 정책 1·Pod 1 | reset 적용 전 | S19 |
| 15 | `./reset.sh` | `No resources found`, Kyverno 유지 | reset 적용 후 (14 ↔ 15) | S19 |
| 과제 | KCA-D2-007 검증 명령 3개 | `kyverno-3.9.2`·`v1.19.2`·`kind-kca01` | - | S20 |
| 16 | `./teardown.sh` 2회 | `kca01` 삭제, 재실행 시 `클러스터 kca01 없음` | teardown 적용 후 | S19 |

## 알려진 문제

| 항목 | 처리 |
|---|---|
| Kyverno v1.20 이상 | 레거시 정책 미실행, setup이 인자 거부·chart appVersion·이미지 태그로 v1.19.2 고정 |
| inotify `max_user_instances` < 512 | setup이 중단하고 OS별 해결 명령 출력(`KCA_SKIP_INOTIFY=1`로 무시) |
| 다른 kind 클러스터 실행 중 | 경고만, 건드리지 않음 |
| webhook 준비 지연 | 서버 dry-run 성공까지 3초 간격 최대 40회 재시도 |
| 같은 이름 클러스터(소유 표식 불일치) | setup·reset·teardown 중단 |
| setup 재실행 | `helm upgrade --install`이 REVISION을 1 올림, 버전·values 동일 |

## 가이드 생성

| 항목 | 경로 |
|---|---|
| 단계 정의 | `../_tools/KCA_01_steps.json` (6~15단계·과제) |
| 출력 수집 | `../_tools/guide_walk.py KCA_01 legacy`, 1~5·16단계는 `qa/KCA_01_L3_run.log` |
| HTML 생성 | `../_tools/KCA_01_guide_build.py` (골격 `templates/lab/guide_shell.py`) |
| UI 테스트 | `../_tools/guide_ui_test.mjs` (`LESSON=KCA_01 PORT=9341`) |
