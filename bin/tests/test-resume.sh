#!/bin/sh
# bin/tests/test-resume.sh [SRC]
#
# タグを打った後で止まったリリースを、同じバージョンで回し直して続きから進める。
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/lib/sandbox.sh"
. "$HERE/lib/assert.sh"

split_dir() {
  echo "$sb/remotes/shimomo/boatrace-php-$1.git"
}

snapshot() {
  printf 'HEAD=%s\n' "$(g rev-parse HEAD)"
  printf 'branches=%s\n' "$(g branch --format='%(refname:short)' | tr '\n' ' ')"
  printf 'tags=%s\n' "$(g tag -l | tr '\n' ' ')"
  printf 'origin=%s\n' "$(g ls-remote "$sb/remotes/origin.git" | cksum)"
  printf 'status=%s\n' "$(g status --short --untracked-files=all | cksum)"
  printf 'files=%s\n' "$(cat CHANGELOG.md composer.json packages/*/composer.json packages/*/README.md | cksum)"
  for p in zz-alpha zz-beta; do
    printf 'split-%s=%s\n' "$p" "$(g ls-remote "$(split_dir "$p")" | cksum)"
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

expect_completed() {
  # expect_completed VERSION
  v="$1"
  check 'releaseSucceeds' 0 "$status"
  check 'tagIsThePrepareReleaseCommit' "chore: prepare release $v" \
    "$(g log --no-show-signature -1 --format=%s "$v" 2> /dev/null || true)"
  check 'historyHasOnePrepareReleaseCommit' 1 \
    "$(g log --no-show-signature --format=%s | grep -c "^chore: prepare release $v\$" || true)"
  check 'originHasTheTag' "$(g rev-parse "$v")" "$(g ls-remote --tags --refs origin "refs/tags/$v" | cut -f1)"
  for p in zz-alpha zz-beta; do
    check "splitHasTheTag:$p" 1 "$(g ls-remote --tags --refs "$(split_dir "$p")" "refs/tags/$v" | wc -l)"
    check "splitTagMatchesTheMonorepoTag:$p" "$(g rev-parse "$v:packages/$p")" \
      "$(g --git-dir="$(split_dir "$p")" rev-parse "$v^{tree}" 2> /dev/null || true)"
    check "splitMainIsTheTaggedCommit:$p" \
      "$(g --git-dir="$(split_dir "$p")" rev-parse "$v^{commit}" 2> /dev/null || true)" \
      "$(g ls-remote "$(split_dir "$p")" refs/heads/main | cut -f1)"
    check "releaseIsRecordedOnce:$p" "$v" \
      "$(cat "$sb/gh-releases/shimomo_boatrace-php-$p" 2> /dev/null | tr '\n' ' ' | sed 's/ $//')"
  done
  check 'noLeftoverLocalRefs' "main|$v" \
    "$(g branch --format='%(refname:short)' | tr '\n' ' ' | sed 's/ $//')|$(g tag -l | tr '\n' ' ' | sed 's/ $//')"
  check 'headRestoresTheUnreleasedHeading' '2 0 chore: update CHANGELOG.md' \
    "$(g show --no-show-signature --numstat --format= HEAD -- CHANGELOG.md | awk '{ printf "%s %s ", $1, $2 }')$(g log --no-show-signature -1 --format=%s)"
  check 'headHasUnreleasedHeadingOnLine3' '3:## Unreleased' \
    "$(grep -n '^## Unreleased$' CHANGELOG.md | tr '\n' ' ' | sed 's/ $//')"
  check 'headHasExactlyOneSectionForItsVersion' 1 "$(grep -c "^## \[$v\] - " CHANGELOG.md || true)"
  check 'originMainMatchesLocalMain' "$(g rev-parse main)" "$(g ls-remote origin refs/heads/main | cut -f1)"
  check 'workingTreeIsClean' '' "$(g status --short)"
}

hide_split() { mv "$(split_dir "$1")" "$sb/remotes/shimomo/hidden-$1.git"; }
show_split() { mv "$sb/remotes/shimomo/hidden-$1.git" "$(split_dir "$1")"; }

expect_first_attempt_failed() {
  check 'firstAttemptFails' nonzero "$([ "$status" -ne 0 ] && echo nonzero || echo zero)"
}

# --- 続きから進む -----------------------------------------------------------

case_start '2つ目のパッケージの分割先に届かず止まる → 回し直すと残りだけ公開して終わる'
sb_new r
sb_change 'feat: add a thing'
hide_split zz-beta
sb_release 1.0.0
expect_first_attempt_failed
show_split zz-beta
alpha_before=$(g ls-remote "$(split_dir zz-alpha)" | cksum)
tag_before=$(g rev-parse 1.0.0)
composer_before=$(wc -l < "$sb/composer.log")
sb_release 1.0.0
expect_completed 1.0.0
check 'publishedPackageIsNotPushedAgain' "$alpha_before" "$(g ls-remote "$(split_dir zz-alpha)" | cksum)"
check 'tagIsNotMoved' "$tag_before" "$(g rev-parse 1.0.0)"
check 'prepareStepsAreNotRunAgain' "$composer_before" "$(wc -l < "$sb/composer.log")"
check 'outputSaysResuming' 1 "$(grep -c 'Resuming release 1.0.0' "$sb/out" || true)"

case_start '1つ目のパッケージの一時タグの署名に失敗して止まる → 回し直すと続きから'
sb_new r
sb_change 'feat: add a thing'
echo 3 > "$sb/inject/gpg-fail-at"
sb_release 1.0.0
expect_first_attempt_failed
rm -f "$sb"/inject/*
sb_release 1.0.0
expect_completed 1.0.0

case_start 'タグの push が拒否されて止まる → 回し直すとタグを push して続きから'
sb_new r
sb_change 'feat: add a thing'
touch "$sb/inject/reject-tag-once"
sb_release 1.0.0
expect_first_attempt_failed
tag_before=$(g rev-parse 1.0.0)
sb_release 1.0.0
expect_completed 1.0.0
check 'tagIsNotMoved' "$tag_before" "$(g rev-parse 1.0.0)"

case_start '見出しを戻すコミットの署名に失敗して止まる → 回し直すと見出しが戻る'
sb_new r
sb_change 'feat: add a thing'
echo 5 > "$sb/inject/gpg-fail-at"
sb_release 1.0.0
expect_first_attempt_failed
rm -f "$sb"/inject/*
sb_release 1.0.0
expect_completed 1.0.0

case_start '見出しを戻すコミットの push が拒否されて止まる → 回し直すと push される'
sb_new r
sb_change 'feat: add a thing'
echo 2 > "$sb/inject/reject-main-at"
sb_release 1.0.0
expect_first_attempt_failed
rm -f "$sb"/inject/*
sb_release 1.0.0
expect_completed 1.0.0

case_start '止まった後でコミットが増えても、公開されるのはタグの時点の内容'
sb_new r
sb_change 'feat: add a thing'
hide_split zz-beta
sb_release 1.0.0
expect_first_attempt_failed
show_split zz-beta
sb_change 'feat: a change that belongs to the next release'
sb_release 1.0.0
expect_completed 1.0.0
check 'laterChangeIsNotInThePublishedTag' 0 \
  "$(g --git-dir="$(split_dir zz-beta)" show 1.0.0:src/Beta.php 2> /dev/null | grep -c 'belongs to the next release' || true)"

# --- GitHub Release の作成 ---------------------------------------------------

release_store() {
  echo "$sb/gh-releases/shimomo_boatrace-php-$1"
}

case_start 'GitHub Release の作成に失敗すると止まる → 回し直すと、足りない Release だけが作られる'
sb_new r
sb_change 'feat: add a thing'
touch "$sb/inject/gh-create"
sb_release 1.0.0
expect_first_attempt_failed
check 'tagWasPushedBeforeTheFailure' 1 "$(g ls-remote --tags --refs "$(split_dir zz-alpha)" refs/tags/1.0.0 | wc -l)"
rm -f "$sb"/inject/*
alpha_before=$(g ls-remote "$(split_dir zz-alpha)" | cksum)
sb_release 1.0.0
expect_completed 1.0.0
check 'pushedTagIsNotPushedAgain' "$alpha_before" "$(g ls-remote "$(split_dir zz-alpha)" | cksum)"

case_start '2つ目のパッケージの GitHub Release だけ作れずに止まる → 回し直すとそれだけが作られる'
sb_new r
sb_change 'feat: add a thing'
echo shimomo/boatrace-php-zz-beta > "$sb/inject/gh-create-fail-repo"
sb_release 1.0.0
expect_first_attempt_failed
check 'firstPackageWasAnnounced' '1.0.0' "$(cat "$(release_store zz-alpha)" 2> /dev/null | tr '\n' ' ' | sed 's/ $//')"
check 'secondPackageHasTheTagButNoRelease' '1 0' \
  "$(g ls-remote --tags --refs "$(split_dir zz-beta)" refs/tags/1.0.0 | wc -l) $(cat "$(release_store zz-beta)" 2> /dev/null | wc -l)"
rm -f "$sb"/inject/*
beta_before=$(g ls-remote "$(split_dir zz-beta)" | cksum)
sb_release 1.0.0
expect_completed 1.0.0
check 'pushedTagIsNotPushedAgain' "$beta_before" "$(g ls-remote "$(split_dir zz-beta)" | cksum)"
check 'finishedPackageIsNotAnnouncedAgain' 1 \
  "$(grep -c '^gh release create 1.0.0 --repo shimomo/boatrace-php-zz-alpha ' "$sb/gh.log" || true)"

case_start 'タグは全部届いているのに GitHub Release が1つ無い → 同じバージョンで流すと作られる'
sb_new r
sb_change 'feat: add a thing'
sb_release 1.0.0
: > "$(release_store zz-beta)"
sb_release 1.0.0
expect_completed 1.0.0
check 'outputSaysResuming' 1 "$(grep -c 'Resuming release 1.0.0' "$sb/out" || true)"

case_start '2回目以降のリリースでも、GitHub Release の作成に失敗すると止まる → 回し直すと前回を起点に作られる'
sb_new r
sb_release 1.0.0
sb_change 'feat: add a thing'
touch "$sb/inject/gh-create"
sb_release 1.1.0
expect_first_attempt_failed
rm -f "$sb"/inject/*
sb_release 1.1.0
check 'releaseSucceeds' 0 "$status"
for p in zz-alpha zz-beta; do
  check "bothReleasesAreRecorded:$p" '1.0.0 1.1.0' \
    "$(cat "$(release_store "$p")" 2> /dev/null | tr '\n' ' ' | sed 's/ $//')"
  check "notesStartFromThePreviousRelease:$p" 1 \
    "$(grep -c -x -F "gh release create 1.1.0 --repo shimomo/boatrace-php-$p --notes-start-tag 1.0.0 --generate-notes" "$sb/gh.log" | sed 's/^[1-9][0-9]*$/1/')"
done

# --- 再開ではないもの -------------------------------------------------------

case_start '出し終えたバージョンをもう一度指定（未 push のコミットがある）→ 何も変えずに止まる'
sb_new r
sb_release 1.0.0
echo local >> packages/zz-beta/src/Beta.php
g commit -q -am 'feat: a commit that was never pushed'
before=$(snapshot)
sb_release 1.0.0
expect_refused "$before" 'Tag 1.0.0 already exists'

case_start 'タグが prepare release 以外のコミットに打たれている → 何も変えずに止まる'
sb_new r
sb_change 'feat: add a thing'
g tag 1.0.0
before=$(snapshot)
sb_release 1.0.0
expect_refused "$before" 'Tag 1.0.0 already exists'

case_start 'タグの位置が main の履歴に無い → 何も変えずに止まる'
sb_new r
sb_change 'feat: add a thing'
hide_split zz-alpha
sb_release 1.0.0
expect_first_attempt_failed
show_split zz-alpha
# prepare release のコミットを main から外し、別のコミットを積む
g reset -q --hard HEAD~1
echo other >> packages/zz-beta/src/Beta.php
g commit -q -am 'feat: history went another way'
g push -q --force origin main
before=$(snapshot)
sb_release 1.0.0
expect_refused "$before" 'Tag 1.0.0 already exists'

case_start '再開しようとしたが独立リポジトリに届かない → 何も変えずに止まる'
sb_new r
sb_change 'feat: add a thing'
hide_split zz-beta
sb_release 1.0.0
expect_first_attempt_failed
before=$(snapshot)
sb_release 1.0.0
expect_refused "$before" 'Could not read the tags of shimomo/boatrace-php-zz-beta'
show_split zz-beta

case_start '通常のリリースなのに、独立リポジトリへ同じタグがもうある → 黙って飛ばさずに止まる'
sb_new r
sb_change 'feat: add a thing'
g push -q "$(split_dir zz-alpha)" HEAD:refs/tags/1.0.0
stray=$(g ls-remote "$(split_dir zz-alpha)" refs/tags/1.0.0 | cut -f1)
sb_release 1.0.0
check 'releaseFails' nonzero "$([ "$status" -ne 0 ] && echo nonzero || echo zero)"
check 'strayTagIsNotReplaced' "$stray" "$(g ls-remote "$(split_dir zz-alpha)" refs/tags/1.0.0 | cut -f1)"
check 'noReleaseIsAnnouncedForIt' 0 "$(cat "$(release_store zz-alpha)" 2> /dev/null | wc -l)"

finish
