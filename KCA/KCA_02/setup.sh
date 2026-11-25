#!/usr/bin/env bash
# usage: ./setup.sh   도구 점검 → kind 클러스터 → Kyverno → webhook 대기 → 실습 Namespace
# 여러 번 실행해도 같은 결과(멱등). 기존 다른 클러스터·~/.kube/config 는 건드리지 않음.
set -euo pipefail
. "$(dirname "$0")/lib.sh"
mode_init "${1:-}"
trap 'echo "ERROR: setup 실패 (단계: ${STEP:-?}). 메시지 확인 후 ./setup.sh 재실행" >&2' ERR

STEP="도구 점검"; info "$STEP ($(uname -s))"
case "$(uname -s)" in Darwin|Linux) ;; *) die "macOS·Linux만 지원" ;; esac
for t in docker kind kubectl helm; do command -v "$t" >/dev/null 2>&1 || die "$t 없음. 설치 후 재실행"; done
docker info >/dev/null 2>&1 || die "Docker daemon 응답 없음. Docker Desktop/서비스 시작 후 재실행"
kv="$(kind version | awk '{print $2}')"
[ "$kv" = "$WANT_KIND" ] || warn "kind $kv (검증 버전 $WANT_KIND)"
kcv="$(kubectl version --client -o json 2>/dev/null | awk -F'"' '/gitVersion/{print $4; exit}')"
ver_ge "${kcv#v}" 1.34 || die "kubectl $kcv, 1.34 이상 필요"
hv="$(helm version --template '{{.Version}}' 2>/dev/null)"
ver_ge "${hv#v}" 3.14 || die "helm $hv, 3.14 이상 필요"
echo "    kind $kv · kubectl $kcv · helm $hv · docker $(docker version --format '{{.Server.Version}}')"
mem="$(docker info --format '{{.MemTotal}}')"
[ "$mem" -ge 4000000000 ] || warn "Docker 메모리 $((mem/1048576))MiB, 4GiB 이상 권장"
others="$(kind get clusters 2>/dev/null | grep -vx "$CLUSTER" | tr '\n' ' ' || true)"
[ -z "$others" ] || warn "실행 중인 다른 kind 클러스터: $others(메모리 부족 시 kind 기동 실패 가능, 이 스크립트는 건드리지 않음)"

STEP="inotify 점검"; info "$STEP"
docker image inspect "$NODE_IMAGE" >/dev/null 2>&1 || docker pull -q "$NODE_IMAGE" >/dev/null
ino="$(docker run --rm --entrypoint cat "$NODE_IMAGE" /proc/sys/fs/inotify/max_user_instances 2>&1)" \
  || die "inotify 값 확인 실패(docker run): $ino"
case "$ino" in ''|*[!0-9]*) die "inotify 값을 읽지 못함: $ino" ;; esac
if [ "$ino" -lt 512 ] && [ "${KCA_SKIP_INOTIFY:-0}" != 1 ]; then
  echo "    fs.inotify.max_user_instances=$ino (512 미만: kubelet 'too many open files'로 kind 기동 실패 가능)" >&2
  if [ "$(uname -s)" = Darwin ]; then
    echo "    해결(Docker VM, 재시작 시 원복): docker run --rm --privileged --pid=host alpine:3.20 sysctl -w fs.inotify.max_user_instances=512" >&2
  else
    echo "    해결: sudo sysctl -w fs.inotify.max_user_instances=512 (영구: /etc/sysctl.d/에 기록)" >&2
  fi
  die "inotify 한도 부족. 해결 후 재실행 (무시하려면 KCA_SKIP_INOTIFY=1)"
fi
echo "    max_user_instances=$ino"

STEP="kind 클러스터"; info "$STEP $CLUSTER"
state_dir_ok
if cluster_exists; then
  ensure_kubeconfig
  owned || die "$(owner_hint)"
  echo "    기존 실습 클러스터 재사용"
else
  rm -f "$KCFG" "$IDF"
  kind create cluster --name "$CLUSTER" --image "$NODE_IMAGE" --kubeconfig "$KCFG" --wait 180s
  id="$(date +%s)-$$-$RANDOM"
  k -n kube-system create configmap kca-lab-owner --from-literal=lab="$LAB" \
    --from-literal=cluster="$CLUSTER" --from-literal=id="$id" >/dev/null \
    || die "소유 표식 기록 실패. 'kind delete cluster --name $CLUSTER' 후 재실행"
  printf '%s\n' "$id" > "$IDF"
fi

STEP="Kyverno $APP 설치"; info "$STEP (chart $CHART)"
# --repo 직접 지정: 사용자 helm repo 설정 미변경
h upgrade --install kyverno kyverno --repo https://kyverno.github.io/kyverno/ \
  -n kyverno --create-namespace --version "$CHART" --wait --timeout 10m >/dev/null
img="$(k -n kyverno get deploy kyverno-admission-controller -o jsonpath='{.spec.template.spec.containers[0].image}')"
case "$img" in *":$APP") echo "    $img" ;; *) die "Kyverno 이미지 $img, 기대 $APP" ;; esac

STEP="정책 webhook 대기"; info "$STEP"
okp=0; last=""
for _ in $(seq 1 40); do
  if last="$(k apply --dry-run=server --request-timeout=10s -f "$LAB_DIR/$PROBE" 2>&1)"; then okp=1; break; fi
  sleep 3
done
[ "$okp" = 1 ] || die "정책 webhook 120초 내 응답 없음. 마지막 오류: $last
  확인: source ./env.sh && kubectl -n kyverno get pods"

STEP="실습 Namespace"; info "$STEP $LAB"
ns_check
k apply -f "$LAB_DIR/00-namespace.yaml" >/dev/null
trap - ERR
echo
echo "준비 완료: $CLUSTER (Kyverno $APP)"
echo "다음: source ./env.sh"
echo "주의: Kyverno v1.20 이상은 이 실습의 ClusterPolicy를 실행하지 않음. setup.sh가 고정한 v1.19.2만 사용"
