#!/usr/bin/env bash
# usage: ./reset.sh   실습 리소스만 지우고 빈 Namespace 2개로 되돌림 (클러스터·Kyverno 유지)
set -euo pipefail
. "$(dirname "$0")/lib.sh"
mode_init "${1:-}"
require_owned_cluster
lab_reset
echo "초기화 완료: $CLUSTER, Namespace $(echo $NSES | tr " " "·") 비어 있음"
