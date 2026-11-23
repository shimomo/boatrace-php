#!/bin/sh
# bin/lib/changelog.sh
#
# CHANGELOG.md の読み書きに関するヘルパー関数群。
# release.sh から `. bin/lib/changelog.sh` で読み込んで使う想定。
# 単体では実行しない（関数定義のみ）。

set -eu

# changelog_collect_commits LAST_TAG VERSION
#
# 直前のタグ（LAST_TAG）から HEAD までのコミットを
# "- subject" 形式の箇条書きで標準出力に返す。
# LAST_TAG が空文字（= タグがまだ一つも無い初回リリース）の場合は
# リポジトリ全コミットを対象にする。
#
# VERSION 自身の "chore: prepare release VERSION" は載せない。途中で止まった
# リリースを回し直すと、前回の試行が作ったそのコミットが直前のタグより後ろに
# 居るので、放っておくと自分の節に並ぶ。
changelog_collect_commits() {
  last_tag="$1"
  version="$2"

  # log.showSignature が有効だと --pretty の出力に GPG の検証メッセージが
  # 混ざり、そのまま CHANGELOG.md に書き込まれる（初回リリースで実際に混入した）。
  # 件名だけを取りたいので明示的に抑止する。
  #
  # git log はパイプへ直接つながない。左辺の失敗が見えなくなり、
  # 箇条書きが空のまま先へ進んでしまう。
  if [ -n "$last_tag" ]; then
    subjects=$(git log --no-show-signature "${last_tag}..HEAD" --pretty='- %s')
  else
    subjects=$(git log --no-show-signature --pretty='- %s')
  fi

  printf '%s\n' "$subjects" \
    | own="- chore: prepare release $version" awk '$0 != ENVIRON["own"]'
}

# changelog_has_release VERSION
#
# CHANGELOG.md に VERSION の節（"## [VERSION] - " で始まる見出し）が
# あれば成功を返す。
changelog_has_release() {
  heading="## [$1] - " awk '
    index($0, ENVIRON["heading"]) == 1 { found = 1 }
    END { exit !found }
  ' CHANGELOG.md
}

# changelog_release_commits VERSION
#
# CHANGELOG.md の VERSION の節に載っている箇条書きを、
# changelog_collect_commits と同じ形で標準出力に返す。
changelog_release_commits() {
  heading="## [$1] - " awk '
    index($0, ENVIRON["heading"]) == 1 { inside = 1; next }
    inside && /^## / { exit }
    inside && /^- / { print }
  ' CHANGELOG.md
}

# changelog_stamp_release VERSION COMMITS
#
# CHANGELOG.md の "## Unreleased" 見出しを
# "## [VERSION] - YYYY-MM-DD" に置き換え、
# その下に COMMITS（changelog_collect_commits の出力）を書き込む。
#
# 例: "## Unreleased" の行がこうなる
#   ## [0.1.0] - 2026-09-10
#
#   - feat: foo
#   - fix: bar
#
# 見出しは残さない。タグの時点の CHANGELOG に空の "Unreleased" を
# 載せないためで、復元は changelog_ensure_unreleased_heading が
# タグの後に別コミットで行う。
# 箇条書きの後ろに空行を出さないこと。見出しの直後にもともと空行が
# あるので、出すと節の間が2行空く。
#
# 注意: "## Unreleased" 見出しが存在しない場合は何も変化しない
#       （= リリースバージョンが追記されない）ので、
#       事前に見出しの存在を保証しておくこと。
changelog_stamp_release() {
  version="$1"
  commits="$2"

  awk -v commits="$commits" -v version="$version" '
    /^## Unreleased$/ {
      print "## [" version "] - " strftime("%Y-%m-%d")
      print ""
      print commits
      next
    }
    { print }
  ' CHANGELOG.md > CHANGELOG_NEW.md

  mv CHANGELOG_NEW.md CHANGELOG.md
}

# changelog_ensure_unreleased_heading
#
# CHANGELOG.md に "## Unreleased" 見出しが無ければ、
# "# Changelog" の直後に挿入して復元する。
# changelog_stamp_release で消費された見出しを次回リリースに備えて
# 再生成するために、リリース完了後に呼び出す想定。
changelog_ensure_unreleased_heading() {
  if grep -q '^## Unreleased$' CHANGELOG.md; then
    return 0
  fi

  awk '
    /^# Changelog$/ {
      print
      print ""
      print "## Unreleased"
      next
    } { print }
  ' CHANGELOG.md > CHANGELOG_NEW.md

  mv CHANGELOG_NEW.md CHANGELOG.md
}
