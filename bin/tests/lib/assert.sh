#!/bin/sh
# bin/tests/lib/assert.sh
#
# テストの検査と集計。bin/tests/test-*.sh が読み込む。

failures=0
checks=0

# check NAME EXPECTED ACTUAL
#
# 合っていれば何も出さない。違えば名前と両方の値を出して、失敗を数える。
# 途中で止めないのは、1つのケースで何が崩れたかを一度に見るため。
check() {
  checks=$((checks + 1))

  if [ "$2" != "$3" ]; then
    printf '    FAIL %s\n         expected: %s\n         actual:   %s\n' "$1" "$2" "$3"
    failures=$((failures + 1))
  fi
}

# case_start TITLE
case_start() {
  printf '  %s\n' "$1"
}

# finish
#
# 件数を出して、失敗があれば 0 以外で終わる。テストの最後に呼ぶ。
finish() {
  printf '\nchecks: %s  failures: %s\n' "$checks" "$failures"
  [ "$failures" -eq 0 ]
}
