# KCA 23 실습 Autogen

| 항목 | 값 |
|---|---|
| 학습자 가이드 | `guide.html` (단일 파일, 외부 리소스 없음, 목차·한 화면 한 단계·복사 버튼·기대 출력·막힐 때·진행 체크) |
| 기준 | Kyverno v1.19.2 (chart 3.9.2) 단일, v1.20 이상은 ClusterPolicy 미실행 |
| 클러스터 | kind `kca23` |
| kubeconfig | `~/.kca-lab/kca23.kubeconfig` (`KCA_LAB_HOME`로 변경) |
| 격리 | `~/.kube/config`·현재 context·helm repo 설정 미변경, 소유 표식 `kube-system/kca-lab-owner` + 로컬 id |
| 지원 | macOS(bash 3.2)·Linux, Docker 4GiB 이상 |
| 검증 | `qa/KCA_23_qa.md` |
| 슬라이드 | S04·S06·S09·S11~S13 (전후 장) |

## 명령

| 명령 | 내용 |
|---|---|
| `./setup.sh` | 도구·버전 점검 → inotify 점검 → kind 생성 또는 재사용(소유 확인) → Kyverno v1.19.2 설치·이미지 태그 확인 → 정책 webhook 대기 → Namespace `kca23` |
| `source ./env.sh` | 현재 셸 KUBECONFIG 지정, 실습 폴더로 이동, 소유 확인 실패 시 환경 미변경 |
| `./verify.sh` | reset 후 0~10단계 자동 실행·판정, 문항 KCA-D5-009 풀이(또는 `KCA_Q009_FILE`) 판정 |
| `./reset.sh` | 실습 외 리소스 있으면 중단, 없으면 라벨 정책·워크로드 삭제 후 빈 Namespace |
| `./teardown.sh` | 소유 표식 일치 클러스터와 전용 kubeconfig만 삭제 |

## 단계

| 단계 | 파일 | 결과 | 거부 주체 | 전후 비교 | 슬라이드 |
|---|---|---|---|---|---|
| 0 | 02·08·07 (정책 없음) | 모두 created, web-latest READY 1/1, 삭제 | - | 적용 전 | S04·S06·S13 |
| 1 | 01 ClusterPolicy → 08 latest Pod | Ready, 같은 Pod 거부(`image-tag`) | kubectl apply | 적용 후 (0 ↔ 1) | S04 |
| 2 | 01 status 조회 | 규칙 `autogen-image-tag`(6종)·`autogen-cronjob-image-tag` | - | 주석·selector 적용 전 | S09·S11·S12 |
| 3 | 02 latest Deployment | 거부(`autogen-image-tag`) | kubectl apply | Autogen 적용 후 (3 ↔ 5~7) | S06 |
| 4 | 03 1.27 Deployment | 허용 | - | - | S06 |
| 5~7 | 04 주석 `none` → 02 | `status.autogen {}`, Deployment 생성, READY 0/1 | replicaset-controller | Autogen 적용 전 | S06 |
| 8 | 05 selector | `status.autogen {}` | - | selector 적용 후 (2 ↔ 8) | S12 |
| 9~10 | 06 metadata.namespace → 07 | spec 패턴 → template 경로, 같은 07 거부 | kubectl apply | 적용 후 (0 ↔ 10) | S13 |
| 과제 | `exams/items/KCA-D5-009.solution.yaml` | `autogen-image-tag ["apps/v1/Deployment"]`만 | - | 주석 적용 후 (2 ↔ 과제) | S11 |

## 알려진 문제

| 항목 | 처리 |
|---|---|
| Kyverno v1.20 이상 | 레거시 정책 미실행, setup이 v1.19.2 고정·확인 |
| inotify `max_user_instances` < 512 | setup이 중단하고 OS별 해결 명령 출력(`KCA_SKIP_INOTIFY=1`로 무시) |
| 다른 kind 클러스터 실행 중 | 경고만, 건드리지 않음 |
| webhook 준비 지연 | 서버 dry-run 성공까지 최대 120초 대기 |
| 같은 이름 클러스터(소유 표식 불일치) | setup·teardown 중단 |

## 가이드 생성

| 항목 | 경로 |
|---|---|
| 단계 정의 | `../_tools/KCA_23_steps.json` |
| 출력 수집 | `../_tools/guide_walk.py KCA_23 legacy` |
| HTML 생성 | `../_tools/KCA_23_guide_build.py` (골격 `templates/lab/guide_shell.py`) |
| UI 테스트 | `../_tools/guide_ui_test.mjs` |
