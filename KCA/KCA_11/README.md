# KCA 11 실습 match · exclude

| 항목 | 값 |
|---|---|
| 학습자 가이드 | `guide.html` (단일 파일, 외부 리소스 없음, 목차·한 화면 한 단계·복사 버튼·기대 출력·막힐 때·진행 체크) |
| 기준 | Kyverno v1.19.2 (chart 3.9.2) 단일, v1.20 이상은 ClusterPolicy 미실행 |
| 클러스터 | kind `kca11` |
| kubeconfig | `~/.kca-lab/kca11.kubeconfig` (`KCA_LAB_HOME`로 변경) |
| 격리 | `~/.kube/config`·현재 context·helm repo 설정 미변경, 소유 표식 `kube-system/kca-lab-owner` + 로컬 id |
| 사용자 전환 | `--as=system:serviceaccount:kca11:deployer`, 실습 클러스터 안 실습 ServiceAccount만(`01-rbac.yaml`) |
| 지원 | macOS(bash 3.2)·Linux, Docker 4GiB 이상 |
| 검증 | `qa/KCA_11_qa.md` |
| 슬라이드 | S04·S06·S07·S11·S12 (전후 장), S13 (실패 데모) |

## 명령

| 명령 | 내용 |
|---|---|
| `./setup.sh` | 도구·버전 점검 → inotify 점검 → kind 생성 또는 재사용(소유 확인) → Kyverno v1.19.2 설치·이미지 태그 확인 → 정책 webhook 대기 → Namespace `kca11`(라벨 `env: prod`) |
| `source ./env.sh` | 현재 셸 KUBECONFIG 지정, 실습 폴더로 이동, 소유 확인 실패 시 환경 미변경 |
| `./verify.sh` | reset 후 0~9단계 자동 실행·판정, 문항 KCA-D4-017 풀이(또는 `KCA_Q017_FILE`) 판정 |
| `./reset.sh` | 실습 외 리소스 있으면 중단, 없으면 라벨 정책 삭제·Namespace 삭제 후 빈 Namespace |
| `./teardown.sh` | 소유 표식 일치 클러스터와 전용 kubeconfig만 삭제 |

## 단계

| 단계 | 파일 | 결과 | 전후 비교 | 슬라이드 |
|---|---|---|---|---|
| 0 | 02·03 각각 (정책 없음) | web·db created, 삭제 | 적용 전 | S04 |
| 1 | 01 RBAC | deployer `can-i create pods` yes | - | S12 |
| 2 | 11 `match.any` → 02·03 | web·db 거부 | 적용 후 (0 ↔ 2) | S04 |
| 3 | 12 `match.all` → 02·03 | web 거부, db created | 적용 후 (2 ↔ 3) | S06 |
| 4 | Namespace 라벨 `env` 제거 → 02 | web created, 라벨 복구·삭제 | 적용 후 (3 ↔ 4) | S07 |
| 5 | 04 (12 유지) | web-exempt 거부 | 적용 전 | S11 |
| 6 | 13 exclude selector → 04 | web-exempt created | 적용 후 (5 ↔ 6) | S11 |
| 7 | 02 `--as` deployer (13 유지) | 거부 | 적용 전 | S12 |
| 8 | 14 exclude subjects → 02 관리자 / deployer | 관리자 거부, deployer created | 적용 후 (7 ↔ 8) | S12 |
| 9 | 15 subjects + `background: true` | 정책 생성 거부 | - | S13 |
| 과제 | `exams/items/KCA-D4-017.solution.yaml` → 02·03·04·05 | web·db 거부, web-exempt·cache created | - | - |

## 알려진 문제

| 항목 | 처리 |
|---|---|
| Kyverno v1.20 이상 | 레거시 정책 미실행, setup이 v1.19.2 고정·확인 |
| inotify `max_user_instances` < 512 | setup이 중단하고 OS별 해결 명령 출력(`KCA_SKIP_INOTIFY=1`로 무시) |
| 다른 kind 클러스터 실행 중 | 경고만, 건드리지 않음 |
| webhook 준비 지연 | 서버 dry-run 성공까지 최대 120초 대기 |
| 정책·Namespace 라벨 반영 지연 | verify는 서버 dry-run으로 반영 확인 후 판정(최대 30초), 가이드는 막힐 때 몇 초 뒤 재실행 |
| 같은 이름 클러스터(소유 표식 불일치) | setup·teardown 중단 |

## 가이드 생성

| 항목 | 경로 |
|---|---|
| 단계 정의 | `../_tools/KCA_11_steps.json` |
| 출력 수집 | `../_tools/guide_walk.py KCA_11 legacy` |
| HTML 생성 | `../_tools/KCA_11_guide_build.py` (골격 `templates/lab/guide_shell.py`) |
| UI 테스트 | `../_tools/guide_ui_test.mjs` (`LESSON=KCA_11`) |
