#!/bin/sh
# bin/tests/test-preflight.sh [SRC]
#
# リリースを始める前の検査。通してはいけない状態で、何も変えずに止まることを見る。
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/lib/sandbox.sh"
. "$HERE/lib/assert.sh"

snapshot() {
  # リリースが触りうるものを全部並べる。前後で比べて「何も変えていない」を確かめる。
  printf 'HEAD=%s\n' "$(g rev-parse HEAD)"
  printf 'branch=%s\n' "$(g branch --show-current)"
  printf 'branches=%s\n' "$(g branch --format='%(refname:short)' | tr '\n' ' ')"
  printf 'origin=%s\n' "$(g ls-remote "$sb/remotes/origin.git" | cksum)"
  printf 'status=%s\n' "$(g status --short --untracked-files=all | cksum)"
  printf 'ignored=%s\n' "$(g status --short --ignored | grep -c '^!!' || true)"
  printf 'files=%s\n' "$(cat CHANGELOG.md composer.json packages/*/composer.json packages/*/README.md | cksum)"
  for p in zz-alpha zz-beta; do
    printf 'split-%s=%s\n' "$p" "$(g ls-remote "$sb/remotes/shimomo/boatrace-php-$p.git" | cksum)"
  done
  # 読むだけの gh release view は数えない。状態を変えるのは create だけ
  printf 'gh=%s\n' "$(grep -c '^gh release create' "$sb/gh.log" || true)"
  printf 'composer=%s\n' "$(cksum < "$sb/composer.log")"
}

expect_refused() {
  # expect_refused BEFORE_SNAPSHOT MESSAGE_FRAGMENT
  check 'releaseFails' nonzero "$([ "$status" -ne 0 ] && echo nonzero || echo zero)"
  check 'nothingChanged' "$1" "$(snapshot)"
  check "messageMentions:$2" 1 "$(grep -c -- "$2" "$sb/out" | sed 's/^[1-9][0-9]*$/1/')"
}

section_body() {
  awk -v heading="## [$1] - " '
    index($0, heading) == 1 { inside = 1; next }
    inside && /^## / { exit }
    inside && /^- / { print }
  '
}

expect_published() {
  # expect_published VERSION
  check 'releaseSucceeds' 0 "$status"
  check 'tagIsThePrepareReleaseCommit' "chore: prepare release $1" \
    "$(g log --no-show-signature -1 --format=%s "$1" 2> /dev/null || true)"
  check 'originMainMatchesLocalMain' "$(g rev-parse main)" "$(g ls-remote origin refs/heads/main | cut -f1)"
  check 'originHasTheTag' 1 "$(g ls-remote --tags --refs origin "refs/tags/$1" | wc -l)"
  check 'splitRepositoriesHaveTheTag' '1 1' \
    "$(g ls-remote --tags --refs "$sb/remotes/shimomo/boatrace-php-zz-alpha.git" "refs/tags/$1" | wc -l) $(g ls-remote --tags --refs "$sb/remotes/shimomo/boatrace-php-zz-beta.git" "refs/tags/$1" | wc -l)"
}

# --- バージョンの形 ---------------------------------------------------------

for v in v1.0.0 1.0 foo '1.0.0 rc1' 1.0.0-beta1 1..0 1.0.0.0 .1.0 '1.0.0
2.0.0'; do
  case_start "バージョン '$(printf '%s' "$v" | tr '\n' '~')' は受け付けない"
  sb_new p
  before=$(snapshot)
  sb_release "$v"
  expect_refused "$before" 'Version must look like'
done

case_start 'バージョン 10.20.30 は受け付ける'
sb_new p
sb_release 10.20.30
expect_published 10.20.30

# --- ブランチ ---------------------------------------------------------------

case_start 'main 以外のブランチでは止まる'
sb_new p
g checkout -q -b topic
echo topic >> packages/zz-beta/src/Beta.php
g commit -q -am 'feat: work in progress on a topic branch'
before=$(snapshot)
sb_release 1.0.0
expect_refused "$before" 'current branch is topic'

case_start 'HEAD が切り離されていると止まる'
sb_new p
g checkout -q --detach HEAD
before=$(snapshot)
sb_release 1.0.0
expect_refused "$before" 'current branch is'

# --- リリースがコミットするファイルに未コミットの変更 -------------------------

dirty_case() {
  # dirty_case LABEL COMMAND...
  case_start "$1"
  shift
  sb_new p
  sb_change 'feat: add a thing'
  "$@"
  before=$(snapshot)
  sb_release 1.0.0
  expect_refused "$before" 'uncommitted changes'
}

edit_readme() { echo 'unfinished note that was never meant to ship' >> packages/zz-alpha/README.md; }
edit_package_manifest_staged() { echo ' ' >> packages/zz-beta/composer.json; g add packages/zz-beta/composer.json; }
edit_root_manifest() { echo ' ' >> composer.json; }
edit_changelog() { echo '- a hand-written line' >> CHANGELOG.md; }
add_untracked_package() {
  mkdir -p packages/zz-gamma
  cp packages/zz-beta/composer.json packages/zz-beta/README.md packages/zz-gamma/
}

dirty_case 'パッケージの README に未コミットの変更があると止まる' edit_readme
dirty_case 'パッケージの composer.json にステージ済みの変更があると止まる' edit_package_manifest_staged
dirty_case 'ルートの composer.json に未コミットの変更があると止まる' edit_root_manifest
dirty_case 'CHANGELOG.md に未コミットの変更があると止まる' edit_changelog
dirty_case 'まだコミットしていないパッケージがあると止まる' add_untracked_package

case_start 'リリースがコミットしないファイルの変更は、止めずにそのまま残す'
sb_new p
sb_change 'feat: add a thing'
echo 'stray edit' >> packages/zz-beta/src/Beta.php
echo 'scratch' > notes.txt
sb_release 1.0.0
expect_published 1.0.0
check 'unrelatedEditsAreLeftAlone' ' M packages/zz-beta/src/Beta.php;?? notes.txt;' \
  "$(g status --short | tr '\n' ';')"
check 'strayEditDidNotReachTheSplit' 0 \
  "$(g --git-dir="$sb/remotes/shimomo/boatrace-php-zz-beta.git" show 1.0.0:src/Beta.php | grep -c 'stray edit' || true)"

# --- origin とのずれ --------------------------------------------------------

case_start 'origin より遅れていると止まる → 取り込めば通り、取り込んだコミットも節に載る'
sb_new p
g clone -q "$sb/remotes/origin.git" "$sb/other"
( cd "$sb/other" && echo x >> packages/zz-beta/src/Beta.php && g commit -q -am 'chore: bump actions/checkout' && g push -q origin main )
before=$(snapshot)
sb_release 1.0.0
expect_refused "$before" 'behind origin/main'
g pull -q --rebase origin main
sb_release 1.0.0
expect_published 1.0.0
check 'sectionListsThePulledCommit' 1 \
  "$(g show 1.0.0:CHANGELOG.md | section_body 1.0.0 | grep -c '^- chore: bump actions/checkout$' || true)"

case_start 'origin より進んでいる（未 push のコミットがある）のは通す'
sb_new p
echo local >> packages/zz-beta/src/Beta.php
g commit -q -am 'feat: a commit that was never pushed'
sb_release 1.0.0
expect_published 1.0.0
check 'sectionListsTheUnpushedCommit' 1 \
  "$(g show 1.0.0:CHANGELOG.md | section_body 1.0.0 | grep -c '^- feat: a commit that was never pushed$' || true)"

case_start 'origin に届かないと止まる'
sb_new p
before=$(snapshot)
mv "$sb/remotes/origin.git" "$sb/remotes/gone.git"
sb_release 1.0.0
mv "$sb/remotes/gone.git" "$sb/remotes/origin.git"
check 'releaseFails' nonzero "$([ "$status" -ne 0 ] && echo nonzero || echo zero)"
check 'nothingChanged' "$before" "$(snapshot)"

case_start 'タグが origin にだけあるバージョンは、何も変えずに止まる'
sb_new p
sb_release 1.0.0
g tag -d 1.0.0 > /dev/null
sb_change 'fix: mend the thing'
before=$(snapshot)
sb_release 1.0.0
expect_refused "$before" 'Tag 1.0.0 already exists'

# --- 実行する場所 -----------------------------------------------------------

release_from() {
  # release_from DIRECTORY VERSION — DIRECTORY をカレントにして、絶対パスで呼ぶ
  echo 0 > "$sb/gpg.count"
  echo 0 > "$sb/main-push.count"
  set +e
  ( cd "$1" && sb_env sh "$sb/work/bin/release.sh" "$2" ) > "$sb/out" 2>&1
  status=$?
  set -e
}

case_start 'サブディレクトリから実行しても、ルートから実行したのと同じ結果になる'
sb_new p
sb_change 'feat: add a thing'
release_from "$sb/work/packages/zz-alpha" 1.0.0
expect_published 1.0.0
check 'workingTreeIsClean' '' "$(g status --short --ignored)"
check 'tagHasItsOwnChangelogSection' 1 "$(g show 1.0.0:CHANGELOG.md 2> /dev/null | grep -c '^## \[1.0.0\] - ' || true)"

case_start '別のリポジトリの中から呼んでも、相手にするのはスクリプトのあるリポジトリ'
sb_new p
sb_change 'feat: add a thing'
# リリースできてしまう形をした、よそのリポジトリを用意する
g init -q --bare "$sb/remotes/elsewhere.git"
mkdir -p "$sb/elsewhere/packages/zz-other"
(
  cd "$sb/elsewhere"
  g init -q .
  g remote add origin "$sb/remotes/elsewhere.git"
  printf '%s\n' '# Changelog' '' '## Unreleased' > CHANGELOG.md
  echo '{"name": "other/root", "replace": {"other/zz-other": "self.version"}}' > composer.json
  echo '{"name": "other/zz-other", "require": {"php": "^8.4"}}' > packages/zz-other/composer.json
  echo '# zz-other' > packages/zz-other/README.md
  g add -A
  g commit -q -m 'chore: initial commit'
  g push -q origin main
)
elsewhere_state() {
  ( cd "$sb/elsewhere" && printf '%s|%s|%s|%s' "$(g rev-parse HEAD)" "$(g tag -l | tr '\n' ' ')" \
      "$(g status --short --ignored | tr '\n' ';')" "$(g ls-remote origin | cksum)" )
}
elsewhere_before=$(elsewhere_state)
release_from "$sb/elsewhere" 1.0.0
check 'otherRepositoryIsUntouched' "$elsewhere_before" "$(elsewhere_state)"
expect_published 1.0.0

case_start 'bin/merge.sh もサブディレクトリから動く'
sb_new p
jq --indent 4 '.require["nesbot/carbon"] = "^3.8.4"' packages/zz-beta/composer.json > x && mv x packages/zz-beta/composer.json
set +e
( cd packages && sb_env sh ../bin/merge.sh ) > "$sb/out" 2>&1
status=$?
set -e
check 'mergeSucceeds' 0 "$status"
check 'rootManifestIsUpdated' '^3.8.4' "$(jq -r '.require["nesbot/carbon"]' composer.json)"
check 'onlyTheManifestsChanged' ' M composer.json; M packages/zz-beta/composer.json;' "$(g status --short --ignored | tr '\n' ';')"

finish
