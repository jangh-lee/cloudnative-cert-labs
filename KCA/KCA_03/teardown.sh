#!/usr/bin/env bash
# usage: ./teardown.sh   이 실습이 만든 kind 클러스터와 전용 kubeconfig 삭제
set -euo pipefail
. "$(dirname "$0")/lib.sh"
require_docker
mode_init "${1:-}"
if cluster_exists; then
  ensure_kubeconfig
  owned || die "$(owner_hint)"
  kind delete cluster --name "$CLUSTER" --kubeconfig "$KCFG"
else
  echo "클러스터 $CLUSTER 없음"
fi
rm -f "$KCFG" "$IDF"
echo "정리 완료"
