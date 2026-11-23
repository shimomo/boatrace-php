#!/bin/sh
# bin/lib/composer-merge.sh
#
# `vendor/bin/monorepo-builder merge` の置き換え。
# packages/*/composer.json の require / require-dev /
# autoload.psr-4 / autoload-dev.psr-4 をルート composer.json に
# フォールド（統合）する。
#
# 元の monorepo-builder merge の挙動（README記載）:
#   - require, require-dev, autoload, autoload-dev の4セクションを
#     全パッケージから集めてルートにマージする
#   - 同じパッケージ名が require と require-dev の両方に出てきた場合は
#     require 側を優先する
#   - 既存セクションのキー順は維持し、新規キーは末尾に追加する
#
# 当プロジェクトでの追加考慮事項（実際の composer.json diff から確認済み）:
#   - boatrace/* 同士の相互依存（root composer.json の `replace` に
#     列挙されているパッケージ名）は、ルートの require には
#     積まない。replace により内部的に解決される依存であり、
#     ルート require に積むと「外部に存在しないバージョン制約付き
#     パッケージ」を要求することになり矛盾するため。
#   - 各パッケージの composer.json の autoload/autoload-dev は
#     パッケージディレクトリ起点の相対パス（例: "src/"）で
#     書かれているため、ルートにマージする際は
#     "packages/<package>/" を前置してパスを補正する。
#   - repositories セクションはルート側で固定運用しており
#     merge対象に含める必要が無いため、このスクリプトでは触れない。
#   - ルートの require は「パッケージの require を畳んだもの」として扱い、
#     どのパッケージも要求しなくなった名前は外す。require-dev は足すだけ
#     （ルートだけが持つ開発用の道具があるため）。
#   - 止めるものが2つある。ルートの replace に載っていないパッケージと、
#     パッケージ間で食い違う制約。どちらも、ここでは正しい答えを決められない。
#
# release.sh から `. bin/lib/composer-merge.sh` で読み込んで使う想定。

set -eu

# composer_merge_packages_into_root
#
# packages/*/composer.json を走査し、require / require-dev /
# autoload.psr-4 / autoload-dev.psr-4 を集約してルート composer.json に
# 書き戻す。
composer_merge_packages_into_root() {
  # 各パッケージのcomposer.jsonに、後でautoloadパスを補正するための
  # "_pkg_dir" を仕込んでから配列にまとめてjqへ渡す。
  package_jsons=$(
    for dir in packages/*; do
      f="$dir/composer.json"
      [ -f "$f" ] || continue
      jq --arg pkg_dir "$dir" '. + {_pkg_dir: $pkg_dir}' "$f"
    done | jq -s '.'
  )

  # ルートの replace に載っていないパッケージがあれば、何も書かずに止める。
  # 下のマージは replace の名前を「内部パッケージ」として require から外すので、
  # 載っていないと、そのパッケージへの依存が外部のものとしてルートの require に
  # 積まれる。replace は手で保守しているので、パッケージを足したときに漏れる。
  unlisted=$(jq -r --argjson packages "$package_jsons" '
    (.replace // {}) as $replace
    | $packages[]
    | select((.name // "") as $name | $replace | has($name) | not)
    | "  \(._pkg_dir) (\(.name // "no name"))"
  ' composer.json)

  if [ -n "$unlisted" ]; then
    {
      echo 'These packages are missing from "replace" in the root composer.json:'
      echo "$unlisted"
      echo 'Add each of them as "<name>": "self.version" and run again.'
    } >&2
    return 1
  fi

  # 同じ依存への制約がパッケージ間で食い違っていたら、何も書かずに止める。
  # ルートに書ける制約は1つで、どれを選ぶべきかはここでは決められない。
  # 選ばせると、後に処理したパッケージの値が黙って勝つ（^8.1 と ^8.0 なら
  # ディレクトリ名の順で ^8.0 になった）。require と require-dev をまたいでも見る。
  conflicts=$(jq -r --argjson packages "$package_jsons" '
    (.replace // {} | keys) as $internal_names
    | [
        $packages[]
        | ._pkg_dir as $dir
        | ((.require // {}), (."require-dev" // {}))
        | to_entries[]
        | select(.key as $k | ($internal_names | index($k)) | not)
        | {name: .key, constraint: .value, dir: $dir}
      ]
    | group_by(.name)[]
    | select((map(.constraint) | unique | length) > 1)
    | "  \(.[0].name): "
      + (group_by(.constraint) | map("\(.[0].constraint) (\(map(.dir) | join(", ")))") | join(", "))
  ' composer.json)

  if [ -n "$conflicts" ]; then
    {
      echo 'Packages disagree on these constraints:'
      echo "$conflicts"
      echo 'Make them the same and run again.'
    } >&2
    return 1
  fi

  # ルートの require から外れるものを知らせる（外すのは下の jq）。
  removed=$(jq -r --argjson packages "$package_jsons" '
    (.replace // {} | keys) as $internal_names
    | ([$packages[] | .require // {} | keys[]] - $internal_names) as $wanted
    | .require // {}
    | keys[]
    | select(. as $name | ($wanted | index($name)) | not)
  ' composer.json)

  if [ -n "$removed" ]; then
    echo 'Removed from "require" in the root composer.json (no package requires them any more):'
    printf '%s\n' "$removed" | sed 's/^/  /'
  fi

  jq --indent 4 --argjson packages "$package_jsons" '
    # 複数オブジェクトをマージするヘルパー。同じキーは後のものが残るが、
    # 値が食い違う場合は上で止めているので、ここへ来るのは同じ値だけ。
    def merge_all: reduce .[] as $o ({}; . * $o);

    # psr-4 のパスの前にパッケージのディレクトリを付ける。
    # 値は文字列のほか、パスの配列でも書ける（Composer の仕様）。文字列と
    # 決めてかかると、配列のときに jq が足し算で落ちる。
    def prefixed($dir):
      if type == "array" then map($dir + "/" + .) else $dir + "/" + . end;

    # ルート composer.json の replace に列挙されている名前 = 自社内部パッケージ。
    # これらへの require/require-dev はルートへ積まない（replaceで解決されるため）。
    (.replace // {} | keys) as $internal_names
    |
    # require / require-dev: 内部パッケージへの依存を除外してからマージ
    ($packages
      | map(.require // {} | with_entries(select(.key as $k | ($internal_names | index($k)) | not)))
      | merge_all) as $merged_require
    |
    ($packages
      | map(."require-dev" // {} | with_entries(select(.key as $k | ($internal_names | index($k)) | not)))
      | merge_all) as $merged_require_dev
    |
    # autoload / autoload-dev: パッケージディレクトリ相対のパスを
    # "packages/<dir>/" 起点のパスへ補正してからマージ
    ($packages
      | map(
          ._pkg_dir as $dir
          | (.autoload.["psr-4"] // {})
          | with_entries(.value |= prefixed($dir))
        )
      | merge_all) as $merged_autoload
    |
    ($packages
      | map(
          ._pkg_dir as $dir
          | (."autoload-dev".["psr-4"] // {})
          | with_entries(.value |= prefixed($dir))
        )
      | merge_all) as $merged_autoload_dev
    |
    # require と require-dev の両方にあるキーは require を優先する
    ($merged_require_dev | with_entries(select(.key as $k | ($merged_require | has($k)) | not)))
      as $merged_require_dev_deduped
    |
    # require はパッケージを畳んだものにする。どのパッケージも要求しなく
    # なった名前は外す（足すだけだと、パッケージから外した依存がルートに残る）。
    # 残るキーの並びは保ち、新しいキーは末尾へ足す。
    .require = (
      ((.require // {}) | with_entries(select(.key as $k | $merged_require | has($k))))
      + $merged_require
    )
    # require-dev は足すだけにする。ルートだけが持つ開発用の道具（pint など）が
    # あり、パッケージが要求していないからといって外せない。
    # ただし require に入った名前は外す。require-dev から require へ移した依存が
    # 両方に残るのを防ぐ。
    | ."require-dev" = (
        ((."require-dev" // {}) | with_entries(select(.key as $k | $merged_require | has($k) | not)))
        + $merged_require_dev_deduped
      )
    | .autoload.["psr-4"] = ((.autoload.["psr-4"] // {}) + $merged_autoload)
    | ."autoload-dev".["psr-4"] = ((."autoload-dev".["psr-4"] // {}) + $merged_autoload_dev)
  ' composer.json > composer.json.tmp
  mv composer.json.tmp composer.json
}
