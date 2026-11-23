#!/bin/sh
# bin/tests/test-manifests.sh [SRC]
#
# リリースが packages/*/composer.json を書き換えるところを検査する。
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/lib/sandbox.sh"
. "$HERE/lib/assert.sh"

edit_manifest() {
  # edit_manifest PACKAGE JQ_FILTER SUBJECT
  jq --indent 4 "$2" "packages/$1/composer.json" > x
  mv x "packages/$1/composer.json"
  g commit -q -am "$3"
  g push -q origin main
}

keys_at() {
  # keys_at REF PACKAGE
  g show "$1:packages/$2/composer.json" 2> /dev/null | jq -r 'keys_unsorted | join(",")'
}

expect_published() {
  check 'releaseSucceeds' 0 "$status"
  check 'tagIsThePrepareReleaseCommit' "chore: prepare release $1" \
    "$(g log --no-show-signature -1 --format=%s "$1" 2> /dev/null || true)"
  check 'workingTreeIsClean' '' "$(g status --short)"
  check 'noLeftoverTemporaryFiles' 0 "$(g status --short --ignored | grep -c '^!!' || true)"
}

# --- セクションを持たないパッケージ -----------------------------------------

case_start 'require-dev を持たないパッケージがあってもリリースできる'
sb_new m
edit_manifest zz-beta 'del(."require-dev")' 'chore: drop require-dev from zz-beta'
keys_before=$(jq -r 'keys_unsorted | join(",")' packages/zz-beta/composer.json)
sb_release 1.0.0
expect_published 1.0.0
check 'requireDevIsNotAdded' "$keys_before" "$(keys_at 1.0.0 zz-beta)"
check 'siblingConstraintIsStillBumped' '^1.0.0' \
  "$(g show 1.0.0:packages/zz-alpha/composer.json 2> /dev/null | jq -r '.require["boatrace/zz-beta"]')"
check 'branchAliasIsBumped' '1.0.x-dev' \
  "$(g show 1.0.0:packages/zz-beta/composer.json 2> /dev/null | jq -r '.extra["branch-alias"]["dev-main"]')"

case_start 'require を持たないパッケージがあってもリリースできる'
sb_new m
edit_manifest zz-beta 'del(.require)' 'chore: drop require from zz-beta'
keys_before=$(jq -r 'keys_unsorted | join(",")' packages/zz-beta/composer.json)
sb_release 1.0.0
expect_published 1.0.0
check 'requireIsNotAdded' "$keys_before" "$(keys_at 1.0.0 zz-beta)"

case_start 'require も require-dev も持たないパッケージがあってもリリースできる'
sb_new m
edit_manifest zz-beta 'del(.require, ."require-dev")' 'chore: drop both sections from zz-beta'
keys_before=$(jq -r 'keys_unsorted | join(",")' packages/zz-beta/composer.json)
sb_release 1.0.0
expect_published 1.0.0
check 'neitherSectionIsAdded' "$keys_before" "$(keys_at 1.0.0 zz-beta)"

# --- リリース後の composer.json が CI の Lint を通る形であること -------------

lint() {
  # CI の Lint と同じ検査を、タグの時点のファイルにかける。通れば 0。
  mkdir -p "$sb/lint"
  g show "$1" > "$sb/lint/composer.json"
  ( cd "$REAL" && composer normalize --dry-run --no-check-lock --no-interaction "$sb/lint/composer.json" > "$sb/lint/out" 2>&1 )
}

case_start 'extra を持たないパッケージ: branch-alias を足した後も composer normalize の検査を通る'
sb_new m
edit_manifest zz-beta 'del(.extra) | ."$schema" = "https://getcomposer.org/schema.json"' 'chore: drop extra from zz-beta'
touch "$sb/inject/composer-real-normalize"
sb_release 1.0.0
expect_published 1.0.0
check 'branchAliasIsAdded' '1.0.x-dev' \
  "$(g show 1.0.0:packages/zz-beta/composer.json 2> /dev/null | jq -r '.extra["branch-alias"]["dev-main"]')"
for f in composer.json packages/zz-alpha/composer.json packages/zz-beta/composer.json; do
  set +e
  lint "1.0.0:$f"
  lint_status=$?
  set -e
  check "passesTheLintCheck:$f" 0 "$lint_status"
  check "keepsFourSpaceIndentation:$f" 1 \
    "$(g show "1.0.0:$f" 2> /dev/null | sed -n 2p | grep -c '^    "' || true)"
done
check 'everyManifestIsNormalized' '3' "$(grep -c '^composer normalize' "$sb/composer.log" || true)"

case_start 'パッケージのディレクトリに composer.lock が残っていても、止まらず、ロックにも触らない'
sb_new m
edit_manifest zz-beta 'del(.extra) | ."$schema" = "https://getcomposer.org/schema.json"' 'chore: drop extra from zz-beta'
cat > packages/zz-beta/composer.lock <<'EOF'
{
    "_readme": [],
    "content-hash": "00000000000000000000000000000000",
    "packages": [],
    "packages-dev": [],
    "aliases": [],
    "minimum-stability": "stable",
    "stability-flags": {},
    "prefer-stable": false,
    "prefer-lowest": false,
    "platform": {},
    "platform-dev": {},
    "plugin-api-version": "2.6.0"
}
EOF
lock_before=$(cksum < packages/zz-beta/composer.lock)
touch "$sb/inject/composer-real-normalize"
sb_release 1.0.0
check 'releaseSucceeds' 0 "$status"
check 'lockFileIsLeftAlone' "$lock_before" "$(cksum < packages/zz-beta/composer.lock)"
set +e
lint "1.0.0:packages/zz-beta/composer.json"
lint_status=$?
set -e
check 'passesTheLintCheck' 0 "$lint_status"

case_start 'bin/merge.sh: 2スペースで書かれたパッケージの composer.json も4スペースに整う'
sb_new m
jq --indent 2 . packages/zz-beta/composer.json > x && mv x packages/zz-beta/composer.json
g commit -q -am 'chore: reindent a manifest with two spaces'
touch "$sb/inject/composer-real-normalize"
set +e
sb_env sh bin/merge.sh > "$sb/out" 2>&1
status=$?
set -e
check 'mergeSucceeds' 0 "$status"
check 'manifestIsReindentedWithFourSpaces' 1 "$(sed -n 2p packages/zz-beta/composer.json | grep -c '^    "' || true)"

# --- 書き換える範囲 ---------------------------------------------------------

case_start 'require-dev にある boatrace/* も上がり、ほかの依存は変わらない'
sb_new m
edit_manifest zz-alpha '."require-dev"["boatrace/zz-beta"] = "^0.0.1"' 'chore: require zz-beta for development too'
sb_release 1.0.0
expect_published 1.0.0
check 'requireAndRequireDevAfterTheRelease' \
  '{"php":"^8.4","boatrace/zz-beta":"^1.0.0","symfony/console":"^8.0"} {"phpunit/phpunit":"^13.2","boatrace/zz-beta":"^1.0.0"}' \
  "$(g show 1.0.0:packages/zz-alpha/composer.json 2> /dev/null | jq -c '.require, ."require-dev"' | tr '\n' ' ' | sed 's/ $//')"

case_start '実物の composer.json 群: いまのバージョンへの書き換えは無変更、次のバージョンは意図した行だけ'
sb_new m
rm -rf packages composer.json
mkdir packages
cp "$REAL/composer.json" .
for d in "$REAL"/packages/*; do
  mkdir -p "packages/$(basename "$d")"
  cp "$d/composer.json" "$d/README.md" "packages/$(basename "$d")/"
done
g add -A
g commit -q -m 'chore: import the real manifests'
current=$(jq -r '.extra["branch-alias"]["dev-main"]' packages/core/composer.json | sed 's/\.x-dev$/.0/')
rewrite() {
  sb_env sh -c '. bin/lib/composer-merge.sh; . bin/lib/composer-version.sh
    composer_version_update_package_requires "$1"
    composer_version_update_package_readmes "$1"
    composer_version_update_branch_alias "$1"' sh "$1" > "$sb/out" 2>&1
}
set +e
rewrite "$current"
status=$?
set -e
check 'rewriteToTheCurrentVersionSucceeds' 0 "$status"
check 'rewriteToTheCurrentVersionChangesNothing' '' "$(g status --short)"
set +e
rewrite 9.8.7
status=$?
set -e
check 'rewriteToTheNextVersionSucceeds' 0 "$status"
check 'onlyConstraintsAndAliasesChange' '' \
  "$(g diff --no-color -U0 | grep -E '^[+-][^+-]' | grep -v -E '^[+-] +"boatrace/[a-z-]+": "\^[0-9.]+",?$|^[+-] +"dev-main": "[0-9.]+\.x-dev"$|^[+-]- boatrace/[a-z-]+: \^[0-9.]+$' || true)"
check 'everySiblingConstraintIsBumped' 0 \
  "$(cat packages/*/composer.json | jq -r '(.require // {}), (."require-dev" // {}) | to_entries[] | select(.key | startswith("boatrace/")) | .value' | grep -c -v -x -F '^9.8.7' || true)"
check 'everyBranchAliasIsBumped' 0 \
  "$(cat packages/*/composer.json | jq -r '.extra["branch-alias"]["dev-main"]' | grep -c -v -x -F '9.8.x-dev' || true)"

# --- ルートの replace に載っていないパッケージ -------------------------------

add_gamma() {
  # zz-gamma を足し、zz-alpha から依存させる。ルートの replace には載せない。
  cp -r packages/zz-beta packages/zz-gamma
  sed -i 's/zz-beta/zz-gamma/; s/ZzBeta/ZzGamma/g' packages/zz-gamma/composer.json
  mv packages/zz-gamma/src/Beta.php packages/zz-gamma/src/Gamma.php
  jq --indent 4 '.require["boatrace/zz-gamma"] = "^0.0.1"' packages/zz-alpha/composer.json > x
  mv x packages/zz-alpha/composer.json
  g add -A
  g commit -q -m 'feat: add the zz-gamma package'
  g push -q origin main
  g init -q --bare "$sb/remotes/shimomo/boatrace-php-zz-gamma.git"
}

case_start 'replace に載っていないパッケージがあると、リリースは何も残さずに止まる'
sb_new m
add_gamma
head_before=$(g rev-parse HEAD)
root_before=$(cksum < composer.json)
sb_release 1.0.0
check 'releaseFails' nonzero "$([ "$status" -ne 0 ] && echo nonzero || echo zero)"
check 'headIsUnchanged' "$head_before" "$(g rev-parse HEAD)"
check 'noTagWasCreated' '' "$(g tag -l | tr '\n' ' ')"
check 'rootManifestIsUnchanged' "$root_before" "$(cksum < composer.json)"
check 'workingTreeIsClean' '' "$(g status --short --ignored)"
check 'nothingWasPublished' '0 0 0' \
  "$(for p in zz-alpha zz-beta zz-gamma; do g ls-remote "$sb/remotes/shimomo/boatrace-php-$p.git" | wc -l; done | tr '\n' ' ' | sed 's/ $//')"
check 'messageNamesThePackage' 1 "$(grep -c 'packages/zz-gamma (boatrace/zz-gamma)' "$sb/out" || true)"

case_start 'bin/merge.sh も同じところで止まり、ルートの composer.json を書き換えない'
sb_new m
add_gamma
set +e
sb_env sh bin/merge.sh > "$sb/out" 2>&1
status=$?
set -e
check 'mergeFails' nonzero "$([ "$status" -ne 0 ] && echo nonzero || echo zero)"
check 'workingTreeIsClean' '' "$(g status --short --ignored)"
check 'messageNamesThePackage' 1 "$(grep -c 'packages/zz-gamma (boatrace/zz-gamma)' "$sb/out" || true)"

case_start 'replace に載せれば通り、ルートの require に自分のパッケージは積まれない'
sb_new m
add_gamma
jq --indent 4 '.replace["boatrace/zz-gamma"] = "self.version"' composer.json > x && mv x composer.json
g commit -q -am 'chore: replace zz-gamma in the root manifest'
g push -q origin main
sb_release 1.0.0
expect_published 1.0.0
check 'rootRequireHasNoInternalPackages' 0 \
  "$(g show 1.0.0:composer.json 2> /dev/null | jq -r '(.require // {}), (."require-dev" // {}) | keys[]' | grep -c '^boatrace/' || true)"
check 'rootAutoloadCoversTheNewPackage' 'packages/zz-gamma/src/' \
  "$(g show 1.0.0:composer.json 2> /dev/null | jq -r '.autoload["psr-4"]["Boatrace\\ZzGamma\\"]')"
check 'theNewPackageIsPublished' 1 \
  "$(g ls-remote --tags --refs "$sb/remotes/shimomo/boatrace-php-zz-gamma.git" refs/tags/1.0.0 | wc -l)"

# --- マージ: ルートの require はパッケージを畳んだもの ------------------------

merge() {
  # 実物の composer_merge_packages_into_root を、砂場の作業ツリーで呼ぶ
  set +e
  sb_env sh -c '. bin/lib/composer-merge.sh; composer_merge_packages_into_root' > "$sb/out" 2>&1
  status=$?
  set -e
}

set_manifest() {
  # set_manifest FILE JQ_FILTER
  jq --indent 4 "$2" "$1" > x
  mv x "$1"
}

case_start 'パッケージから外した依存は、ルートの require からも外れる'
sb_new m
set_manifest packages/zz-beta/composer.json '.require["nesbot/carbon"] = "^3.8.4"'
merge
check 'addedDependencyReachesTheRoot' '^3.8.4' "$(jq -r '.require["nesbot/carbon"]' composer.json)"
set_manifest packages/zz-beta/composer.json 'del(.require["nesbot/carbon"])'
merge
check 'mergeSucceeds' 0 "$status"
check 'rootRequireIsBackToWhatThePackagesNeed' '{"php":"^8.4","symfony/console":"^8.0"}' "$(jq -c '.require' composer.json)"
check 'outputNamesWhatWasRemoved' 1 "$(grep -c 'nesbot/carbon' "$sb/out" || true)"

case_start 'ルートだけが持つ開発用の依存は残る'
sb_new m
set_manifest composer.json '."require-dev"["laravel/pint"] = "^1.27"'
merge
check 'mergeSucceeds' 0 "$status"
check 'rootOnlyDevToolIsKept' '{"phpunit/phpunit":"^13.2","laravel/pint":"^1.27"}' "$(jq -c '."require-dev"' composer.json)"

case_start 'require-dev から require へ移した依存は、ルートでも require だけに残る'
sb_new m
set_manifest packages/zz-beta/composer.json '."require-dev"["psr/log"] = "^3.0"'
merge
check 'devDependencyReachesTheRoot' '^3.0' "$(jq -r '."require-dev"["psr/log"]' composer.json)"
set_manifest packages/zz-beta/composer.json 'del(."require-dev"["psr/log"]) | .require["psr/log"] = "^3.0"'
merge
check 'mergeSucceeds' 0 "$status"
check 'movedDependencyIsInRequireOnly' '^3.0 null' \
  "$(jq -r '"\(.require["psr/log"]) \(."require-dev"["psr/log"])"' composer.json)"

case_start 'ルートの require に紛れ込んだ自分のパッケージも外れる'
sb_new m
set_manifest composer.json '.require["boatrace/zz-beta"] = "^0.0.1"'
merge
check 'mergeSucceeds' 0 "$status"
check 'internalPackageIsRemovedFromTheRoot' 'null' "$(jq -r '.require["boatrace/zz-beta"]' composer.json)"
check 'outputNamesWhatWasRemoved' 1 "$(grep -c '^  boatrace/zz-beta$' "$sb/out" || true)"

# --- マージ: autoload ---------------------------------------------------------

case_start 'psr-4 の値が配列でも、それぞれのパスにパッケージのディレクトリが付く'
sb_new m
set_manifest packages/zz-beta/composer.json \
  '.autoload["psr-4"]["Boatrace\\ZzBeta\\"] = ["src/", "lib/"] | ."autoload-dev"["psr-4"]["Boatrace\\ZzBeta\\Tests\\"] = ["tests/", "fixtures/"]'
merge
check 'mergeSucceeds' 0 "$status"
check 'everyPathIsPrefixed' '["packages/zz-beta/src/","packages/zz-beta/lib/"]' \
  "$(jq -c '.autoload["psr-4"]["Boatrace\\ZzBeta\\"]' composer.json)"
check 'everyDevPathIsPrefixed' '["packages/zz-beta/tests/","packages/zz-beta/fixtures/"]' \
  "$(jq -c '."autoload-dev"["psr-4"]["Boatrace\\ZzBeta\\Tests\\"]' composer.json)"
check 'stringValuesStayStrings' '"packages/zz-alpha/src/" "packages/zz-alpha/tests/"' \
  "$(jq -c '.autoload["psr-4"]["Boatrace\\ZzAlpha\\"], ."autoload-dev"["psr-4"]["Boatrace\\ZzAlpha\\Tests\\"]' composer.json | tr '\n' ' ' | sed 's/ $//')"
check 'noTemporaryFileIsLeft' '' "$(ls composer.json.tmp 2> /dev/null || true)"
merge
check 'mergingAgainChangesNothing' '["packages/zz-beta/src/","packages/zz-beta/lib/"]' \
  "$(jq -c '.autoload["psr-4"]["Boatrace\\ZzBeta\\"]' composer.json)"

# --- マージ: 制約の食い違い -------------------------------------------------

case_start 'パッケージ間で制約が食い違うと、何も書かずに止まる'
sb_new m
set_manifest packages/zz-alpha/composer.json '.require["symfony/console"] = "^8.1"'
g commit -q -am 'chore: raise symfony/console in zz-alpha only'
merge
check 'mergeFails' nonzero "$([ "$status" -ne 0 ] && echo nonzero || echo zero)"
check 'nothingIsWritten' '' "$(g status --short --ignored)"
check 'messageShowsBothSides' 1 \
  "$(grep -c 'symfony/console: \^8.0 (packages/zz-beta), \^8.1 (packages/zz-alpha)' "$sb/out" || true)"

case_start 'require と require-dev にまたがる食い違いでも止まる'
sb_new m
set_manifest packages/zz-alpha/composer.json '.require["psr/log"] = "^2.0"'
set_manifest packages/zz-beta/composer.json '."require-dev"["psr/log"] = "^3.0"'
g commit -q -am 'chore: add psr/log with different constraints'
merge
check 'mergeFails' nonzero "$([ "$status" -ne 0 ] && echo nonzero || echo zero)"
check 'nothingIsWritten' '' "$(g status --short --ignored)"
check 'messageShowsBothSides' 1 \
  "$(grep -c 'psr/log: \^2.0 (packages/zz-alpha), \^3.0 (packages/zz-beta)' "$sb/out" || true)"

case_start '制約が食い違ったままのリリースは、何も残さずに止まる'
sb_new m
edit_manifest zz-alpha '.require["symfony/console"] = "^8.1"' 'chore: raise symfony/console in zz-alpha only'
head_before=$(g rev-parse HEAD)
sb_release 1.0.0
check 'releaseFails' nonzero "$([ "$status" -ne 0 ] && echo nonzero || echo zero)"
check 'headIsUnchanged' "$head_before" "$(g rev-parse HEAD)"
check 'noTagWasCreated' '' "$(g tag -l | tr '\n' ' ')"
check 'workingTreeIsClean' '' "$(g status --short --ignored)"

case_start '実物の composer.json 群: マージしても何も変わらない'
sb_new m
rm -rf packages composer.json
mkdir packages
cp "$REAL/composer.json" .
for d in "$REAL"/packages/*; do
  mkdir -p "packages/$(basename "$d")"
  cp "$d/composer.json" "$d/README.md" "packages/$(basename "$d")/"
done
g add -A
g commit -q -m 'chore: import the real manifests'
merge
check 'mergeSucceeds' 0 "$status"
check 'nothingChanges' '' "$(g status --short --ignored)"
check 'nothingIsReportedAsRemoved' 0 "$(grep -c -i 'removed' "$sb/out" || true)"

finish
