# KCA-01 실습 공통 설정·함수 (setup/verify/reset/teardown 에서 source)
# bash 3.2(macOS)·Linux 호환
LAB=kca01
LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="${KCA_LAB_HOME:-$HOME/.kca-lab}"
# 상대 경로는 실행 위치 기준 절대 경로로 고정(이후 cd와 무관)
case "$STATE_DIR" in /*) ;; *) STATE_DIR="$PWD/${STATE_DIR#./}" ;; esac
KYVERNO_DEPLOYS="kyverno-admission-controller kyverno-background-controller kyverno-cleanup-controller kyverno-reports-controller"
NODE_IMAGE='kindest/node:v1.35.8@sha256:07b2536e30b803ed61d1677a79df6115f798ce64c80f9e22f6ed45afd09323c0'
WANT_KIND=v0.33.0
LABEL='lecture.kca/lab=kca01'

die()  { echo "ERROR: $*" >&2; exit 1; }
warn() { echo "WARN:  $*" >&2; }
info() { echo "==> $*"; }

# 기준: Kyverno v1.19.2 단일(레거시 ClusterPolicy 실행 최종 minor). v1.20 이상은 ClusterPolicy 미실행
mode_init() {
  # 버전 고정: 인자로 다른 버전을 받지 않음(v1.20 이상은 이 과정 ClusterPolicy 미실행)
  [ -z "${1:-}" ] || die "버전 고정: Kyverno v1.19.2(chart 3.9.2)만 설치, 인자 '$1' 거부. v1.20 이상은 이 과정의 ClusterPolicy를 실행하지 않음"
  CLUSTER=kca01; CHART=3.9.2; APP=v1.19.2; PROBE=01-cpol-require-team.yaml
  CHART_REPO=https://kyverno.github.io/kyverno/
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
# 실습용 kubectl: KCA_KUBECTL → $STATE_DIR/bin/kubectl → PATH 순. node v1.35.8, 지원 client 1.34~1.36
KUBECTL_WANT=v1.35.8
kubectl_pick() {
  if [ -n "${KCA_KUBECTL:-}" ]; then KUBECTL="$KCA_KUBECTL"
  elif [ -x "$STATE_DIR/bin/kubectl" ]; then KUBECTL="$STATE_DIR/bin/kubectl"
  else KUBECTL=kubectl; fi
  case "$KUBECTL" in /*) ;; */*) KUBECTL="$PWD/$KUBECTL" ;; *) KUBECTL="$(command -v "$KUBECTL" 2>/dev/null || true)" ;; esac
  export KUBECTL
  # 이 스크립트의 kubectl·eval 명령·하위 프로세스가 같은 바이너리 사용
  case "$KUBECTL" in
    */kubectl) PATH="${KUBECTL%/*}:$PATH"; export PATH ;;
    ?*) kubectl() { "$KUBECTL" "$@"; }; export -f kubectl ;;
  esac
}
kubectl_pick
tilde() { case "$1" in "$HOME"/*) echo "~/${1#"$HOME"/}" ;; *) echo "$1" ;; esac; }
kubectl_hint() { echo "README 'kubectl v1.35' 절차(임시 파일 → sha256 확인 성공 시에만 $(tilde "$STATE_DIR/bin")/kubectl 로 이동), 또는 KCA_KUBECTL=<v1.35 kubectl 경로>"; }
# client minor 1.34~1.36 밖이면 경고, 결과 버전은 kcv
kubectl_check() {
  [ -n "$KUBECTL" ] && [ -x "$KUBECTL" ] || die "kubectl 없음. 설치: $(kubectl_hint)"
  kcv="$("$KUBECTL" version --client -o json 2>/dev/null | awk -F'"' '/gitVersion/{print $4; exit}')"
  { ver_ge "${kcv#v}" 1.34 && ver_ge 1.36.99 "${kcv#v}"; } \
    || warn "kubectl $kcv ($(tilde "$KUBECTL")): node v1.35 지원 범위 1.34~1.36 밖. 설치: $(kubectl_hint)"
}
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

# 초기화 단계 실패: 메시지 출력 후 1 반환. 호출부가 종료 상태를 확인(set -e·서브셸 여부와 무관)
rfail() { echo "ERROR: $*" >&2; return 1; }
# Kyverno가 실습 Namespace에 만드는 보고서 종류: managed-by=kyverno 예외는 이 종류에만 적용
REPORT_KINDS="policyreports.wgpolicyk8s.io ephemeralreports.reports.kyverno.io"
# 실습 외 리소스 선택자: 이 회차 라벨 값이 아닌 객체(라벨 없음·다른 회차 값 모두 포함)
foreign_sel() {
  s="lecture.kca/lab!=$LAB"
  case " $REPORT_KINDS " in *" $1 "*) s="$s,app.kubernetes.io/managed-by!=kyverno" ;; esac
  echo "$s"
}
# 실습 Namespace 소유 확인: 없으면 0, 있고 라벨 맞으면 0, 라벨 없거나 다르면 1
ns_check() {
  n="$(k get namespace "$LAB" --ignore-not-found -o name)" || { rfail "Namespace 조회 실패"; return 1; }
  [ -z "$n" ] && return 0
  v="$(k get namespace "$LAB" -o jsonpath='{.metadata.labels.lecture\.kca/lab}')" || { rfail "Namespace 라벨 조회 실패"; return 1; }
  [ "$v" = "$LAB" ] || { rfail "Namespace $LAB 에 실습 라벨 없음, 건드리지 않음"; return 1; }
}
# 실습 라벨 워크로드의 하위 객체(ownerReferences UID 연쇄)
lab_uids() {
  u="$(k -n "$LAB" get deployment -l "$LABEL" -o jsonpath='{range .items[*]}{.metadata.uid}{" "}{end}')" || { rfail "실습 워크로드 조회 실패"; return 1; }
  r="$(k -n "$LAB" get replicaset -o jsonpath='{range .items[*]}{.metadata.uid}{"|"}{.metadata.ownerReferences[0].uid}{"\n"}{end}')" || { rfail "ReplicaSet 조회 실패"; return 1; }
  for line in $r; do o="${line#*|}"; case " $u " in *" $o "*) [ -n "$o" ] && u="$u ${line%%|*}" ;; esac; done
  echo "$u"
}
# 실습 외 리소스 탐지(삭제 전): 이 회차 라벨 값이 아닌 객체 중 기본 SA·root CA·이벤트·Kyverno 보고서·실습 워크로드 하위 객체 제외
foreign_left() {
  u="$(lab_uids)" || return 1; uids=" $u "
  res="$(k api-resources --verbs=list,delete --namespaced -o name 2>/dev/null)" || { rfail "api-resources 조회 실패"; return 1; }
  for r in $res; do
    case "$r" in events|events.events.k8s.io) continue ;; esac
    o="$(k -n "$LAB" get "$r" -l "$(foreign_sel "$r")" \
         -o jsonpath='{range .items[*]}{.metadata.name}{"|"}{.metadata.ownerReferences[0].uid}{"\n"}{end}' 2>/dev/null)" \
      || { rfail "$r 조회 실패: $(k -n "$LAB" get "$r" -o name 2>&1 | grep -v '^Warning:' | head -2)"; return 1; }
    while IFS='|' read -r n own; do
      [ -n "$n" ] || continue
      case "$r/$n" in serviceaccounts/default|configmaps/kube-root-ca.crt) continue ;; esac
      if [ -n "$own" ]; then case "$uids" in *" $own "*) continue ;; esac; fi
      echo "$r/$n"
    done <<EOF_LIST
$o
EOF_LIST
  done
}
# 실습 리소스 초기화: 소유 확인 → 실습 외 리소스 확인(삭제 전) → 라벨 리소스 삭제 → Namespace 재생성
#   단계마다 종료 상태 확인, 실패하면 다음 변경 전에 1 반환
lab_reset() {
  ns_check || return 1
  n="$(k get namespace "$LAB" --ignore-not-found -o name)" || { rfail "Namespace 조회 실패"; return 1; }
  if [ -n "$n" ]; then
    left="$(foreign_left)" || { rfail "실습 외 리소스 확인 실패, 아무것도 삭제하지 않음"; return 1; }
    [ -z "$left" ] || { rfail "Namespace $LAB 에 실습 외 리소스 존재, 아무것도 삭제하지 않음: $(echo $left)"; return 1; }
  fi
  k delete clusterpolicy -l "$LABEL" --ignore-not-found >/dev/null || { rfail "ClusterPolicy 삭제 실패"; return 1; }
  if [ -n "$n" ]; then
    k -n "$LAB" delete deployment -l "$LABEL" --ignore-not-found --cascade=foreground --wait=true >/dev/null || { rfail "Deployment 삭제 실패"; return 1; }
    k -n "$LAB" delete pod -l "$LABEL" --ignore-not-found --wait=true >/dev/null || { rfail "Pod 삭제 실패"; return 1; }
    k delete namespace "$LAB" --wait=true >/dev/null || { rfail "Namespace 삭제 실패"; return 1; }
  fi
  k apply -f "$LAB_DIR/00-namespace.yaml" >/dev/null || { rfail "Namespace 생성 실패"; return 1; }
}
