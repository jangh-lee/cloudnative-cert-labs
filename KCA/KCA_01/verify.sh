#!/usr/bin/env bash
# usage: ./verify.sh
# 실습 리소스를 초기화(reset)한 뒤 가이드 단계(버전·webhook·정책·소유 표식·reset·버전 거부·env)를 자동 실행하고 PASS/FAIL 판정
set -uo pipefail
. "$(dirname "$0")/lib.sh"
mode_init "$@"
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
has()    { printf '%s' "$out" | grep -qF -- "$1" && ok "포함: $1" || ng "포함: $1"; }
same()   { [ "$out" = "$1" ] && ok "출력 일치" || ng "출력 불일치, 기대: $(echo $1)"; }
reject() { printf '%s' "$out" | grep -qE "$1" && ng "없어야 함: $1" || ok "없음: $1"; }
rc_is()  { [ "$rc" "$1" 0 ] && ok "exit $rc" || ng "exit $rc"; }
IMGS="{range .items[*]}{.metadata.name}{\"  \"}{.spec.template.spec.containers[0].image}{\"\\n\"}{end}"

# 버전 고정: chart 3.9.2, app v1.19.2, 컨트롤러 4개 이미지
step 1 "helm list -n kyverno"
rc_is -eq; expect '^kyverno[[:space:]]+kyverno[[:space:]]+[0-9]+[[:space:]].*deployed[[:space:]]+kyverno-3\.9\.2[[:space:]]+v1\.19\.2[[:space:]]*$'
step 2 "kubectl -n kyverno get deploy"
for d in admission background cleanup reports; do expect "^kyverno-$d-controller +1/1 "; done
step 2b "kubectl -n kyverno get deploy -o jsonpath='$IMGS'"
for d in $KYVERNO_DEPLOYS; do expect "^$d  [^ ]+:v1\.19\.2\$"; done
[ "$(printf '%s\n' "$out" | grep -c .)" -eq 4 ] && ok "Deployment 4개" || ng "Deployment 수 다름"
# webhook 구성: 정책 검증 webhook이 ClusterPolicy CREATE·UPDATE를 받고 실패 시 Fail → 서버 dry-run 통과 = webhook 응답
step 3 "kubectl get validatingwebhookconfiguration kyverno-policy-validating-webhook-cfg -o jsonpath='{.webhooks[0].failurePolicy} {.webhooks[0].rules[0].operations} {.webhooks[0].rules[0].resources}{\"\\n\"}'"
rc_is -eq; expect '^Fail \["CREATE","UPDATE"\] .*"clusterpolicies'
step 3b "kubectl apply --dry-run=server -f 01-cpol-require-team.yaml"
rc_is -eq; has 'clusterpolicy.kyverno.io/kca01-require-team created (server dry run)'
# 다른 버전 요청 거부(설치 전에 중단)
step 4 "./setup.sh 1.20.0"
rc_is -ne; has "버전 고정: Kyverno v1.19.2(chart 3.9.2)만 설치, 인자 '1.20.0' 거부"
# 정책 동작: 적용 전 생성 → 적용 후 같은 파일 거부, team 라벨 Pod 허용
step 5 "kubectl apply -f 02-pod-no-team.yaml"
rc_is -eq; expect 'pod/web-no-team created'
step 5b "kubectl delete -f 02-pod-no-team.yaml --wait=true"
rc_is -eq; expect 'pod "web-no-team" deleted'
step 6 "kubectl apply -f 01-cpol-require-team.yaml && kubectl wait --for=condition=Ready clusterpolicy/kca01-require-team --timeout=60s"
rc_is -eq; expect 'condition met'
step 6b "kubectl apply -f 02-pod-no-team.yaml"
rc_is -ne; expect 'resource Pod/kca01/web-no-team was blocked'; expect 'team-label'
step 6c "kubectl apply -f 03-pod-team.yaml"
rc_is -eq; expect 'pod/web-team created'
# 소유 표식: 클러스터 ConfigMap id = 로컬 id
step 7 "kubectl -n kube-system get configmap kca-lab-owner -o jsonpath='{.data.lab}/{.data.cluster}{\"\\n\"}'"
expect '^kca01/kca01$'
step 7b "kubectl -n kube-system get configmap kca-lab-owner -o jsonpath='{.data.id}'"
[ -n "$out" ] && [ "$out" = "$(cat "$IDF")" ] && ok "id 일치" || ng "id 불일치"
# 다른 상태 폴더(표식 id 없음)에서는 teardown 거부, 클러스터 유지
if [ -e other-home ]; then ng "other-home 이미 있음, 소유 거부 확인 생략(삭제하지 않음)"; else
  step 8 "mkdir other-home && KCA_LAB_HOME=./other-home ./teardown.sh"
  rc_is -ne; has "소유 확인 실패: kca01 의 kube-system/kca-lab-owner 와 $LAB_DIR/other-home/kca01.id 불일치"
  rm -f other-home/kca01.kubeconfig && rmdir other-home
fi
step 8b "kind get clusters | grep -x kca01"
expect '^kca01$'
# reset: 실습 라벨 리소스만 삭제
step 9 "kubectl get clusterpolicy,pod -A -l lecture.kca/lab=kca01"
expect 'kca01-require-team'; expect 'web-team'
step 9b "./reset.sh && kubectl get clusterpolicy,pod -A -l lecture.kca/lab=kca01"
rc_is -eq; expect '초기화 완료: kca01, Namespace kca01 비어 있음'; expect 'No resources found'
step 9c "kubectl -n kyverno get deploy kyverno-admission-controller"
expect '^kyverno-admission-controller +1/1 '
# env.sh: KUBECONFIG 없는 새 셸에서 전용 kubeconfig 지정
step 10 "env -u KUBECONFIG bash -c 'echo \"KUBECONFIG=\${KUBECONFIG:-unset}\"'"
expect '^KUBECONFIG=unset$'
step 10b "env -u KUBECONFIG bash -c 'source ./env.sh >/dev/null && echo \"KUBECONFIG=\$KUBECONFIG\" && kubectl config current-context'"
rc_is -eq; same "KUBECONFIG=$KCFG
kind-kca01"
# 실습형 문항 KCA-D2-007: 검증 명령과 정답 상태
step Q007a "helm list -n kyverno -o json | grep -oE '\"(chart|app_version)\":\"[^\"]*\"'"
same '"chart":"kyverno-3.9.2"
"app_version":"v1.19.2"'
step Q007b "kubectl -n kyverno get deploy -o jsonpath='{range .items[*]}{.spec.template.spec.containers[0].image}{\"\\n\"}{end}' | sed 's/.*://' | sort -u"
same 'v1.19.2'
step Q007c "kubectl config current-context"
same 'kind-kca01'
echo; echo "RESULT pass=$pass fail=$fail"
echo "클러스터는 남겨 둠. 초기화: ./reset.sh, 삭제: ./teardown.sh"
[ "$fail" -eq 0 ]
