#!/bin/sh
# bin/tests/test-rerun.sh [SRC]
#
# 途中で止まったリリースを同じバージョンで回し直したときの CHANGELOG を検査する。
# SRC は bin/ を持つディレクトリ（既定は本物のリポジトリ）。壊した版を試すときに差し替える。
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/lib/sandbox.sh"
. "$HERE/lib/assert.sh"

section_body() {
  awk -v heading="## [$1] - " '
    index($0, heading) == 1 { inside = 1; next }
    inside && /^## / { exit }
    inside && /^- / { print }
  '
}

consecutive_blanks() {
  awk 'p && /^$/ { n++ } { p = /^$/ } END { print n + 0 }'
}

pending() {
  # これから出すリリースの節に並ぶはずの箇条書き
  last=$(g describe --tags --abbrev=0 2> /dev/null || echo '')
  if [ -n "$last" ]; then
    g log --no-show-signature "$last..HEAD" --pretty='- %s'
  else
    g log --no-show-signature --pretty='- %s'
  fi
}

expect_released() {
  # expect_released VERSION EXPECTED_BODY
  v="$1"
  check 'releaseSucceeds' 0 "$status"
  check 'tagHasExactlyOneSectionForItsVersion' 1 \
    "$(g show "$v:CHANGELOG.md" 2> /dev/null | grep -c "^## \[$v\] - " || true)"
  check 'tagSectionListsTheCommitsSinceTheLastTag' "$2" \
    "$(g show "$v:CHANGELOG.md" 2> /dev/null | section_body "$v")"
  check 'tagHasNoUnreleasedHeading' 0 \
    "$(g show "$v:CHANGELOG.md" 2> /dev/null | grep -c '^## Unreleased$' || true)"
  check 'tagIsThePrepareReleaseCommit' "chore: prepare release $v" \
    "$(g log --no-show-signature -1 --format=%s "$v" 2> /dev/null || true)"
  check 'historyHasOnePrepareReleaseCommit' 1 \
    "$(g log --no-show-signature --format=%s | grep -c "^chore: prepare release $v\$" || true)"
  check 'updateCommitOnlyRestoresHeading' '2 0 chore: update CHANGELOG.md' \
    "$(g show --no-show-signature --numstat --format= HEAD -- CHANGELOG.md | awk '{ printf "%s %s ", $1, $2 }')$(g log --no-show-signature -1 --format=%s)"
  check 'headHasUnreleasedHeadingOnLine3' '3:## Unreleased' \
    "$(grep -n '^## Unreleased$' CHANGELOG.md | tr '\n' ' ' | sed 's/ $//')"
  check 'headHasExactlyOneSectionForItsVersion' 1 "$(grep -c "^## \[$v\] - " CHANGELOG.md || true)"
  check 'headHasNoConsecutiveBlankLines' 0 "$(consecutive_blanks < CHANGELOG.md)"
  check 'workingTreeIsClean' '' "$(g status --short)"
  check 'originMainMatchesLocalMain' "$(g rev-parse main)" "$(g ls-remote origin refs/heads/main | cut -f1)"
  check 'originHasTheTag' 1 "$(g ls-remote --tags --refs origin "refs/tags/$v" | wc -l)"
}

expect_stopped_untouched() {
  # expect_stopped_untouched HEAD_BEFORE ORIGIN_BEFORE TAGS_BEFORE CHANGELOG_BEFORE
  check 'releaseFails' nonzero "$([ "$status" -ne 0 ] && echo nonzero || echo zero)"
  check 'headIsUnchanged' "$1" "$(g rev-parse HEAD)"
  check 'originMainIsUnchanged' "$2" "$(g ls-remote origin refs/heads/main | cut -f1)"
  check 'noTagWasCreated' "$3" "$(g tag -l | tr '\n' ' ')"
  check 'changelogIsUnchanged' "$4" "$(cksum < CHANGELOG.md)"
}

# --- 止まってすぐ、何も片付けずに同じバージョンで回し直す -------------------

restore_release_files() {
  # 事前チェックの案内どおりに、書きかけを捨てる
  g restore --staged --worktree -- composer.json packages/*/composer.json packages/*/README.md CHANGELOG.md
}

interrupted_then_rerun() {
  # interrupted_then_rerun LABEL INJECT_FILE INJECT_VALUE LEFTOVER
  # LEFTOVER: uncommitted（コミットの前で止まり、書きかけが作業ツリーに残る）
  #           committed（prepare release のコミットまで済んでいる）
  case_start "$1"
  sb_new t
  sb_change 'feat: add a thing'
  body=$(pending)
  echo "$3" > "$sb/inject/$2"
  sb_release 1.0.0
  check 'firstAttemptFails' nonzero "$([ "$status" -ne 0 ] && echo nonzero || echo zero)"
  rm -f "$sb"/inject/*
  if [ "$4" = uncommitted ]; then
    # 書きかけは止まった時点で元に戻っているので、そのまま回し直せる
    check 'firstAttemptLeavesNothingBehind' '' "$(g status --short --ignored)"
  fi
  sb_release 1.0.0
  expect_released 1.0.0 "$body"
}

interrupted_then_rerun 'composer update が失敗（コミット前）→ そのまま回し直し' composer-update 1 uncommitted
interrupted_then_rerun 'prepare release の署名に失敗（コミット前）→ そのまま回し直し' gpg-fail-at 1 uncommitted
interrupted_then_rerun 'main の push が拒否（コミット後・push 前）→ そのまま回し直し' reject-main-once 1 committed
interrupted_then_rerun 'タグの署名に失敗（push 後・タグ前）→ そのまま回し直し' gpg-fail-at 2 committed

# --- 試行の間にコミットが増えた：古い節のまま出さない ---------------------------

case_start 'コミット前に止まる → コミットを足す → 回し直すと、足したコミットも載って通る'
sb_new t
sb_change 'feat: add a thing'
touch "$sb/inject/composer-update"
sb_release 1.0.0
rm -f "$sb"/inject/*
sb_change 'fix: mend the cause'
body=$(pending)
sb_release 1.0.0
expect_released 1.0.0 "$body"

case_start 'タグの前に止まる（コミットは push 済み）→ コミットを足す → 回し直しは止まる'
sb_new t
sb_change 'feat: add a thing'
echo 2 > "$sb/inject/gpg-fail-at"
sb_release 1.0.0
rm -f "$sb"/inject/*
sb_change 'fix: a late fix'
head_before=$(g rev-parse HEAD)
origin_before=$(g ls-remote origin refs/heads/main | cut -f1)
changelog_before=$(cksum < CHANGELOG.md)
sb_release 1.0.0
expect_stopped_untouched "$head_before" "$origin_before" '' "$changelog_before"
check 'messageNamesTheStaleSection' 1 "$(grep -c 'already has a section for 1.0.0' "$sb/out" || true)"

case_start '出し終えたバージョンをもう一度指定（タグは origin にだけある）→ 止まる'
sb_new t
sb_release 1.0.0
g tag -d 1.0.0 > /dev/null
sb_change 'fix: mend the thing'
head_before=$(g rev-parse HEAD)
origin_before=$(g ls-remote origin refs/heads/main | cut -f1)
changelog_before=$(cksum < CHANGELOG.md)
sb_release 1.0.0
# タグは事前チェックが origin から取ってくるので、ローカルにも戻っている
expect_stopped_untouched "$head_before" "$origin_before" '1.0.0 ' "$changelog_before"
check 'messageNamesTheExistingTag' 1 "$(grep -c 'Tag 1.0.0 already exists' "$sb/out" || true)"

# --- これまでの約束が崩れていないこと ---------------------------------------

case_start '通常のリリースを2回'
sb_new t
body=$(pending)
sb_release 1.0.0
expect_released 1.0.0 "$body"
sb_change 'feat: add a thing'
sb_change 'fix: mend the thing'
body=$(pending)
sb_release 1.1.0
expect_released 1.1.0 "$body"
check 'firstReleaseNotesHaveNoStartTag' 1 \
  "$(grep -c -x -F 'gh release create 1.0.0 --repo shimomo/boatrace-php-zz-alpha --generate-notes' "$sb/gh.log" || true)"
check 'secondReleaseNotesStartFromTheFirst' 1 \
  "$(grep -c -x -F 'gh release create 1.1.0 --repo shimomo/boatrace-php-zz-alpha --notes-start-tag 1.0.0 --generate-notes' "$sb/gh.log" || true)"

case_start 'タグの後で止まったリリースの、次のバージョン'
sb_new t
mv "$sb/remotes/shimomo/boatrace-php-zz-alpha.git" "$sb/remotes/shimomo/hidden.git"
sb_release 1.0.0
check 'interruptedAfterTheTag' 'nonzero 1.0.0' \
  "$([ "$status" -ne 0 ] && echo nonzero || echo zero) $(g ls-remote --tags --refs origin | sed 's#.*refs/tags/##' | tr '\n' ' ' | sed 's/ $//')"
mv "$sb/remotes/shimomo/hidden.git" "$sb/remotes/shimomo/boatrace-php-zz-alpha.git"
sb_change 'fix: mend the thing'
body=$(pending)
sb_release 1.1.0
expect_released 1.1.0 "$body"

# タグの後で止まったリリースを同じバージョンで回し直す場合は test-resume.sh が見る。

# --- 件名がそのまま載ること -------------------------------------------------

add_awkward_commits() {
  while IFS= read -r subject; do
    sb_change "$subject" < /dev/null
  done <<'EOF'
refactor: move Boatrace\Core\Foo to Boatrace\Types\Foo
fix: split TSV rows on \t and trim the trailing \r\n
fix: escape \\ and keep 100% of "quotes", 'apostrophes', $HOME, `backticks` & ampersands
fix: keep a trailing backslash\
EOF
}

case_start '件名のバックスラッシュや記号が、そのまま節に載る'
sb_new t
add_awkward_commits
body=$(pending)
sb_release 1.0.0
expect_released 1.0.0 "$body"
check 'awkPrintsNoWarnings' 0 "$(grep -c 'warning' "$sb/out" || true)"

case_start '件名にバックスラッシュがあっても、タグの前で止まったリリースを回し直せる'
sb_new t
add_awkward_commits
body=$(pending)
echo 2 > "$sb/inject/gpg-fail-at"
sb_release 1.0.0
rm -f "$sb"/inject/*
sb_release 1.0.0
expect_released 1.0.0 "$body"

finish
