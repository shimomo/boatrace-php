# 🚤 Boatrace

[![test](https://github.com/shimomo/boatrace-php/actions/workflows/test.yml/badge.svg)](https://github.com/shimomo/boatrace-php/actions/workflows/test.yml)
[![psalm](https://github.com/shimomo/boatrace-php/actions/workflows/psalm.yml/badge.svg)](https://github.com/shimomo/boatrace-php/actions/workflows/psalm.yml)
[![lint](https://github.com/shimomo/boatrace-php/actions/workflows/lint.yml/badge.svg)](https://github.com/shimomo/boatrace-php/actions/workflows/lint.yml)

Boatrace は、ボートレース（競艇）のデータ取得ライブラリを開発するモノレポです。

各パッケージは独立した GitHub リポジトリへ分割されており、Packagist から個別にインストールできます。

---

## 📦 パッケージ

| Package | Description | Packagist |
|---------|-------------|-----------|
| `boatrace/types` | 契約（interface）と Enum | https://packagist.org/packages/boatrace/types |
| `boatrace/core` | PHP-DI コンテナと共通部品 | https://packagist.org/packages/boatrace/core |
| `boatrace/support` | 汎用モジュール（HTTP ブラウザ、変換、XPath 抽出など） | https://packagist.org/packages/boatrace/support |
| `boatrace/scraper` | ボートレース公式サイトのスクレイピング | https://packagist.org/packages/boatrace/scraper |
| `boatrace/scraper-boatcast` | ボートキャストのスクレイピング（展示タイム、票数、オッズ） | https://packagist.org/packages/boatrace/scraper-boatcast |

利用側が直接 require するのは `boatrace/scraper` と `boatrace/scraper-boatcast` で、残りは推移的に入ります。

```bash
composer require boatrace/scraper boatrace/scraper-boatcast
```

---

## 🗂️ リポジトリ構造

```
.
├── .github/
│   ├── workflows/
│   └── dependabot.yml
├── bin/
│   ├── lib/
│   ├── merge.sh
│   └── release.sh
├── packages/
│   ├── core/
│   ├── scraper/
│   ├── scraper-boatcast/
│   ├── support/
│   └── types/
├── .gitignore
├── CHANGELOG.md
├── composer.json
├── LICENSE
├── phpunit.xml.dist
├── pint.json
├── psalm.xml.dist
└── README.md
```

各ディレクトリは独立した Composer パッケージです。

リリース時には、それぞれ専用リポジトリ（`shimomo/boatrace-php-<package>`）へ同期され Packagist で公開されます。

---

## 🛠️ 開発

```bash
composer test       # phpunit
composer analyse    # psalm
composer lint       # pint --test
composer fix        # pint
composer normalize  # composer.json の整形
```

`packages/*/composer.json` を変えたら `bin/merge.sh` でルートの `composer.json` へ反映します。

リリースは `bin/release.sh <version>` です。CHANGELOG の更新、バージョンの書き込み、タグ付け、各パッケージの分割と push、GitHub Release の作成までを行います。

---

## 📄 ライセンス

Boatrace は [MIT license](LICENSE) の元で公開されています。
