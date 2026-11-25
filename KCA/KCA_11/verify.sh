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
expect() { printf '%s' "$out" | grep -qE "$1" && ok "$1" || ng "$1"; }
reject() { printf '%s' "$out" | grep -qE "$1" && ng "없어야 함: $1" || ok "없음: $1"; }
rc_is()  { [ "$rc" "$1" 0 ] && ok "exit $rc" || ng "exit $rc"; }
SA='--as=system:serviceaccount:kca11:deployer'
BLK='resource Pod/kca11/%s was blocked'
# settle <정규식> <명령>: 정책·Namespace 라벨 변경이 webhook에 반영될 때까지 서버 dry-run 재시도(최대 30초)
settle() { for _ in $(seq 1 15); do o="$(eval "$2" 2>&1)"; printf '%s' "$o" | grep -qE "$1" && return 0; sleep 2; done; echo "WARN: 반영 대기 시간 초과: $2"; }
DRY='--dry-run=server'

# 0: 적용 전(정책 없음): 이후 단계와 같은 파일·같은 명령으로 02·03이 그대로 만들어짐
step 0 "kubectl apply -f 02-pod-web.yaml"
rc_is -eq; expect 'pod/web created'
step 0a "kubectl apply -f 03-pod-db.yaml"
rc_is -eq; expect 'pod/db created'
step 0b "kubectl delete -f 02-pod-web.yaml -f 03-pod-db.yaml --wait=true"
rc_is -eq; expect 'pod "db" deleted'
# 1: 실습 RBAC(ServiceAccount deployer, kca11 Pod 권한)
step 1 "kubectl apply -f 01-rbac.yaml && kubectl auth can-i create pods -n kca11 $SA && kubectl auth can-i get pods -n kca11 $SA"
rc_is -eq; expect 'serviceaccount/deployer created'; expect '^yes$'
# 2: match.any → web·db 모두 거부
step 2 "kubectl apply -f 11-cpol-any.yaml && kubectl wait --for=condition=Ready clusterpolicy/kca11-require-owner --timeout=60s"
rc_is -eq; expect 'condition met'
step 2b "kubectl apply -f 02-pod-web.yaml"
rc_is -ne; expect "$(printf "$BLK" web)"; expect 'require-owner'
step 2c "kubectl apply -f 03-pod-db.yaml"
rc_is -ne; expect "$(printf "$BLK" db)"
# 3: match.all → web 거부, db 생성
step 3 "kubectl apply -f 12-cpol-all.yaml && kubectl wait --for=condition=Ready clusterpolicy/kca11-require-owner --timeout=60s"
rc_is -eq; expect 'configured'
settle 'pod/db created' "kubectl apply $DRY -f 03-pod-db.yaml"
step 3b "kubectl apply -f 02-pod-web.yaml"
rc_is -ne; expect "$(printf "$BLK" web)"
step 3c "kubectl apply -f 03-pod-db.yaml"
rc_is -eq; expect 'pod/db created'
# 4: Namespace 라벨 env 제거 → namespaceSelector 불일치 → web 생성
step 4 "kubectl label namespace kca11 env- && kubectl get namespace kca11 -L env"
rc_is -eq; expect 'namespace/kca11 unlabeled'
settle 'pod/web created' "kubectl apply $DRY -f 02-pod-web.yaml"
step 4b "kubectl apply -f 02-pod-web.yaml"
rc_is -eq; expect 'pod/web created'
step 4c "kubectl label namespace kca11 env=prod && kubectl delete -f 02-pod-web.yaml --wait=true"
rc_is -eq; expect 'namespace/kca11 labeled'; expect 'pod "web" deleted'
settle 'was blocked' "kubectl apply $DRY -f 04-pod-web-exempt.yaml"
# 5~6: exclude selector 적용 전(12) 거부 → 적용 후(13) 생성
step 5 "kubectl apply -f 04-pod-web-exempt.yaml"
rc_is -ne; expect "$(printf "$BLK" web-exempt)"
step 6 "kubectl apply -f 13-cpol-exclude-label.yaml && kubectl wait --for=condition=Ready clusterpolicy/kca11-require-owner --timeout=60s"
rc_is -eq
settle 'created' "kubectl apply $DRY -f 04-pod-web-exempt.yaml"
step 6b "kubectl apply -f 04-pod-web-exempt.yaml"
rc_is -eq; expect 'pod/web-exempt created'
# 7~8: subjects 적용 전(13) SA 거부 → 적용 후(14) SA 생성, 관리자 거부
step 7 "kubectl apply -f 02-pod-web.yaml $SA"
rc_is -ne; expect "$(printf "$BLK" web)"
step 8 "kubectl apply -f 14-cpol-exclude-sa.yaml && kubectl wait --for=condition=Ready clusterpolicy/kca11-require-owner --timeout=60s"
rc_is -eq
settle 'created' "kubectl apply $DRY -f 02-pod-web.yaml $SA"
step 8a "kubectl apply -f 02-pod-web.yaml"
rc_is -ne; expect "$(printf "$BLK" web)"
step 8b "kubectl apply -f 02-pod-web.yaml $SA"
rc_is -eq; expect 'pod/web created'
step 8c "kubectl get pods -n kca11 -L tier,exempt"
expect '^db '; expect '^web '; expect '^web-exempt '
# 9: subjects + background: true 정책은 생성 거부
step 9 "kubectl apply -f 15-cpol-subjects-bg.yaml"
rc_is -ne; expect 'validate-policy.kyverno.svc'; expect 'Set spec.background=false'
reject 'kca11-subjects-bg created'
# 실습형 문항 KCA-D4-017: 학습자 답안(KCA_Q017_FILE) 또는 풀이 파일 판정
SOL="${KCA_Q017_FILE:-../../exams/items/KCA-D4-017.solution.yaml}"
if [ -f "$SOL" ]; then
  step Q017 "kubectl delete -f 14-cpol-exclude-sa.yaml && kubectl delete pod -n kca11 -l lecture.kca/lab=kca11 --wait=true && kubectl apply -f \"\$SOL\" && kubectl wait --for=condition=Ready clusterpolicy/kca11-q017 --timeout=60s"
  rc_is -eq; expect 'condition met'
  settle 'created' "kubectl apply $DRY -f 04-pod-web-exempt.yaml"
  step Q017b "kubectl apply -f 02-pod-web.yaml"
  rc_is -ne; expect "$(printf "$BLK" web)"
  step Q017c "kubectl apply -f 03-pod-db.yaml"
  rc_is -ne; expect "$(printf "$BLK" db)"
  step Q017d "kubectl apply -f 04-pod-web-exempt.yaml"
  rc_is -eq; expect 'pod/web-exempt created'
  step Q017e "kubectl apply -f 05-pod-cache.yaml"
  rc_is -eq; expect 'pod/cache created'
elif [ -n "${KCA_Q017_FILE:-}" ]; then
  ng "KCA_Q017_FILE 없음: $KCA_Q017_FILE"
else
  echo; echo "SKIP: 문항 풀이 파일 없음(학습자 패키지), KCA-D4-017 판정 생략"
fi
echo; echo "RESULT pass=$pass fail=$fail"
echo "실습 리소스는 남겨 둠. 초기화: ./reset.sh"
[ "$fail" -eq 0 ]
