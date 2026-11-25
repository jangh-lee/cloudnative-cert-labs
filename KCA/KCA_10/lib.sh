# KCA-10 실습 공통 설정·함수 (setup/verify/reset/teardown 에서 source)
# bash 3.2(macOS)·Linux 호환
LAB=kca10
NSES="kca10-blue kca10-green"
LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="${KCA_LAB_HOME:-$HOME/.kca-lab}"
NODE_IMAGE='kindest/node:v1.35.8@sha256:07b2536e30b803ed61d1677a79df6115f798ce64c80f9e22f6ed45afd09323c0'
WANT_KIND=v0.33.0
LABEL='lecture.kca/lab=kca10'

die()  { echo "ERROR: $*" >&2; exit 1; }
warn() { echo "WARN:  $*" >&2; }
info() { echo "==> $*"; }

# 기준: Kyverno v1.19.2 단일(레거시 ClusterPolicy·Policy 실행 최종 minor). v1.20 이상은 레거시 정책 미실행
mode_init() {
  case "${1:-}" in ''|legacy) ;; *) die "인자 없음(기준 v1.19.2 단일): $1" ;; esac
  MODE=legacy; CLUSTER=kca10; CHART=3.9.2; APP=v1.19.2; PROBE=04-cpol-require-team.yaml
  CTX="kind-$CLUSTER"
  KCFG="$STATE_DIR/$CLUSTER.kubeconfig"
  IDF="$STATE_DIR/$CLUSTER.id"
}

# 전용 kubeconfig만 사용: ~/.kube/config·현재 context 미변경
k() { kubectl --kubeconfig "$KCFG" --context "$CTX" "$@"; }
h() { helm --kubeconfig "$KCFG" --kube-context "$CTX" "$@"; }

state_dir_ok() {
  [ ! -L "$STATE_DIR" ] || die "$STATE_DIR 가 심볼릭 링크, 실제 디렉터리만 사용"
  mkdir -p "$STATE_DIR" || die "$STATE_DIR 생성 실패"
  for f in "$KCFG" "$IDF"; do [ ! -L "$f" ] || die "$f 가 심볼릭 링크"; done
}
# x.y.z 비교: ver_ge 1.35.0 1.34 → 참
ver_ge() { awk -v a="$1" -v b="$2" 'BEGIN{split(a,x,".");split(b,y,".");for(i=1;i<=3;i++){if((x[i]+0)>(y[i]+0))exit 0;if((x[i]+0)<(y[i]+0))exit 1}exit 0}'; }
require_docker() { docker info >/dev/null 2>&1 || die "Docker daemon 응답 없음. Docker 시작 후 재실행"; }
cluster_exists() {
  out="$(kind get clusters 2>&1)" || die "kind get clusters 실패: $out"
  printf '%s\n' "$out" | grep -qx "$CLUSTER"
}
# kubeconfig는 매번 kind에서 다시 받아 kind 클러스터 이름과 묶음
ensure_kubeconfig() {
  state_dir_ok
  kind export kubeconfig --name "$CLUSTER" --kubeconfig "$KCFG" >/dev/null 2>&1 \
    || die "kubeconfig 생성 실패: kind export kubeconfig --name $CLUSTER"
}
# 소유 표식: kube-system/kca-lab-owner {lab, cluster, id} = 로컬 $IDF
owned() {
  [ -s "$IDF" ] || return 1
  got="$(k -n kube-system get configmap kca-lab-owner -o jsonpath='{.data.lab}/{.data.cluster}/{.data.id}' 2>/dev/null)" || return 1
  [ "$got" = "$LAB/$CLUSTER/$(cat "$IDF")" ]
}
owner_hint() { echo "소유 확인 실패: $CLUSTER 의 kube-system/kca-lab-owner 와 $IDF 불일치. 이 실습이 만든 클러스터가 확실하면 직접 'kind delete cluster --name $CLUSTER'"; }
require_owned_cluster() {
  require_docker
  cluster_exists || die "클러스터 $CLUSTER 없음. 먼저: ./setup.sh"
  ensure_kubeconfig
  owned || die "$(owner_hint)"
}

# 실습 Namespace 소유 확인: 없으면 통과, 있고 라벨 맞으면 통과, 라벨 없으면 중단
ns_check() {
  for ns in $NSES; do
    n="$(k get namespace "$ns" --ignore-not-found -o name)" || die "Namespace 조회 실패"
    [ -z "$n" ] && continue
    [ "$(k get namespace "$ns" -o jsonpath='{.metadata.labels.lecture\.kca/lab}')" = "$LAB" ] \
      || die "Namespace $ns 에 실습 라벨 없음, 건드리지 않음"
  done
}
# 실습 외 리소스 탐지(삭제 전 실행): 실습 라벨 없는 객체 중 기본 SA·root CA·이벤트·Kyverno 생성 보고서 제외
foreign_left() {
  res="$(k api-resources --verbs=list,delete --namespaced -o name 2>/dev/null)" || die "api-resources 조회 실패"
  for ns in $NSES; do
    [ -n "$(k get namespace "$ns" --ignore-not-found -o name)" ] || continue
    for r in $res; do
      case "$r" in events|events.events.k8s.io) continue ;; esac
      o="$(k -n "$ns" get "$r" -l '!lecture.kca/lab,app.kubernetes.io/managed-by!=kyverno' \
           -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null)" \
        || die "$r 조회 실패: $(k -n "$ns" get "$r" -o name 2>&1 | grep -v '^Warning:' | head -2)"
      printf '%s\n' "$o" | while read -r n; do
        [ -n "$n" ] || continue
        case "$r/$n" in serviceaccounts/default|configmaps/kube-root-ca.crt) continue ;; esac
        echo "$ns/$r/$n"
      done
    done
  done
}
# 실습 리소스 초기화: 소유 확인 → 실습 외 리소스 확인(삭제 전) → 라벨 정책·Pod 삭제 → Namespace 재생성
lab_reset() {
  set -e
  ns_check
  left="$(foreign_left)"
  [ -z "$left" ] || die "실습 Namespace에 실습 외 리소스 존재, 아무것도 삭제하지 않음: $(echo $left)"
  k delete clusterpolicy -l "$LABEL" --ignore-not-found >/dev/null 2>&1
  for ns in $NSES; do
    [ -n "$(k get namespace "$ns" --ignore-not-found -o name)" ] || continue
    k -n "$ns" delete policy,pod -l "$LABEL" --ignore-not-found --wait=true >/dev/null 2>&1
    k delete namespace "$ns" --wait=true >/dev/null
  done
  k apply -f "$LAB_DIR/00-namespace.yaml" >/dev/null
}
