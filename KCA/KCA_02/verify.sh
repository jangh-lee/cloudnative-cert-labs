#!/usr/bin/env bash
# usage: ./verify.sh
# 실습 리소스를 초기화(reset)한 뒤 가이드 전 단계(0~9)를 자동 실행하고 단계별 PASS/FAIL 판정
set -uo pipefail
. "$(dirname "$0")/lib.sh"
mode_init "${1:-}"
( require_owned_cluster ) || exit 1
ensure_kubeconfig
owned || { echo "STOP: $(owner_hint)"; exit 1; }
export KUBECONFIG="$KCFG"
[ "$(kubectl config current-context)" = "$CTX" ] || { echo "STOP: 전용 kubeconfig context 불일치"; exit 1; }
cd "$LAB_DIR"
echo "초기화: 실습 리소스 삭제 후 빈 Namespace"
( lab_reset ) || { echo "STOP: reset 실패"; exit 1; }

pass=0; fail=0
ok()  { echo "PASS: $1"; pass=$((pass+1)); }
ng()  { echo "FAIL: $1"; fail=$((fail+1)); }
step() { echo; echo "## $1"; echo "\$ $2"; out="$(eval "$2" 2>&1)"; rc=$?; echo "$out"; }
expect() { printf '%s' "$out" | grep -qE -- "$1" && ok "$1" || ng "$1"; }
reject() { printf '%s' "$out" | grep -qE -- "$1" && ng "없어야 함: $1" || ok "없음: $1"; }
rc_is()  { [ "$rc" "$1" 0 ] && ok "exit $rc" || ng "exit $rc"; }
# 조회 성공 + 출력 없음일 때만 PASS, 조회 실패(API·권한 오류)는 FAIL
absent() { n="$(kubectl get clusterpolicy "$1" --ignore-not-found -o name 2>/dev/null)"; c=$?
  if [ "$c" -ne 0 ]; then ng "정책 $1 조회 실패(rc=$c): $(kubectl get clusterpolicy "$1" --ignore-not-found -o name 2>&1 | grep -v '^Warning:' | head -1)"; elif [ -z "$n" ]; then ok "정책 $1 없음(생성 거부)"; else ng "정책 $1 생성됨"; fi; }
WH='admission webhook "validate-policy.kyverno.svc" denied the request'

# 0: 적용 전 기준선(정책 없음): 01·02 Pod 생성 후 삭제
step 0 "kubectl apply -f 01-pod-no-app.yaml -f 02-pod-app-only.yaml"
rc_is -eq; expect 'pod/no-app created'; expect 'pod/app-only created'
step 0b "kubectl delete -f 01-pod-no-app.yaml -f 02-pod-app-only.yaml --wait=true"
rc_is -eq; expect 'pod "no-app" deleted'
# 1: validate 규칙 정책 생성·Ready
step 1 "kubectl apply -f 03-cpol-require-app.yaml && kubectl wait --for=condition=Ready clusterpolicy/kca02-require-app --timeout=60s"
rc_is -eq; expect 'clusterpolicy.kyverno.io/kca02-require-app created'; expect 'condition met'
# 2: 같은 Pod 01 거부, 02 허용
step 2 "kubectl apply -f 01-pod-no-app.yaml"
rc_is -ne; expect 'resource Pod/kca02/no-app was blocked'; expect 'rule require-app failed at path /metadata/labels/app/'
step 2b "kubectl apply -f 02-pod-app-only.yaml"
rc_is -eq; expect 'pod/app-only created'
# 3: rule 필드 목록
step 3 "kubectl explain clusterpolicy.spec.rules | grep -E '^  (name|match|exclude|validate|mutate|generate|verifyImages)\b'"
expect 'match.*-required-'; expect 'name.*-required-'; expect '^  validate'; expect '^  mutate'; expect '^  generate'; expect '^  verifyImages'
# 4: rule 유형 0개·2개 → Kyverno webhook 거부
step 4 "kubectl apply -f 04-cpol-no-type.yaml"
rc_is -ne; expect "$WH"; expect "No operation defined in the rule 'require-app'"
absent kca02-no-type
step 4b "kubectl apply -f 05-cpol-two-types.yaml"
rc_is -ne; expect "$WH"; expect "Multiple operations defined in the rule 'require-app'"
absent kca02-two-types
# 5: failureAction 위치 오류 → API 서버 스키마 거부
step 5 "kubectl apply -f 06-cpol-team-bad-position.yaml"
rc_is -ne; expect 'strict decoding error: unknown field "spec.rules\[0\].failureAction"'
absent kca02-require-team
# 6: validate 아래로 옮긴 정책 생성, 02 Pod 다시 제출 → require-team 거부
step 6 "kubectl apply -f 07-cpol-team-fixed.yaml && kubectl wait --for=condition=Ready clusterpolicy/kca02-require-team --timeout=60s"
rc_is -eq; expect 'clusterpolicy.kyverno.io/kca02-require-team created'; expect 'condition met'
step 6b "kubectl delete -f 02-pod-app-only.yaml --wait=true && kubectl apply -f 02-pod-app-only.yaml"
rc_is -ne; expect 'pod "app-only" deleted'; expect 'resource Pod/kca02/app-only was blocked'; expect 'rule require-team failed at path /metadata/labels/team/'
reject 'require-app failed'
# 7: match 없음 → API 서버 스키마 거부
step 7 "kubectl apply -f 08-cpol-no-match.yaml"
rc_is -ne; expect 'The ClusterPolicy "kca02-require-team" is invalid: spec.rules\[0\].match: Required value'
step 7b "kubectl get clusterpolicy kca02-require-team -o jsonpath='{.spec.rules[0].match.any[0].resources.kinds[0]}{\"\\n\"}'"
expect '^Pod$'
# 8: 규칙 이름 중복 → Kyverno webhook 거부
step 8 "kubectl apply -f 09-cpol-dup-name.yaml"
rc_is -ne; expect "$WH"; expect "Duplicate rule name: 'require-label'"
absent kca02-env-tier
# 9: 이름을 나눈 정책 생성, 규칙 이름 조회
step 9 "kubectl apply -f 10-cpol-unique-name.yaml && kubectl get clusterpolicy kca02-env-tier -o jsonpath='{.spec.rules[*].name}{\"\\n\"}'"
rc_is -eq; expect 'clusterpolicy.kyverno.io/kca02-env-tier created'; expect '^require-env require-tier$'
# 실습형 문항 KCA-D1-008 기준선: owner 없는 Pod가 과제 정책 전에는 서버 dry-run 통과
step Q008pre "kubectl apply --dry-run=server -f 11-pod-owner-missing.yaml"
rc_is -eq; expect 'pod/owner-missing created \(server dry run\)'
# 실습형 문항 KCA-D1-008: 학습자 답안(KCA_Q008_FILE) 또는 풀이 파일 판정
SOL="${KCA_Q008_FILE:-../../exams/items/KCA-D1-008.solution.yaml}"
if [ -f "$SOL" ]; then
  step Q008 "kubectl apply -f \"\$SOL\" && kubectl wait --for=condition=Ready clusterpolicy/kca02-require-owner --timeout=60s"
  rc_is -eq; expect 'condition met'
  step Q008b "kubectl get clusterpolicy kca02-require-owner -o jsonpath='{.metadata.labels.lecture\\.kca/lab} {.spec.background} {.spec.rules[0].name} {.spec.rules[0].match.any[0].resources.kinds} {.spec.rules[0].match.any[0].resources.namespaces} {.spec.rules[0].validate.failureAction} {.spec.rules[0].validate.pattern.metadata.labels.owner}{\"\\n\"}'"
  expect '^kca02 false require-owner \["Pod"\] \["kca02"\] Enforce \?\*$'
  step Q008c "kubectl apply --dry-run=server -f 11-pod-owner-missing.yaml"
  rc_is -ne; expect 'resource Pod/kca02/owner-missing was blocked'; expect 'rule require-owner failed at path /metadata/labels/owner/'
  step Q008d "kubectl apply --dry-run=server -f 12-pod-owner.yaml"
  rc_is -eq; expect 'pod/owner-ok created \(server dry run\)'
elif [ -n "${KCA_Q008_FILE:-}" ]; then
  ng "KCA_Q008_FILE 없음: $KCA_Q008_FILE"
else
  echo; echo "SKIP: 문항 풀이 파일 없음(학습자 패키지), KCA-D1-008 판정 생략"
fi
echo; echo "RESULT pass=$pass fail=$fail"
echo "실습 리소스는 남겨 둠. 초기화: ./reset.sh"
[ "$fail" -eq 0 ]
