#!/usr/bin/env bash
# usage: ./verify.sh
# 실습 리소스를 초기화(reset)한 뒤 가이드 전 단계(0~10)를 자동 실행하고 단계별 PASS/FAIL 판정
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
expect() { printf '%s' "$out" | grep -qE "$1" && ok "$1" || ng "$1"; }
reject() { printf '%s' "$out" | grep -qE "$1" && ng "없어야 함: $1" || ok "없음: $1"; }
rc_is()  { [ "$rc" "$1" 0 ] && ok "exit $rc" || ng "exit $rc"; }
# poll <한 줄 정규식> <명령>: 30초 안에 출력 한 줄이 정규식과 일치할 때까지 재시도
poll() { for _ in $(seq 1 15); do out="$(eval "$2" 2>&1)"; rc=$?; [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -qxE "$1" && break; sleep 2; done
         echo "\$ $2"; echo "$out"; rc_is -eq; expect "^$1\$"; }
# FailedCreate 이벤트: 대상 객체 이름 기준
obj() { kubectl -n kca23 get rs -l app="$2" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null; }
ev() { n="$(obj "$1" "$2")"; [ -n "$n" ] || return 0
  kubectl -n kca23 get events --field-selector "reason=FailedCreate,involvedObject.name=$n" \
    -o jsonpath='{.items[0].involvedObject.kind}/{.items[0].involvedObject.name} | {.items[0].source.component} | {.items[0].message}' 2>/dev/null | tr -s '\n' ' '; }
pollev() { for _ in $(seq 1 15); do out="$(ev "$1" "$2")"; [ -n "$out" ] && break; sleep 2; done; echo "\$ events FailedCreate $2"; echo "$out"; }
RULES="{range .status.autogen.rules[*]}{.name}{\"  \"}{.match.any[0].resources.kinds}{\"\\n\"}{end}"

# 0: 적용 전 기준선(정책 없음): 이후 단계와 같은 파일 02·08·07이 그대로 만들어짐
step 0 "kubectl apply -f 02-deploy-latest.yaml && kubectl -n kca23 rollout status deploy/web-latest --timeout=180s"
rc_is -eq; expect 'web-latest created'; expect 'successfully rolled out'
step 0b "kubectl -n kca23 get deploy web-latest"
expect '^web-latest +1/1 '
step 0d "kubectl apply -f 08-pod-latest.yaml && kubectl -n kca23 wait --for=condition=Ready pod/bare-latest --timeout=120s"
rc_is -eq; expect 'pod/bare-latest created'; expect 'condition met'
step 0e "kubectl apply -f 07-deploy-ns.yaml"
rc_is -eq; expect 'deployment.apps/web-ns created'
step 0c "kubectl delete -f 02-deploy-latest.yaml -f 08-pod-latest.yaml -f 07-deploy-ns.yaml --cascade=foreground --wait=true"
rc_is -eq; expect 'deleted'
step 1 "kubectl apply -f 01-cpol-disallow-latest.yaml && kubectl wait --for=condition=Ready clusterpolicy/kca23-disallow-latest --timeout=60s"
rc_is -eq; expect 'condition met'
step 1b "kubectl apply -f 08-pod-latest.yaml"
rc_is -ne; expect 'resource Pod/kca23/bare-latest was blocked'; expect 'rule image-tag failed at path /spec/containers/0/image/'
step 2 "kubectl get clusterpolicy kca23-disallow-latest -o jsonpath='$RULES'"
expect 'autogen-image-tag  \["apps/v1/DaemonSet","apps/v1/Deployment","batch/v1/Job","apps/v1/ReplicaSet","v1/ReplicationController","apps/v1/StatefulSet"\]'
expect 'autogen-cronjob-image-tag  \["batch/v1/CronJob"\]'
step 3 "kubectl apply -f 02-deploy-latest.yaml"
rc_is -ne; expect 'autogen-image-tag'; expect '/spec/template/spec/containers/0/image/'
step 4 "kubectl apply -f 03-deploy-pinned.yaml"
rc_is -eq; expect 'deployment.apps/web-pinned created'
step 5 "kubectl apply -f 04-cpol-autogen-none.yaml"
rc_is -eq; expect 'configured'
poll '\{\}' "kubectl get clusterpolicy kca23-disallow-latest -o jsonpath='{.status.autogen}'"
step 6 "kubectl apply -f 02-deploy-latest.yaml"
rc_is -eq; expect 'web-latest created'
pollev rs web-latest
expect '^ReplicaSet/web-latest-[a-z0-9]+ \| replicaset-controller \|'; expect 'rule image-tag failed at path /spec/containers/0/image/'
step 7 "kubectl -n kca23 get deploy web-latest"
expect '^web-latest +0/1 '
step 8 "kubectl apply -f 05-cpol-selector.yaml"
rc_is -eq
sleep 5
poll '\{\}' "kubectl get clusterpolicy kca23-selector -o jsonpath='{.status.autogen}'"
step 8b "kubectl get clusterpolicy kca23-selector -o jsonpath='$RULES'"
[ -z "$(printf '%s\n' "$out" | grep -v -e '^Warning:' -e '^$')" ] && ok "selector 자동 규칙 0개" || ng "selector 자동 규칙 있음"
step 9 "kubectl apply -f 06-cpol-namespace.yaml"
rc_is -eq
step 9a "kubectl get clusterpolicy kca23-no-default-ns -o jsonpath='{.spec.rules[0].validate.pattern}'"
expect '^\{"metadata":\{"namespace":"!default"\}\}$'
poll '\{"spec":\{"template":\{"metadata":\{"namespace":"!default"\}\}\}\}' "kubectl get clusterpolicy kca23-no-default-ns -o jsonpath='{.status.autogen.rules[0].validate.pattern}'"
step 10 "kubectl apply -f 07-deploy-ns.yaml"
rc_is -ne; expect 'autogen-no-default'; expect '/spec/template/metadata/namespace/'
# 실습형 문항 KCA-D5-009: 학습자 답안(KCA_Q009_FILE) 또는 풀이 파일 판정
SOL="${KCA_Q009_FILE:-../../exams/items/KCA-D5-009.solution.yaml}"
if [ -f "$SOL" ]; then
  step Q009 "kubectl apply -f \"\$SOL\""
  rc_is -eq
  poll 'autogen-image-tag  \["apps/v1/Deployment"\]' "kubectl get clusterpolicy kca23-deploy-only -o jsonpath='$RULES'"
  n="$(printf '%s\n' "$out" | grep -v -e '^Warning:' -e '^$' | grep -c .)"
  [ "$n" -eq 1 ] && ok "규칙 1개(Deployment만)" || ng "규칙 $n개, 기대 1개"
  step Q009b "kubectl get clusterpolicy kca23-deploy-only -o jsonpath='{.spec.rules[0].validate.failureAction} {.spec.rules[0].match.any[0].resources.namespaces[0]} {.spec.rules[0].validate.pattern.spec.containers[0].image} {.spec.background} {.metadata.labels.lecture\\.kca/lab}{\"\\n\"}'"
  expect '^Enforce kca23 !\*:latest false kca23$'
elif [ -n "${KCA_Q009_FILE:-}" ]; then
  ng "KCA_Q009_FILE 없음: $KCA_Q009_FILE"
else
  echo; echo "SKIP: 문항 풀이 파일 없음(학습자 패키지), KCA-D5-009 판정 생략"
fi
echo; echo "RESULT pass=$pass fail=$fail"
echo "실습 리소스는 남겨 둠. 초기화: ./reset.sh"
[ "$fail" -eq 0 ]
