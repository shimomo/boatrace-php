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
#   0. 始める前の検査（バージョンの形・ブランチ・未コミットの変更・
#      origin とのずれ・タグの重複）。何も変えないうちに止める
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
# 途中で止まったら、同じバージョンでもう一度流す。
#   - タグの前で止まった場合は、最初からやり直す（prepare release のコミットが
#     もうあれば、その節を使い回す）
#   - タグの後で止まった場合は、続きから再開する（1〜4 を飛ばし、まだタグの
#     無い独立リポジトリだけへ配信して、6 を済ませる）
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

# リリースが書き換えてコミットするファイル。下の事前チェックとステップ3の
# git add で同じ並びを使う。片方にだけ足すと、未コミットの変更がまた
# prepare release のコミットへ巻き込まれる。
# グロブを展開させるので、使うときはクオートしない。
release_files='composer.json packages/*/composer.json packages/*/README.md CHANGELOG.md'

script_dir=$(cd "$(dirname "$0")" && pwd)

# shellcheck source=lib/changelog.sh
. "$script_dir/lib/changelog.sh"
# shellcheck source=lib/composer-merge.sh
. "$script_dir/lib/composer-merge.sh"
# shellcheck source=lib/composer-version.sh
. "$script_dir/lib/composer-version.sh"
# shellcheck source=lib/package-release.sh
. "$script_dir/lib/package-release.sh"

# release_is_complete VERSION
#
# VERSION のリリースが最後まで済んでいれば成功を返す。済んでいるとは、
# origin の main の CHANGELOG に "## Unreleased" が戻っていて（ステップ6）、
# すべてのパッケージの独立リポジトリにタグがあること（ステップ5）。
# 事前チェックの git fetch の後で呼ぶ（origin/main が古いと見誤る）。
release_is_complete() {
  git show origin/main:CHANGELOG.md | grep -q '^## Unreleased$' || return 1

  for directory in packages/*; do
    package_release_is_published "$1" "$directory" || return 1
  done
}

# release_discard_unfinished STATUS
#
# 途中で止まったとき（STATUS が 0 以外）、リリースが書きかけたファイルを
# 始める前の状態へ戻す。残しておくと次の実行が事前チェックで止まり、
# 手で捨てることになる。
#
# 戻すのは HEAD の内容へ、なので、コミット済みのものには触れない。
# prepare release のコミットの後で止まった場合、そのコミットは残る。
#
# jq や awk が書き出す途中のファイルも消す。*.tmp は .gitignore の対象で、
# 残っていても git status には出ない。
release_discard_unfinished() {
  if [ "$1" -ne 0 ]; then
    # shellcheck disable=SC2086
    if [ -n "$(git status --porcelain --untracked-files=no -- $release_files)" ]; then
      git restore --staged --worktree -- $release_files || true
      echo 'Release stopped. The files it had started to rewrite were put back.' >&2
    fi

    rm -f CHANGELOG_NEW.md composer.json.tmp \
      packages/*/composer.json.tmp packages/*/README.md.tmp
  fi

  exit "$1"
}

# ---------------------------------------------------------------------------
# 0. 始める前の検査
# ---------------------------------------------------------------------------
# どれも、何も変えないうちに止めるためのもの。ここを通った後で止まると、
# 書きかけの CHANGELOG や push 済みのコミットが残る。

# バージョンは x.y.z だけを受け付ける。この値はそのままタグ名・依存の制約
# （^x.y.z）・branch-alias（x.y.x-dev）になり、形が崩れていても最後まで
# 通ってしまう（"foo" なら ^foo と foo.x-dev が配られる）。
if ! expr "X$version" : 'X[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*$' > /dev/null; then
  echo "Version must look like 1.2.3, got: $version" >&2
  exit 1
fi

# main の上でだけ出す。ステップ3は「いまのブランチへコミットして main を push」
# なので、別のブランチに居ると main は動かないまま、タグと分割先だけが
# そのブランチの内容で公開される（エラーにもならない）。
branch=$(git symbolic-ref --short -q HEAD || echo '')
if [ "$branch" != main ]; then
  echo "Releases are cut from main, but the current branch is ${branch:-detached}." >&2
  exit 1
fi

# リリースがコミットするファイルに、未コミットの変更が無いこと。ステップ3の
# git add がそのまま拾い、prepare release のコミットに混ざって分割先まで
# 配られる。途中で止まったリリースは書きかけを自分で戻すが、強制終了された
# ときは残ることがあり、それもここで止まる。
# shellcheck disable=SC2086
dirty=$(git status --porcelain --untracked-files=all -- $release_files)
if [ -n "$dirty" ]; then
  {
    echo 'These files have uncommitted changes that the release commit would pick up:'
    echo "$dirty"
    echo 'Commit them, or discard them (a release that was killed can leave its edits behind):'
    echo "  git restore --staged --worktree -- $release_files"
  } >&2
  exit 1
fi

# origin の main より遅れていないこと。遅れているとステップ3の push が拒否され、
# prepare release のコミットがローカルにだけ残る。
# タグも一緒に取ってくる。別の場所で打たれたタグは、取ってこないと
# 下の重複チェックから見えない。
git fetch --quiet --tags origin main
if ! git merge-base --is-ancestor origin/main HEAD; then
  echo 'main is behind origin/main. Pull first.' >&2
  exit 1
fi

# 同じバージョンのタグが既にあるとき。
#
# タグの後で止まった今回のリリースなら、続きから再開する。そう言えるのは、
# タグが今回の prepare release のコミットに打たれていて、それが HEAD の履歴に
# あり、まだ済んでいない手順が残っているときだけ。
#
# それ以外（出し終えたバージョンをもう一度指定した・別のコミットに同じ名前の
# タグがある）は、何も変えずに止める。放っておいてもステップ4の git tag で
# 落ちるが、その時点では CHANGELOG の節と prepare release のコミットがもう
# push されている。
resuming=0
if git rev-parse -q --verify "refs/tags/$version" > /dev/null; then
  if [ "$(git log --no-show-signature -1 --format=%s "$version^{commit}")" != "chore: prepare release $version" ] \
    || ! git merge-base --is-ancestor "$version^{commit}" HEAD \
    || release_is_complete "$version"; then
    echo "Tag $version already exists." >&2
    exit 1
  fi

  resuming=1
  echo "==> Resuming release $version"
fi

# ここから先で止まったら、書きかけたファイルを元へ戻す。
#
# 事前チェックより前に仕掛けないこと。未コミットの変更が無いと確かめる前に
# 戻すと、手元の作業を消す。
#
# シグナルは exit に読み替える。dash はシグナルで落ちるときに EXIT の
# トラップを呼ばないので、そのままだと Ctrl-C で書きかけが残る。
trap 'release_discard_unfinished "$?"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

# ---------------------------------------------------------------------------
# 1. CHANGELOG.md に今回バージョンのセクションを書き込む
# ---------------------------------------------------------------------------
# 直前のタグ以降のコミットだけを対象にする。
# タグが一つも無い場合（プロジェクト初回リリース）は全コミットを対象にする。
#
last_tag=$(git describe --tags --abbrev=0 2>/dev/null || echo '')
commits=$(changelog_collect_commits "$last_tag" "$version")

if [ "$resuming" -eq 1 ]; then
  # 再開のときは書かない。節はタグの時点でもう入っている。直前のタグが
  # 今回のバージョン自身になっているので、集め直した箇条書きとは合わない。
  :
elif changelog_has_release "$version"; then
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
#
# 再開のときは飛ばす。書き換えはタグの時点でもう入っていて、
# composer update をもう一度走らせる理由が無い。
if [ "$resuming" -eq 0 ]; then
  composer_version_release "$version"
fi

# ---------------------------------------------------------------------------
# 3. 変更をコミットしてpush
# ---------------------------------------------------------------------------
# ここでコミットしておかないと、後続の subtree split に
# バージョン更新が含まれないまま各パッケージへ配布されてしまう。
# CHANGELOG.md もここで入れる（release_files に含めてある）。外すと今回の節が
# ステップ6のコミットへ落ち、タグの時点の CHANGELOG に自分の節が載らない。
#
# 再開のときもここは通す。コミットするものは無いが、push は要る。
# 前回がステップ6の push で止まっていた場合、見出しを戻すコミットは
# ローカルにだけあり、ここで origin へ届く。
# shellcheck disable=SC2086
git add $release_files

if ! git diff --cached --quiet; then
  git commit -m "chore: prepare release $version"
fi

git push origin main

# ---------------------------------------------------------------------------
# 4. ルートリポジトリにバージョンタグを打ってpush
# ---------------------------------------------------------------------------
# 再開のときは打ち直さない（タグはもうある）。push はやり直す。前回がタグの
# push で止まっていた場合に届けるためで、届いていれば何も起きない。
if [ "$resuming" -eq 0 ]; then
  git tag -s "$version" -m "release $version"
fi

git push origin "$version"

# ---------------------------------------------------------------------------
# 5. 各パッケージを独立リポジトリへ配信
# ---------------------------------------------------------------------------
# subtree split → force push → タグpush → GitHub Release作成 を
# パッケージごとに実行する。詳細は package_release_publish 内のコメント参照。
#
# 再開のときは、前回の実行でもう公開できているパッケージを飛ばす。
# 再開でないのに独立リポジトリへ同じタグがあるのは異常なので、飛ばさずに
# package_release_publish のタグの push で落とす。
for directory in packages/*; do
  if [ "$resuming" -eq 1 ] && package_release_is_published "$version" "$directory"; then
    echo "==> $(basename "$directory") (already published)"
    continue
  fi

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
