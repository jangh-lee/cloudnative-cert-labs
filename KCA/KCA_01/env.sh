# usage: source ./env.sh   현재 셸의 kubectl을 실습용 kubectl(v1.35)·전용 kubeconfig로 지정
# 검증에 실패하면 셸 환경을 바꾸지 않고 1을 반환
_kca_env() {
  _d="$(cd "$(dirname "${BASH_SOURCE[0]:-$1}")" && pwd)"
  _c=kca01
  _h="${KCA_LAB_HOME:-$HOME/.kca-lab}"
  case "$_h" in /*) ;; *) _h="$PWD/${_h#./}" ;; esac
  # 실습용 kubectl: KCA_KUBECTL → $_h/bin/kubectl → PATH 순
  if [ -n "${KCA_KUBECTL:-}" ]; then _k="$KCA_KUBECTL"; elif [ -x "$_h/bin/kubectl" ]; then _k="$_h/bin/kubectl"; else _k=kubectl; fi
  case "$_k" in /*) ;; */*) _k="$PWD/$_k" ;; *) _k="$(command -v "$_k" 2>/dev/null)" ;; esac
  case "$_k" in /*) [ -x "$_k" ] ;; *) false ;; esac || { echo "kubectl 없음: README 'kubectl v1.35' 설치 후 재실행"; return 1; }
  _f="$_h/$_c.kubeconfig"
  if [ ! -s "$_f" ]; then echo "kubeconfig 없음: ./setup.sh 먼저 실행"; return 1; fi
  _x="$(KUBECONFIG="$_f" "$_k" config current-context 2>/dev/null)"
  if [ "$_x" != "kind-$_c" ]; then echo "context 불일치($_x), ./setup.sh 재실행"; return 1; fi
  _i="$_h/$_c.id"
  _o="$(KUBECONFIG="$_f" "$_k" get --request-timeout=5s -n kube-system configmap kca-lab-owner -o jsonpath='{.data.lab}/{.data.cluster}/{.data.id}' 2>/dev/null)"
  if [ ! -s "$_i" ] || [ "$_o" != "kca01/$_c/$(cat "$_i")" ]; then
    echo "클러스터 응답 없음 또는 이 실습 소유 아님: ./setup.sh"; return 1
  fi
  _v="$("$_k" version --client -o json 2>/dev/null | awk -F'"' '/gitVersion/{print $4; exit}')"
  export KUBECONFIG="$_f"
  # 이 셸의 kubectl을 실습용 바이너리로
  case "$_k" in
    */kubectl) [ "$(command -v kubectl 2>/dev/null)" = "$_k" ] || export PATH="${_k%/*}:$PATH" ;;
    *) export KCA_KUBECTL_BIN="$_k"; kubectl() { "$KCA_KUBECTL_BIN" "$@"; } ;;
  esac
  hash -r 2>/dev/null
  cd "$_d" && echo "KUBECONFIG=$KUBECONFIG  context=kind-$_c  kubectl=$_v  dir=$_d"
}
_kca_env "$0" "$@"
_kca_rc=$?; unset -f _kca_env; unset _d _c _f _x _i _o _h _k _v
return $_kca_rc 2>/dev/null || exit $_kca_rc
