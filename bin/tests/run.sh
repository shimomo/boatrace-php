#!/bin/sh
# bin/tests/run.sh [SRC]
#
# リリースのスクリプト（bin/release.sh・bin/merge.sh・bin/lib/*）のテストを
# 全部走らせる。本物のリリースは行わない（→ lib/sandbox.sh）。
#
# 使い方:
#   sh bin/tests/run.sh             このリポジトリの bin/ を検査する
#   sh bin/tests/run.sh <dir>       <dir>/bin を検査する（壊した版が落ちることを
#                                   確かめるとき。テスト1本だけなら
#                                   sh bin/tests/test-rerun.sh <dir> のように呼ぶ）
#
# テストは互いに独立した砂場で動くので、並べて走らせる。
# 通ったテストは件数だけ、落ちたテストは出力をそのまま出す。

set -eu

here=$(cd "$(dirname "$0")" && pwd)

results=$(mktemp -d "${TMPDIR:-/tmp}/boatrace-release-tests-results.XXXXXX")
trap 'rm -rf "$results"' EXIT

for test in "$here"/test-*.sh; do
  name=$(basename "$test" .sh)
  (
    status=0
    sh "$test" "$@" > "$results/$name.out" 2>&1 || status=$?
    echo "$status" > "$results/$name.status"
  ) &
done

wait

failed=0

for test in "$here"/test-*.sh; do
  name=$(basename "$test" .sh)

  if [ "$(cat "$results/$name.status")" -eq 0 ]; then
    printf 'ok    %-16s %s\n' "$name" "$(tail -n 1 "$results/$name.out")"
  else
    printf 'FAIL  %s\n' "$name"
    sed 's/^/      /' "$results/$name.out"
    failed=1
  fi
done

exit "$failed"
