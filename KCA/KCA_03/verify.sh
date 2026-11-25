#!/usr/bin/env bash
# usage: ./verify.sh
# 실습 리소스를 초기화(reset)한 뒤 가이드 전 단계(0~5)를 자동 실행하고 단계별 PASS/FAIL 판정
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
# poll <정규식> <명령>: 60초 안에 출력이 정규식과 일치할 때까지 재시도
poll() { for _ in $(seq 1 30); do out="$(eval "$2" 2>&1)"; rc=$?; [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -qE -- "$1" && break; sleep 2; done
         echo "\$ $2"; echo "$out"; rc_is -eq; expect "$1"; }
POLR="kubectl -n kca03 get polr"
RES="kubectl -n kca03 get polr -o jsonpath='{range .items[*].results[*]}{.policy} {.rule} {.result}{\"\\n\"}{end}'"

# 0: 적용 전(정책 없음): 같은 01 Pod 생성
step 0 "kubectl apply -f 01-pod-no-app.yaml && kubectl -n kca03 wait --for=condition=Ready pod/no-app --timeout=120s"
rc_is -eq; expect 'pod/no-app created'; expect 'condition met'
step 0b "kubectl delete -f 01-pod-no-app.yaml --wait=true"
rc_is -eq; expect 'pod "no-app" deleted'
# 1: Enforce → 같은 Pod 거부, 저장 안 됨, 보고서 없음
step 1 "kubectl apply -f 02-cpol-enforce.yaml && kubectl wait --for=condition=Ready clusterpolicy/kca03-require-app --timeout=60s"
rc_is -eq; expect 'condition met'
step 1b "kubectl apply -f 01-pod-no-app.yaml"
rc_is -ne; expect 'resource Pod/kca03/no-app was blocked due to the following policies'; expect '^kca03-require-app:'; expect 'app-label:'; expect 'app 라벨 필요'
step 1c "kubectl -n kca03 get pod no-app"
rc_is -ne; expect 'NotFound|not found'
step 1d "sleep 15; $POLR"
expect 'No resources found'
# 2: Audit → 같은 Pod 생성
step 2 "kubectl apply -f 03-cpol-audit.yaml && kubectl wait --for=condition=Ready clusterpolicy/kca03-require-app --timeout=60s"
rc_is -eq; expect 'configured'; expect 'condition met'
step 2b "kubectl apply -f 01-pod-no-app.yaml"
rc_is -eq; expect 'pod/no-app created'; reject 'blocked'
# 3: Audit 위반 이벤트
echo; echo "## 3"
poll 'PolicyViolation' "kubectl -n kca03 get events --field-selector reason=PolicyViolation"
expect 'pod/no-app'
# 4: polr FAIL 1
echo; echo "## 4"
poll ' 0 +1 +0 +0 +0 ' "$POLR"
poll 'kca03-require-app app-label fail' "$RES"
# 5: 옛 필드 spec.validationFailureAction: Enforce → 같은 Pod 거부
step 5 "kubectl delete -f 01-pod-no-app.yaml --wait=true && kubectl apply -f 04-cpol-legacy-field.yaml && kubectl wait --for=condition=Ready clusterpolicy/kca03-require-app --timeout=60s"
rc_is -eq; expect 'configured'
step 5b "kubectl apply -f 01-pod-no-app.yaml"
rc_is -ne; expect 'resource Pod/kca03/no-app was blocked'
# 실습형 문항 KCA-D1-018: 학습자 답안(KCA_Q018_FILE) 또는 풀이 파일 판정
SOL="${KCA_Q018_FILE:-../../exams/items/KCA-D1-018.solution.yaml}"
WRES="kubectl -n kca03 get polr -o jsonpath='{range .items[?(@.scope.name==\"with-app\")].results[*]}{.policy} {.rule} {.result}{\"\\n\"}{end}'"
if [ -f "$SOL" ]; then
  echo; echo "## Q018a 답안 파일 검사"
  grep -q 'validationFailureAction' "$SOL" && ng "옛 필드 spec.validationFailureAction 사용" || ok "옛 필드 없음"
  step Q018 "kubectl apply -f \"\$SOL\" && kubectl wait --for=condition=Ready clusterpolicy/kca03-require-team --timeout=60s && kubectl apply -f 05-pod-app.yaml"
  rc_is -eq; expect 'pod/with-app created'
  step Q018b "kubectl get clusterpolicy kca03-require-team -o jsonpath='{.spec.rules[0].validate.failureAction} {.spec.rules[0].validate.pattern.metadata.labels.team} {.metadata.labels.lecture\\.kca/lab}{\"\\n\"}'"
  expect '^Audit \?\* kca03$'
  echo; echo "## Q018c"
  poll 'kca03-require-team team-label fail' "$WRES"
  expect 'kca03-require-app app-label pass'
elif [ -n "${KCA_Q018_FILE:-}" ]; then
  ng "KCA_Q018_FILE 없음: $KCA_Q018_FILE"
else
  echo; echo "SKIP: 문항 풀이 파일 없음(학습자 패키지), KCA-D1-018 판정 생략"
fi
echo; echo "RESULT pass=$pass fail=$fail"
echo "실습 리소스는 남겨 둠. 초기화: ./reset.sh"
[ "$fail" -eq 0 ]
