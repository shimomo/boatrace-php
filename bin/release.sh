#!/bin/sh
# bin/release.sh
#
# モノレポ全体のリリースを実行するスクリプト。
#
# 使い方:
#   bin/release.sh <version>
#   例: bin/release.sh 0.1.0
#
# 全体の流れ:
#   1. CHANGELOG.md の "Unreleased" 見出しを今回のバージョンの見出しに
#      置き換え、対象コミット一覧を書き込む
#      （途中で止まった前回の試行の節がもうあれば、それを使い回す）
#   2. packages/*/composer.json と ルート composer.json の
#      バージョン関連フィールドを更新する
#   3. 上記の変更を "chore: prepare release" としてコミット・push する
#   4. ルートリポジトリにバージョンタグを打って push する
#   5. packages/* を1つずつ独立リポジトリへ subtree split し、
#      push & GitHub Release 作成を行う
#   6. CHANGELOG.md に次回リリース用の "Unreleased" 見出しを復元し、
#      別コミットとして push する
#
# 依存:
#   - bin/lib/changelog.sh         CHANGELOG.md の読み書き関数
#   - bin/lib/composer-merge.sh    packages/* の require/autoload等を
#                                  ルート composer.json へマージする関数
#   - bin/lib/composer-version.sh  composer.json のバージョン更新関数
#   - bin/lib/package-release.sh   パッケージ単位のリリース処理関数
#   - GitHub CLI (gh) でログイン済みであること
#   - 各 packages/<name> に対応する shimomo/boatrace-php-<name> リポジトリが
#     作成済みで、git push 権限（SSH）があること
#   - jq, composer（normalize, update）がインストールされていること

set -eu

version="${1:?Usage: bin/release.sh <version>}"

# 同じバージョンのタグが既にあるなら、何も変えないうちに止める。
# 放っておいてもステップ4の git tag で落ちるが、その時点では CHANGELOG の節と
# prepare release のコミットがもう push されている（途中で止まったリリースを
# 同じバージョンで回し直すと、空の節が二重に書かれる）。
if git rev-parse -q --verify "refs/tags/$version" > /dev/null; then
  echo "Tag $version already exists." >&2
  exit 1
fi

script_dir=$(cd "$(dirname "$0")" && pwd)

# shellcheck source=lib/changelog.sh
. "$script_dir/lib/changelog.sh"
# shellcheck source=lib/composer-merge.sh
. "$script_dir/lib/composer-merge.sh"
# shellcheck source=lib/composer-version.sh
. "$script_dir/lib/composer-version.sh"
# shellcheck source=lib/package-release.sh
. "$script_dir/lib/package-release.sh"

# ---------------------------------------------------------------------------
# 1. CHANGELOG.md に今回バージョンのセクションを書き込む
# ---------------------------------------------------------------------------
# 直前のタグ以降のコミットだけを対象にする。
# タグが一つも無い場合（プロジェクト初回リリース）は全コミットを対象にする。
#
last_tag=$(git describe --tags --abbrev=0 2>/dev/null || echo '')
commits=$(changelog_collect_commits "$last_tag" "$version")

if changelog_has_release "$version"; then
  # 今回のバージョンの節がもうある。タグを打つ前に止まった前回の試行が
  # 書いたものなので、書き足さずに使い回す。ここでもう一度書くと、
  # 節が二重になったまま公開まで進む。
  #
  # 使い回すのは、載っている箇条書きがいま集めたものと同じときだけ。
  # 試行の間にコミットが増えていると、それを載せないままタグを打つことになる。
  if [ "$(changelog_release_commits "$version")" != "$commits" ]; then
    echo "CHANGELOG.md already has a section for $version that does not match the commits since ${last_tag:-the first commit}." >&2
    echo "Remove that section (git restore CHANGELOG.md if it is uncommitted) and run again." >&2
    exit 1
  fi
else
  # 先に "## Unreleased" 見出しを保証する。前回のリリースがタグの後で止まると
  # ステップ6が走らず見出しが戻らないままになり、changelog_stamp_release は
  # 置き換える相手が無いので何も書かずに通ってしまう。
  changelog_ensure_unreleased_heading
  changelog_stamp_release "$version" "$commits"
fi

# ---------------------------------------------------------------------------
# 2. composer.json 群のバージョン情報を更新
# ---------------------------------------------------------------------------
#   - 各 packages/*/composer.json の `require` / `require-dev` のうち
#     boatrace/* への依存を `^<version>` に更新
#   - 各 packages/*/composer.json の branch-alias を `<major>.<minor>.x-dev` に更新
#   - composer_version_sync_monorepo でルートへのマージ・依存関係・フォーマットを同期
#   - ルート composer.json の `replace` は `self.version` なので触らない
composer_version_release "$version"

# ---------------------------------------------------------------------------
# 3. 変更をコミットしてpush
# ---------------------------------------------------------------------------
# ここでコミットしておかないと、後続の subtree split に
# バージョン更新が含まれないまま各パッケージへ配布されてしまう。
# CHANGELOG.md もここで入れる。外すと今回の節がステップ6のコミットへ
# 落ち、タグの時点の CHANGELOG に自分の節が載らない。
git add composer.json packages/*/composer.json packages/*/README.md CHANGELOG.md

if ! git diff --cached --quiet; then
  git commit -m "chore: prepare release $version"
fi

git push origin main

# ---------------------------------------------------------------------------
# 4. ルートリポジトリにバージョンタグを打ってpush
# ---------------------------------------------------------------------------
git tag -s "$version" -m "release $version"
git push origin "$version"

# ---------------------------------------------------------------------------
# 5. 各パッケージを独立リポジトリへ配信
# ---------------------------------------------------------------------------
# subtree split → force push → タグpush → GitHub Release作成 を
# パッケージごとに実行する。詳細は package_release_publish 内のコメント参照。
for directory in packages/*; do
  package_release_publish "$version" "$directory"
done

# ---------------------------------------------------------------------------
# 6. 次回リリースに備えて Unreleased 見出しを復元しコミット
# ---------------------------------------------------------------------------
# ステップ1の changelog_stamp_release で "## Unreleased" は
# バージョン見出しに置き換わって消費されているので、
# 次回リリースのために再度差し込んでおく。
# こちらは prepare release コミットとは別コミットとして残す
# （リリース本体の変更内容と、次回への準備作業を分離するため）。
changelog_ensure_unreleased_heading

git add CHANGELOG.md

if ! git diff --cached --quiet; then
  git commit -m 'chore: update CHANGELOG.md'
  git push origin main
fi

echo "==> Release $version completed"
