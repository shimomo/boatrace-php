#!/bin/sh
# bin/tests/lib/sandbox.sh
#
# 実物の bin/release.sh を、外へ出られない砂場で端から端まで走らせるための部品。
# テストは本物のリリースを一切行わない（push も GitHub Release の作成もしない）。
#
#   - origin と分割先はローカルの bare リポジトリ
#   - パッケージ名は実在しないもの（zz-alpha / zz-beta）。分割先の宛先は
#     shimomo/boatrace-php-zz-* になり、万一外へ出ても存在しない
#   - git は file プロトコルしか使えない（GIT_ALLOW_PROTOCOL=file）
#   - composer / gh / gpg は PATH の先頭に置いたスタブ
#   - env -i で環境を作り直すので、本物の認証情報は見えない
#
# 読み込む側は、先に HERE（bin/tests の絶対パス）を決めておく。読み込むと次が決まる。
#
#   REAL  このリポジトリのルート
#   SRC   検査する bin/ を持つディレクトリ。テストの第1引数で差し替えられる
#         （既定は REAL。壊した版が落ちることを確かめるときに使う）
#   BASE  砂場の置き場。環境変数で渡せば、終わった後も残る（調べたいとき用）。
#         渡さなければ一時ディレクトリを作り、終わったら消す
#
# 前提: git（subtree 付き）・jq が /usr/bin か /bin にあること。
#       composer normalize を本物へ中継するケースがあるので、composer install 済みで
#       あること（vendor/ にプラグインが要る）。

REAL=$(cd "$HERE/../.." && pwd)
SRC=$(cd "${1:-$REAL}" && pwd)

# 砂場は PATH を固定して動かすので、必要な道具がそこに無ければ先に止める。
for sb_tool in git jq awk sed grep; do
  if ! env -i PATH=/usr/bin:/bin sh -c 'command -v "$1" > /dev/null' sh "$sb_tool"; then
    echo "bin/tests needs $sb_tool in /usr/bin or /bin (the sandbox runs with a fixed PATH)." >&2
    exit 1
  fi
done

if [ ! -e "$(env -i PATH=/usr/bin:/bin git --exec-path)/git-subtree" ]; then
  echo 'bin/tests needs git subtree.' >&2
  exit 1
fi

# normalize を中継するときに使う、本物の composer とその PATH。
sb_real_composer=$(command -v composer || true)
sb_real_path=$PATH

# シグナルの扱いも、環境変数と同じく作り直す。バックグラウンドで起動された
# シェルは SIGINT を無視した状態で始まり、それは子へ引き継がれて、trap でも
# 戻せない。戻さないと、テストを並べて走らせたとき（run.sh）に「Ctrl-C で
# 止まったら書きかけを戻す」が試せず、そのケースだけ落ちる。
# env が対応していなければ（GNU coreutils 8.31 より前など）、呼び出し側の
# 状態のまま走らせる。
sb_default_signals=''
if env --default-signal=INT true 2> /dev/null; then
  sb_default_signals='--default-signal=INT,TERM,HUP'
fi

if [ -n "${BASE:-}" ]; then
  mkdir -p "$BASE"
  BASE=$(cd "$BASE" && pwd)
else
  BASE=$(mktemp -d "${TMPDIR:-/tmp}/boatrace-release-tests.XXXXXX")
  trap 'rm -rf "$BASE"' EXIT
fi

sb_env() {
  # shellcheck disable=SC2086
  env -i $sb_default_signals \
    PATH="$sb/stubs:/usr/bin:/bin" \
    HOME="$sb/home" \
    SB="$sb" \
    GIT_CONFIG_NOSYSTEM=1 \
    GIT_CONFIG_GLOBAL="$sb/gitconfig" \
    GIT_ALLOW_PROTOCOL=file \
    GIT_SSH_COMMAND=/bin/false \
    GIT_TERMINAL_PROMPT=0 \
    TZ=Asia/Tokyo \
    LC_ALL=C.UTF-8 \
    "$@"
}

g() {
  sb_env git "$@"
}

sb_new() {
  # sb_new NAME
  sb="$BASE/$1"
  rm -rf "$sb"
  mkdir -p "$sb/stubs" "$sb/home" "$sb/inject" "$sb/gh-releases" \
    "$sb/remotes/shimomo" "$sb/work"

  cat > "$sb/gitconfig" <<EOF
[user]
  name = sandbox
  email = sandbox@example.invalid
[init]
  defaultBranch = main
[commit]
  gpgsign = true
[gpg]
  program = $sb/stubs/gpg
[log]
  showSignature = true
[advice]
  detachedHead = false
[url "file://$sb/remotes/"]
  insteadOf = git@github.com:
EOF

  cat > "$sb/stubs/composer" <<'EOF'
#!/bin/sh
echo "composer $*" >> "$SB/composer.log"
if [ -f "$SB/inject/composer-real-normalize" ] && [ "$1" = normalize ]; then
  # normalize だけ本物へ中継する。プラグインは本物のリポジトリの vendor にあるので
  # そこを作業ディレクトリにし、整える対象は砂場のファイルを絶対パスで渡す。
  # オプションはスクリプトが渡したものだけを使う（足すと、渡し忘れを見逃す）。
  shift
  file="$PWD/composer.json"
  flags=''
  for a in "$@"; do
    case "$a" in
      -*) flags="$flags $a" ;;
      *) file=$(realpath "$a") ;;
    esac
  done
  if [ ! -s "$SB/real-composer" ]; then
    echo 'composer is not installed, so normalize cannot be relayed.' >&2
    exit 127
  fi
  # shellcheck disable=SC2086
  exec env PATH="$(cat "$SB/real-path")" "$(cat "$SB/real-composer")" \
    --working-dir="$(cat "$SB/real-project")" --no-interaction \
    normalize $flags "$file"
fi
if [ -f "$SB/inject/composer-signal-$1" ]; then
  # 端末で Ctrl-C を押したのと同じく、リリースのシェルへ SIGINT を送る
  kill -s "$(cat "$SB/inject/composer-signal-$1")" "$PPID"
  sleep 1
  exit 1
fi
if [ -f "$SB/inject/composer-$1" ]; then
  echo "composer $1: curl error 6 while downloading https://repo.packagist.org/packages.json: Could not resolve host" >&2
  exit 1
fi
exit 0
EOF

  cat > "$sb/stubs/gh" <<'EOF'
#!/bin/sh
echo "gh $*" >> "$SB/gh.log"
repo=''
prev=''
for a in "$@"; do
  [ "$prev" = '--repo' ] && repo="$a"
  prev="$a"
done
store="$SB/gh-releases/$(echo "$repo" | tr / _)"
case "$1 $2" in
  'release view')
    # 本物と同じ返し方にする。版を指定されたらその Release があるかを、
    # 指定が無ければ最新の Release を見る。無ければ "release not found" で 1。
    case "$3" in
      --*) [ -s "$store" ] && tail -n 1 "$store" && exit 0 ;;
      *) grep -qxF -- "$3" "$store" 2> /dev/null && echo "$3" && exit 0 ;;
    esac
    echo 'release not found' >&2
    exit 1
    ;;
  'release create')
    if [ -f "$SB/inject/gh-create" ] \
      || { [ -f "$SB/inject/gh-create-fail-repo" ] && [ "$(cat "$SB/inject/gh-create-fail-repo")" = "$repo" ]; }; then
      echo 'gh: HTTP 401: Bad credentials' >&2
      exit 1
    fi
    if grep -qxF -- "$3" "$store" 2> /dev/null; then
      echo 'a release with the same tag name already exists' >&2
      exit 1
    fi
    echo "$3" >> "$store"
    ;;
esac
EOF

  cat > "$sb/stubs/gpg" <<'EOF'
#!/bin/sh
n=$(( $(cat "$SB/gpg.count" 2> /dev/null || echo 0) + 1 ))
echo "$n" > "$SB/gpg.count"
if [ -f "$SB/inject/gpg-fail-at" ] && [ "$(cat "$SB/inject/gpg-fail-at")" = "$n" ]; then
  echo 'gpg: signing failed: Inappropriate ioctl for device' >&2
  exit 2
fi
cat > /dev/null
printf '%s\n' '-----BEGIN PGP SIGNATURE-----' '' 'c2FuZGJveA==' '=AAAA' '-----END PGP SIGNATURE-----'
printf '\n[GNUPG:] BEGIN_SIGNING H8\n[GNUPG:] SIG_CREATED D 22 8 00 1700000000 0000000000000000000000000000000000000000\n' >&2
EOF
  chmod +x "$sb/stubs/composer" "$sb/stubs/gh" "$sb/stubs/gpg"
  echo "$REAL" > "$sb/real-project"
  echo "$sb_real_composer" > "$sb/real-composer"
  echo "$sb_real_path" > "$sb/real-path"

  for r in origin shimomo/boatrace-php-zz-alpha shimomo/boatrace-php-zz-beta; do
    g init -q --bare "$sb/remotes/$r.git"
  done

  cat > "$sb/remotes/origin.git/hooks/pre-receive" <<EOF
#!/bin/sh
inject='$sb/inject'
while read -r old new ref; do
  case "\$ref" in
    refs/heads/main)
      n=\$(( \$(cat "\$inject/../main-push.count" 2> /dev/null || echo 0) + 1 ))
      echo "\$n" > "\$inject/../main-push.count"
      if [ -f "\$inject/reject-main-at" ] && [ "\$(cat "\$inject/reject-main-at")" = "\$n" ]; then
        echo 'sandbox: push to main rejected' >&2
        exit 1
      fi
      if [ -f "\$inject/reject-main-once" ]; then
        rm -f "\$inject/reject-main-once"
        echo 'sandbox: push to main rejected' >&2
        exit 1
      fi
      ;;
    refs/tags/*)
      if [ -f "\$inject/reject-tag-once" ]; then
        rm -f "\$inject/reject-tag-once"
        echo 'sandbox: tag push rejected' >&2
        exit 1
      fi
      ;;
  esac
done
EOF
  chmod +x "$sb/remotes/origin.git/hooks/pre-receive"

  cd "$sb/work"
  g init -q .
  g remote add origin "$sb/remotes/origin.git"

  mkdir -p bin
  cp -r "$SRC/bin/release.sh" "$SRC/bin/merge.sh" "$SRC/bin/lib" bin/
  printf '%s\n' '/vendor/' 'composer.lock' '*.tmp' > .gitignore
  printf '%s\n' '# Changelog' '' '## Unreleased' > CHANGELOG.md

  cat > composer.json <<'EOF'
{
    "name": "shimomo/sandbox",
    "license": "MIT",
    "type": "library",
    "require": {
        "php": "^8.4",
        "symfony/console": "^8.0"
    },
    "require-dev": {
        "phpunit/phpunit": "^13.2"
    },
    "replace": {
        "boatrace/zz-alpha": "self.version",
        "boatrace/zz-beta": "self.version"
    },
    "autoload": {
        "psr-4": {
            "Boatrace\\ZzAlpha\\": "packages/zz-alpha/src/",
            "Boatrace\\ZzBeta\\": "packages/zz-beta/src/"
        }
    },
    "autoload-dev": {
        "psr-4": {
            "Boatrace\\ZzAlpha\\Tests\\": "packages/zz-alpha/tests/",
            "Boatrace\\ZzBeta\\Tests\\": "packages/zz-beta/tests/"
        }
    }
}
EOF

  for p in alpha beta; do
    cap=$(echo "$p" | sed 's/^./\U&/')
    mkdir -p "packages/zz-$p/src"
    echo "<?php // $p" > "packages/zz-$p/src/$cap.php"
    sed -e "s/@P@/$p/g" -e "s/@CAP@/$cap/g" > "packages/zz-$p/composer.json" <<'EOF'
{
    "name": "boatrace/zz-@P@",
    "license": "MIT",
    "type": "library",
    "require": {
        "php": "^8.4",
        "boatrace/zz-beta": "^0.0.1",
        "symfony/console": "^8.0"
    },
    "require-dev": {
        "phpunit/phpunit": "^13.2"
    },
    "autoload": {
        "psr-4": {
            "Boatrace\\Zz@CAP@\\": "src/"
        }
    },
    "autoload-dev": {
        "psr-4": {
            "Boatrace\\Zz@CAP@\\Tests\\": "tests/"
        }
    },
    "extra": {
        "branch-alias": {
            "dev-main": "0.0.x-dev"
        }
    }
}
EOF
    printf '%s\n' "# zz-$p" '' '## Requirements' '' '- PHP: ^8.4' '- boatrace/zz-beta: ^0.0.1' > "packages/zz-$p/README.md"
    if [ "$p" = beta ]; then
      # beta は自分自身には依存しない
      # 行ごと消すと "name" まで消えるので、依存だけを外す
      jq --indent 4 'del(.require["boatrace/zz-beta"])' packages/zz-beta/composer.json > packages/zz-beta/composer.json.new
      mv packages/zz-beta/composer.json.new packages/zz-beta/composer.json
      grep -v 'boatrace/zz-beta' packages/zz-beta/README.md > packages/zz-beta/README.md.new
      mv packages/zz-beta/README.md.new packages/zz-beta/README.md
    fi
    jq -e . "packages/zz-$p/composer.json" > /dev/null
  done

  g add -A
  g commit -q -m 'chore: initial commit'
  g push -q origin main
  : > "$sb/composer.log"
  : > "$sb/gh.log"
}

sb_change() {
  # sb_change SUBJECT
  # echo は dash だとバックスラッシュを解釈するので使わない
  printf '%s\n' "$1" >> packages/zz-beta/src/Beta.php
  g commit -q -am "$1"
  g push -q origin main
}

sb_release() {
  # sb_release ARGS... → status, 出力は $sb/out
  echo 0 > "$sb/gpg.count"
  echo 0 > "$sb/main-push.count"
  set +e
  sb_env sh bin/release.sh "$@" > "$sb/out" 2>&1
  status=$?
  set -e
}

# 砂場の外へ出られないことを、何かを走らせる前に確かめる。insteadOf を外した
# 設定で GitHub の URL を叩き、git 自身がプロトコルを拒否することを見る。
# ここが通らないなら、テストは本物のリポジトリへ push しうるので続けない。
sb_guard_check() {
  sb="$BASE/guard"
  rm -rf "$sb"
  mkdir -p "$sb/stubs" "$sb/home"
  : > "$sb/gitconfig"

  if sb_guard_out=$(sb_env git ls-remote git@github.com:shimomo/boatrace-php-zz-alpha.git 2>&1); then
    echo "GUARD FAILED: the sandbox reached GitHub: $sb_guard_out" >&2
    exit 99
  fi

  case "$sb_guard_out" in
    *'not allowed'*) ;;
    *)
      echo "GUARD FAILED: refused for an unexpected reason: $sb_guard_out" >&2
      exit 99
      ;;
  esac
}

sb_guard_check
