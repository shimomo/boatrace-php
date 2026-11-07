#!/bin/sh
# bin/lib/composer-version.sh
#
# composer.json のバージョン関連フィールドを更新するヘルパー群。
# 旧 `vendor/bin/monorepo-builder release` のうち
# SetCurrentMutualDependenciesReleaseWorker 相当の処理に加え、
# 旧 `monorepo-builder merge` 相当の処理（bin/lib/composer-merge.sh）も
# 呼び出す。これにより symplify/monorepo-builder への依存を完全に断つ。
#
# ルート composer.json の `replace` は `self.version` で書いているため、
# リリースごとに書き換える必要は無い（UpdateReplaceReleaseWorker 相当は持たない）。
#
# 依存: bin/lib/composer-merge.sh
#   （composer_version_sync_monorepo 内で composer_merge_packages_into_root
#    を呼ぶため、release.sh 側で本ファイルより先に
#    composer-merge.sh を source しておくこと）
#
# release.sh から `. bin/lib/composer-version.sh` で読み込んで使う想定。

set -eu

# composer_version_update_package_requires VERSION
#
# packages/*/composer.json の require / require-dev のうち、
# boatrace/* への依存（パッケージ間の相互依存）を
# `^VERSION` に更新する。
# (旧 SetCurrentMutualDependenciesReleaseWorker 相当)
#
# 例: packages/scraper/composer.json の
#     require."boatrace/core" を "^0.1" -> "^0.2.0" に更新する。
#
# 注意:
#   - boatrace/* 以外の依存（phpunit, psalm など）には触れない
#   - require / require-dev のどちらに boatrace/* が
#     書かれていても対応できるよう両方を更新対象にしている
#   - バージョン制約のフォーマットは `^x.y.z` 固定（複合制約は使わない）。
composer_version_update_package_requires() {
  version="$1"
  constraint="^$version"

  for dir in packages/*; do
    f="$dir/composer.json"
    [ -f "$f" ] || continue

    jq --indent 4 --arg v "$constraint" '
      (.require // {}) |= with_entries(
        if (.key | startswith("boatrace/")) then .value = $v else . end
      )
      | (."require-dev" // {}) |= with_entries(
          if (.key | startswith("boatrace/")) then .value = $v else . end
        )
    ' "$f" > "$f.tmp"
    mv "$f.tmp" "$f"
  done
}

# composer_version_update_package_readmes VERSION
#
# packages/*/README.md の Requirements に並ぶ `- boatrace/<name>: <制約>` を
# `^VERSION` に更新する。composer.json だけ上げると README が取り残され、
# 0.2.0 のリリースで実際に `^0.1` のまま配布された。
composer_version_update_package_readmes() {
  version="$1"

  for dir in packages/*; do
    f="$dir/README.md"
    [ -f "$f" ] || continue

    sed -E "s#^(- boatrace/[a-z-]+: ).*\$#\\1^$version#" "$f" > "$f.tmp"
    mv "$f.tmp" "$f"
  done
}

# composer_version_update_branch_alias VERSION
#
# 各 packages/*/composer.json の extra.branch-alias.dev-main を
# "<major>.<minor>.x-dev" 形式に更新する。
# 例: version=0.3.0 -> "0.3.x-dev"
#
# 通常のパッチ/マイナーリリースでは <major>.<minor> 部分は
# 変わらないことが多いが、minor/majorが上がるリリースのタイミングでは
# このタイミングで合わせて更新する必要がある。
composer_version_update_branch_alias() {
  version="$1"
  major_minor=$(echo "$version" | cut -d. -f1,2)
  alias="${major_minor}.x-dev"

  for dir in packages/*; do
    f="$dir/composer.json"
    [ -f "$f" ] || continue

    jq --indent 4 --arg v "$alias" \
      '.extra["branch-alias"]["dev-main"] = $v' \
      "$f" > "$f.tmp"
    mv "$f.tmp" "$f"
  done
}

# composer_version_sync_monorepo
#
# composer.json 群の更新後に、パッケージ側の定義をルートへ反映し、
# 依存関係・フォーマットを同期する。
# 旧 "composer sync:monorepo"（= monorepo-builder merge +
# composer update + composer normalize）の完全な置き換え。
#
#   1. composer_merge_packages_into_root
#      （bin/lib/composer-merge.sh）で packages/* の
#      require / require-dev / autoload / autoload-dev を
#      ルート composer.json にフォールドする
#      （旧 `monorepo-builder merge` 相当）
#   2. composer update でロックファイルを同期
#   3. composer normalize でフォーマットを整える
#
# インデントは 4 スペースに固定する。jq は既存のインデントを保たず
# 既定の 2 スペースで書き出し、composer normalize は既存のインデントを
# 検出して踏襲するので、指定が無いと 0.1.0 のときのように 2 へ潰れる。
#
# これにより symplify/monorepo-builder への依存を完全に断てる。
composer_version_sync_monorepo() {
  composer_merge_packages_into_root
  composer update
  composer normalize --indent-size=4 --indent-style=space
}

# composer_version_release VERSION
#
# 上記3関数をまとめて実行する、リリース時に呼び出す入口関数。
# release.sh からはこの1関数だけ呼べばよい。
composer_version_release() {
  version="$1"

  composer_version_update_package_requires "$version"
  composer_version_update_package_readmes "$version"
  composer_version_update_branch_alias "$version"
  composer_version_sync_monorepo
}
