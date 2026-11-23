#!/bin/sh
# bin/tests/test-rollback.sh [SRC]
#
# 途中で止まったリリースが、書きかけたファイルを始める前の状態へ戻すこと。
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/lib/sandbox.sh"
. "$HERE/lib/assert.sh"

release_files_sum() {
  cat CHANGELOG.md composer.json packages/*/composer.json packages/*/README.md | cksum
}

leftovers() {
  find . -path ./.git -prune -o \( -name '*.tmp' -o -name 'CHANGELOG_NEW.md' \) -print | sort | tr '\n' ' '
}

remember() {
  head_before=$(g rev-parse HEAD)
  files_before=$(release_files_sum)
  status_before=$(g status --short --untracked-files=all)
}

expect_put_back() {
  # expect_put_back EXPECTED_EXIT（nonzero か、具体的な終了コード）
  if [ "$1" = nonzero ]; then
    check 'releaseFails' nonzero "$([ "$status" -ne 0 ] && echo nonzero || echo zero)"
  else
    check 'releaseExitsWith' "$1" "$status"
  fi
  check 'headIsUnchanged' "$head_before" "$(g rev-parse HEAD)"
  check 'releaseFilesAreBackToWhatTheyWere' "$files_before" "$(release_files_sum)"
  check 'statusIsWhatItWasBefore' "$status_before" "$(g status --short --untracked-files=all)"
  check 'nothingIsLeftStaged' '' "$(g diff --cached --name-only)"
  check 'noTemporaryFilesAreLeft' '' "$(leftovers)"
  check 'messageSaysTheFilesWerePutBack' 1 "$(grep -c 'were put back' "$sb/out" || true)"
}

# --- コミットの前で止まる ---------------------------------------------------

case_start 'composer update の失敗で止まる → 書き換えたファイルが元に戻る'
sb_new b
sb_change 'feat: add a thing'
remember
touch "$sb/inject/composer-update"
sb_release 1.0.0
expect_put_back nonzero

case_start 'composer.json が壊れていて jq が落ちる → 元に戻り、.tmp も残らない'
sb_new b
echo '{' > packages/zz-beta/composer.json
g commit -q -am 'chore: break a manifest'
g push -q origin main
remember
sb_release 1.0.0
expect_put_back nonzero

case_start 'prepare release の署名に失敗（ステージ済みで止まる）→ インデックスも元に戻る'
sb_new b
sb_change 'feat: add a thing'
remember
echo 1 > "$sb/inject/gpg-fail-at"
sb_release 1.0.0
expect_put_back nonzero

# INT は Ctrl-C、TERM は kill、HUP は端末を閉じたとき
for pair in INT:130 TERM:143 HUP:129; do
  case_start "途中でシグナル ${pair%%:*} を受ける → 元に戻り、終了コードは ${pair##*:}"
  sb_new b
  sb_change 'feat: add a thing'
  remember
  echo "${pair%%:*}" > "$sb/inject/composer-signal-update"
  sb_release 1.0.0
  expect_put_back "${pair##*:}"
done

case_start '手元の関係ない変更は、止まっても消えない'
sb_new b
sb_change 'feat: add a thing'
echo 'stray edit' >> packages/zz-beta/src/Beta.php
echo 'scratch' > notes.txt
remember
touch "$sb/inject/composer-update"
sb_release 1.0.0
expect_put_back nonzero
check 'unrelatedEditsSurvive' ' M packages/zz-beta/src/Beta.php;?? notes.txt;' "$(g status --short | tr '\n' ';')"

# --- コミットの後で止まる ---------------------------------------------------

case_start 'main の push が拒否されて止まる → prepare release のコミットは残す'
sb_new b
sb_change 'feat: add a thing'
head_before=$(g rev-parse HEAD)
touch "$sb/inject/reject-main-once"
sb_release 1.0.0
check 'releaseFails' nonzero "$([ "$status" -ne 0 ] && echo nonzero || echo zero)"
check 'prepareReleaseCommitIsKept' "chore: prepare release 1.0.0 $head_before" \
  "$(g log --no-show-signature -1 --format=%s) $(g rev-parse HEAD~1)"
check 'workingTreeIsClean' '' "$(g status --short)"
check 'noTemporaryFilesAreLeft' '' "$(leftovers)"

case_start '見出しを戻すコミットの署名に失敗して止まる → CHANGELOG.md が元に戻る'
sb_new b
sb_change 'feat: add a thing'
echo 5 > "$sb/inject/gpg-fail-at"
sb_release 1.0.0
check 'releaseFails' nonzero "$([ "$status" -ne 0 ] && echo nonzero || echo zero)"
check 'headIsThePrepareReleaseCommit' 'chore: prepare release 1.0.0' "$(g log --no-show-signature -1 --format=%s)"
check 'workingTreeIsClean' '' "$(g status --short)"
check 'nothingIsLeftStaged' '' "$(g diff --cached --name-only)"

# --- 止まらなかったとき -----------------------------------------------------

case_start '最後まで通ったときは何も戻さない'
sb_new b
sb_change 'feat: add a thing'
sb_release 1.0.0
check 'releaseSucceeds' 0 "$status"
check 'noMessageAboutPuttingFilesBack' 0 "$(grep -c 'were put back' "$sb/out" || true)"
check 'headRestoresTheUnreleasedHeading' 'chore: update CHANGELOG.md' "$(g log --no-show-signature -1 --format=%s)"
check 'workingTreeIsClean' '' "$(g status --short)"

finish
