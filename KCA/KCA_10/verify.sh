#!/usr/bin/env bash
# usage: ./verify.sh
# 실습 리소스를 초기화(reset)한 뒤 가이드 전 단계(0~7)를 자동 실행하고 단계별 PASS/FAIL 판정
set -uo pipefail
. "$(dirname "$0")/lib.sh"
mode_init "${1:-}"
( require_owned_cluster ) || exit 1
ensure_kubeconfig
owned || { echo "STOP: $(owner_hint)"; exit 1; }
export KUBECONFIG="$KCFG"
[ "$(kubectl config current-context)" = "$CTX" ] || { echo "STOP: 전용 kubeconfig context 불일치"; exit 1; }
cd "$LAB_DIR"
echo "초기화: 실습 리소스 삭제 후 빈 Namespace 2개"
( lab_reset ) || { echo "STOP: reset 실패"; exit 1; }

pass=0; fail=0
ok()  { echo "PASS: $1"; pass=$((pass+1)); }
ng()  { echo "FAIL: $1"; fail=$((fail+1)); }
step() { echo; echo "## $1"; echo "\$ $2"; out="$(eval "$2" 2>&1)"; rc=$?; echo "$out"; }
expect() { printf '%s' "$out" | grep -qE -- "$1" && ok "$1" || ng "$1"; }
reject() { printf '%s' "$out" | grep -qE -- "$1" && ng "없어야 함: $1" || ok "없음: $1"; }
rc_is()  { [ "$rc" "$1" 0 ] && ok "exit $rc" || ng "exit $rc"; }
DENY='admission webhook "validate.kyverno.svc-fail" denied the request'

# 0: 적용 전(정책 없음): 같은 Pod 파일 01·02가 두 Namespace에서 생성됨
step 0 "kubectl apply -f 01-pod-blue.yaml && kubectl apply -f 02-pod-green.yaml"
rc_is -eq; expect '^pod/no-team created'; [ "$(printf '%s\n' "$out" | grep -c '^pod/no-team created')" -eq 2 ] && ok "2개 생성" || ng "2개 생성 아님"
step 0b "kubectl delete -f 01-pod-blue.yaml -f 02-pod-green.yaml --wait=true"
rc_is -eq; expect 'deleted'
# 1: Policy 생성 직후 상태 → wait → Ready
step 1 "kubectl apply -f 03-pol-require-team.yaml && kubectl -n kca10-blue get pol require-team"
rc_is -eq; expect 'policy.kyverno.io/require-team created'; expect '^NAME +ADMISSION +BACKGROUND +READY +AGE +MESSAGE'
step 1b "kubectl -n kca10-blue wait --for=condition=Ready pol/require-team --timeout=60s && kubectl -n kca10-blue get pol require-team"
rc_is -eq; expect 'policy.kyverno.io/require-team condition met'; expect '^require-team +true +false +True +[0-9a-z]+ +Ready$'
step 1c "kubectl -n kca10-blue get pol require-team -o jsonpath='{range .status.conditions[*]}{.type}={.status} {.reason} {.message}{\"\\n\"}{end}'"
expect '^Ready=True Succeeded Ready$'
# 2: 범위 조회
step 2 "kubectl get pol -A && kubectl get cpol"
expect '^NAMESPACE +NAME +ADMISSION'; expect '^kca10-blue +require-team +true +false +True'; expect 'No resources found'
# 3: Policy 적용 후: blue 거부, green 생성
step 3 "kubectl apply -f 01-pod-blue.yaml"
rc_is -ne; expect "$DENY"; expect 'resource Pod/kca10-blue/no-team was blocked'; expect '^require-team:$'
step 3b "kubectl apply -f 02-pod-green.yaml"
rc_is -eq; expect '^pod/no-team created'
# 4: 잘못된 ClusterPolicy(failureAction: Deny)는 저장 안 됨 → 같은 규칙 Enforce는 Ready
step 4 "kubectl delete -f 02-pod-green.yaml --wait=true"
rc_is -eq; expect 'deleted'
step 4a "kubectl apply -f 08-cpol-invalid.yaml"
rc_is -ne; expect 'spec.rules\[0\].validate.failureAction: Unsupported value: "Deny": supported values: "Audit", "Enforce"'
step 4b "kubectl wait --for=condition=Ready cpol/kca10-require-team --timeout=60s"
rc_is -ne; expect 'Error from server \(NotFound\): clusterpolicies.kyverno.io "kca10-require-team" not found'
step 4c "kubectl apply -f 04-cpol-require-team.yaml && kubectl wait --for=condition=Ready cpol/kca10-require-team --timeout=60s && kubectl get cpol"
rc_is -eq; expect 'clusterpolicy.kyverno.io/kca10-require-team created'; expect 'condition met'; expect '^kca10-require-team +true +false +True'
# 5: ClusterPolicy 적용 후: green도 거부, blue는 두 정책 모두 위반, team 라벨 Pod는 생성
step 5 "kubectl apply -f 02-pod-green.yaml"
rc_is -ne; expect 'resource Pod/kca10-green/no-team was blocked'; expect '^kca10-require-team:$'; reject '^require-team:$'
step 5b "kubectl apply -f 01-pod-blue.yaml"
rc_is -ne; expect 'resource Pod/kca10-blue/no-team was blocked'; expect '^kca10-require-team:$'; expect '^require-team:$'
step 5c "kubectl apply -f 07-pod-green-team.yaml"
rc_is -eq; expect 'pod/with-team created'
# 6: Policy는 namespaces·클러스터 범위 kind를 쓸 수 없음
step 6 "kubectl apply -f 05-pol-other-ns.yaml"
rc_is -ne; expect 'Filtering namespaces not allowed in namespaced policies'
step 6b "kubectl -n kca10-blue get pol require-team-green"
rc_is -ne; expect 'NotFound'
step 6c "kubectl apply -f 06-pol-namespace-kind.yaml"
rc_is -ne; expect "Cluster wide resource 'Namespace' not allowed in namespaced policy"
# 7: 결과
step 7 "kubectl get pod -A -l lecture.kca/lab=kca10 && kubectl get cpol,pol -A"
expect '^kca10-green +with-team '; reject 'no-team'
expect '^clusterpolicy.kyverno.io/kca10-require-team +true +false +True'; expect '^kca10-blue +policy.kyverno.io/require-team +true +false +True'
# 실습형 문항 KCA-D4-007: 학습자 답안(KCA_Q007_FILE) 또는 풀이 파일 판정
SOL="${KCA_Q007_FILE:-../../exams/items/KCA-D4-007.solution.yaml}"
if [ -f "$SOL" ]; then
  step Q007 "kubectl delete -f 04-cpol-require-team.yaml -f 07-pod-green-team.yaml --wait=true && kubectl apply -f \"\$SOL\" && kubectl -n kca10-green wait --for=condition=Ready pol/green-team --timeout=60s"
  rc_is -eq; expect 'condition met'
  step Q007b "kubectl apply -f 02-pod-green.yaml"
  rc_is -ne; expect 'resource Pod/kca10-green/no-team was blocked'; expect 'green-team:'
  step Q007c "kubectl -n kca10-green get pol green-team -o jsonpath='{.spec.rules[0].validate.failureAction} {.spec.background} {.metadata.labels.lecture\\.kca/lab}{\"\\n\"}'"
  expect '^Enforce false kca10$'
  step Q007d "kubectl -n kca10-green get pol green-team -o jsonpath='{.spec.rules[0].name} {.spec.rules[0].validate.pattern} {.spec.rules[0].match.any[0].resources.namespaces}{\"\\n\"}'"
  expect '^team-label \{"metadata":\{"labels":\{"team":"\?\*"\}\}\} $'
  step Q007f "kubectl -n kca10-green get pol green-team -o jsonpath='{.spec.rules[0].match}{\"\\n\"}'"
  expect '^\{"any":\[\{"resources":\{"kinds":\["Pod"\]\}\}\]\}$'
  step Q007e "kubectl apply -f 07-pod-green-team.yaml"
  rc_is -eq; expect 'pod/with-team created'
elif [ -n "${KCA_Q007_FILE:-}" ]; then
  ng "KCA_Q007_FILE 없음: $KCA_Q007_FILE"
else
  echo; echo "SKIP: 문항 풀이 파일 없음(학습자 패키지), KCA-D4-007 판정 생략"
fi
echo; echo "RESULT pass=$pass fail=$fail"
echo "실습 리소스는 남겨 둠. 초기화: ./reset.sh"
[ "$fail" -eq 0 ]
