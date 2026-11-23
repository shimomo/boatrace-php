#!/bin/sh
# bin/lib/package-release.sh
#
# packages/* 配下の1パッケージを、独立した GitHub リポジトリ
# （shimomo/boatrace-php-<package>）へ subtree split で切り出し、
# push & GitHub Release 作成までを行うヘルパー。
# release.sh から `. bin/lib/package-release.sh` で読み込んで使う想定。

set -eu

# package_release_locate DIRECTORY
#
# DIRECTORY から、以降の関数が使う package / repository / remote を決める。
package_release_locate() {
  package=$(basename "$1")
  # composer パッケージ名は boatrace/<package> だが、GitHub 上は
  # shimomo 配下に boatrace-php- プレフィックス付きで置く。
  repository="shimomo/boatrace-php-$package"
  remote="git@github.com:$repository.git"
}

# package_release_has_tag VERSION DIRECTORY
#
# そのパッケージの独立リポジトリに VERSION のタグがもうあれば成功を返す。
#
# 「タグが無い」と「リポジトリに届かない」を取り違えないこと。
# git ls-remote --exit-code は前者で 2、後者で 128 を返す。後者を未公開と読むと、
# 届かないリポジトリへ公開をやり直そうとして、もっと先で落ちる。
package_release_has_tag() {
  package_release_locate "$2"

  ls_remote_status=0
  git ls-remote --exit-code --tags "$remote" "refs/tags/$1" > /dev/null \
    || ls_remote_status=$?

  case "$ls_remote_status" in
    0) return 0 ;;
    2) return 1 ;;
    *)
      echo "Could not read the tags of $repository." >&2
      exit "$ls_remote_status"
      ;;
  esac
}

# package_release_has_release VERSION DIRECTORY
#
# そのパッケージの独立リポジトリに VERSION の GitHub Release がもうあれば
# 成功を返す。
#
# gh は「無い」も「読めなかった」も同じ終了コードで返すので、ここでは区別
# しない。読めなかっただけなら、この後の gh release create が同じ理由で落ちる。
package_release_has_release() {
  package_release_locate "$2"

  gh release view "$1" --repo "$repository" > /dev/null 2>&1
}

# package_release_is_published VERSION DIRECTORY
#
# そのパッケージの公開が済んでいれば（タグも GitHub Release もあれば）
# 成功を返す。リリースが最後まで済んだかを release.sh が判断するのに使う。
package_release_is_published() {
  package_release_has_tag "$1" "$2" && package_release_has_release "$1" "$2"
}

# package_release_push_split VERSION DIRECTORY
#
# packages/<name> 配下だけの履歴を切り出し、独立リポジトリの main と
# VERSION のタグとして push する。
#   1. packages/<name> 配下だけの履歴を git subtree split で取り出す
#   2. 取り出したコミットを署名付きタグで固定する（一時タグ）
#   3. 独立リポジトリの main ブランチへ force push
#      （force push前提の運用のため、各パッケージリポジトリの
#        main ブランチ履歴は毎回ルートの最新状態で上書きされる）
#   4. 一時タグを正式なバージョンタグとして独立リポジトリへ push
#   5. ローカルの一時タグ/作業ブランチを掃除
package_release_push_split() {
  version="$1"
  directory="$2"

  package_release_locate "$directory"

  # --- 1. packages/<name> 配下だけの履歴を切り出す --------------------
  # 途中で止まった前回の実行が、作業用のブランチと一時タグを残していることが
  # ある。残っていると下の git tag が "already exists" で落ちるので、先に片付ける。
  tmp_tag="pkg-${package}-${version}"
  git tag -d "$tmp_tag" > /dev/null 2>&1 || true
  git branch -D "split-$package" > /dev/null 2>&1 || true

  # 切り出すのは HEAD ではなく VERSION のタグの位置。再開のときは HEAD が
  # タグより先へ進んでいることがあり、HEAD から切り出すと、次のリリースに
  # 入るはずの変更が VERSION として配られる。
  commit=$(git subtree split \
    --prefix="$directory" \
    --branch="split-$package" \
    "$version^{commit}")

  # --- 2. 切り出したコミットに署名付き一時タグを打つ -------------------
  # tmp_tag はあくまでローカル作業用の名前。リモートには
  # ステップ4で "refs/tags/${version}" という別名で push する。
  git tag -s "$tmp_tag" "$commit" -m "Release $version"

  # --- 3. 独立リポジトリの main を force push ------------------------
  # subtree split は毎回ルート側の現在の履歴から再構成するため、
  # 過去のpush内容と完全一致しないことがある。
  # よって force push が前提の運用になっている。
  # push 元が生の SHA なので、宛先は refs/heads/ まで書く。"main" だけだと
  # git はリモートの既存 main から補完しようとし、空のリポジトリでは失敗する。
  git push "$remote" "$commit:refs/heads/main" --force

  # --- 4. バージョンタグを独立リポジトリへ push -----------------------
  git push "$remote" "refs/tags/${tmp_tag}:refs/tags/${version}"

  # --- 5. ローカルの一時タグ・作業ブランチを掃除 -----------------------
  git tag -d "$tmp_tag"
  git branch -D "split-$package"
}

# package_release_create_release VERSION DIRECTORY PREV_VERSION
#
# 独立リポジトリに VERSION の GitHub Release を作る。
#
# PREV_VERSION（直前の Latest リリースのタグ）があれば --notes-start-tag で
# 比較起点を明示する。これをやらないと GitHub 側の自動推測が失敗し、
# "Full Changelog: .../commits/<version>" という単一コミットへのリンクに
# なってしまうケースがある（GitHub は祖先関係にあるタグでも、Release として
# 公開されていないと自動では前回リリースとして認識できないことがある）。
#
# 失敗は握りつぶさない。握りつぶすと、Release が無いまま "completed" と出て、
# 気付く手がかりが流れていく gh のエラー行だけになる。ここで止まっても、
# 同じバージョンでもう一度流せば、足りない Release だけが作られる。
package_release_create_release() {
  version="$1"
  prev_version="$3"

  package_release_locate "$2"

  if [ -n "$prev_version" ]; then
    gh release create "$version" \
      --repo "$repository" \
      --notes-start-tag "$prev_version" \
      --generate-notes
  else
    # 初回リリースなど、比較対象となる前回タグが存在しない場合
    gh release create "$version" \
      --repo "$repository" \
      --generate-notes
  fi
}

# package_release_publish VERSION DIRECTORY [ONLY_MISSING]
#
# 1パッケージ分のリリース処理一式。
#   1. そのパッケージリポジトリの「現在のLatestリリースタグ」を控える
#      （Full Changelog の比較起点として後で使うため。
#       これを取得し損ねると、GitHub側の自動推測に頼ることになり、
#       過去に "Full Changelog: commits/x.y.z" という
#       単一コミットへの壊れたリンクになる不具合が再発する）
#   2. 履歴を切り出して独立リポジトリへ push する（package_release_push_split）
#   3. GitHub Release を作成する（package_release_create_release）
#
# ONLY_MISSING が 1 のとき（途中で止まったリリースの再開）は、2 と 3 のうち
# もう済んでいるものを飛ばす。0 のとき（通常）は確かめずに両方行う。
# 通常のリリースなのに独立リポジトリへ同じタグがもうあるのは異常なので、
# 飛ばさずにタグの push で落とす。
#
# 引数:
#   VERSION      リリースするバージョン文字列（例: 0.1.0）
#   DIRECTORY    パッケージのディレクトリパス（例: packages/scraper-boatcast）
#   ONLY_MISSING 1 なら済んでいる手順を飛ばす（省略時は 0）
package_release_publish() {
  version="$1"
  directory="$2"
  only_missing="${3:-0}"

  package_release_locate "$directory"

  echo "==> ${package}"

  # --- 1. 直前のLatestリリースタグを記録 -----------------------------
  # 今回の Release を作る前に取得すること。作った後に取ると、今回のバージョン
  # 自身を拾ってしまう（タグを push しただけでは Latest は変わらない）。
  # まだ一度もリリースしていないパッケージでは空文字になる
  # （gh release view が失敗するので || echo '' で握りつぶす）。
  prev_version=$(gh release view \
    --repo "$repository" \
    --json tagName \
    --jq .tagName 2>/dev/null || echo '')

  untouched=1

  # --- 2. 履歴を切り出して独立リポジトリへ push ------------------------
  if [ "$only_missing" -eq 0 ] || ! package_release_has_tag "$version" "$directory"; then
    package_release_push_split "$version" "$directory"
    untouched=0
  fi

  # --- 3. GitHub Release を作成 ---------------------------------------
  if [ "$only_missing" -eq 0 ] || ! package_release_has_release "$version" "$directory"; then
    package_release_create_release "$version" "$directory" "$prev_version"
    untouched=0
  fi

  if [ "$untouched" -eq 1 ]; then
    echo '    already published'
  fi
}
