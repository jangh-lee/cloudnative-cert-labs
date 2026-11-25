# usage: source ./env.sh   현재 셸의 kubectl을 실습 전용 kubeconfig로 지정
# 검증에 실패하면 셸 환경을 바꾸지 않고 1을 반환
_kca_env() {
  _d="$(cd "$(dirname "${BASH_SOURCE[0]:-$1}")" && pwd)"
  _c=kca02
  _f="${KCA_LAB_HOME:-$HOME/.kca-lab}/$_c.kubeconfig"
  if [ ! -s "$_f" ]; then echo "kubeconfig 없음: ./setup.sh 먼저 실행"; return 1; fi
  _x="$(KUBECONFIG="$_f" kubectl config current-context 2>/dev/null)"
  if [ "$_x" != "kind-$_c" ]; then echo "context 불일치($_x), ./setup.sh 재실행"; return 1; fi
  _i="${KCA_LAB_HOME:-$HOME/.kca-lab}/$_c.id"
  _o="$(KUBECONFIG="$_f" kubectl get --request-timeout=5s -n kube-system configmap kca-lab-owner -o jsonpath='{.data.lab}/{.data.cluster}/{.data.id}' 2>/dev/null)"
  if [ ! -s "$_i" ] || [ "$_o" != "kca02/$_c/$(cat "$_i")" ]; then
    echo "클러스터 응답 없음 또는 이 실습 소유 아님: ./setup.sh"; return 1
  fi
  export KUBECONFIG="$_f"
  cd "$_d" && echo "KUBECONFIG=$KUBECONFIG  context=kind-$_c  dir=$_d"
}
_kca_env "$0" "$@"
_kca_rc=$?; unset -f _kca_env; unset _d _c _f _x _i _o
return $_kca_rc 2>/dev/null || exit $_kca_rc
