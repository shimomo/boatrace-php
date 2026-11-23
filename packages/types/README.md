# 🚤 Boatrace Types

[![php](https://poser.pugx.org/boatrace/types/require/php)](https://packagist.org/packages/boatrace/types)
[![stable](https://poser.pugx.org/boatrace/types/v/stable)](https://packagist.org/packages/boatrace/types)
[![license](https://poser.pugx.org/boatrace/types/license)](https://packagist.org/packages/boatrace/types)

Boatrace Types は、`boatrace/*` パッケージ群が共有する契約（interface）と Enum を提供する PHP ライブラリです。実装は持ちません。

`boatrace/core` / `boatrace/support` / `boatrace/scraper` / `boatrace/scraper-boatcast` が依存しているため、通常は個別にインストールする必要はありません。

## 📦 Requirements

- php: ^8.4
- php-di/php-di: ^7.0
- symfony/browser-kit: ^8.0
- symfony/dom-crawler: ^8.0

## 💾 Installation

```bash
composer require boatrace/types
```

## ⚡ Usage

### Enums

スクレイパの戻り値に含まれる `*_number` は、対応する Enum の値です。名前から引く `fromName()`、一覧を配列で返す `toArray()` を共通で持ちます。

```php
<?php

require __DIR__ . '/vendor/autoload.php';

use Boatrace\Types\Enums\Grade;
use Boatrace\Types\Enums\Rank;
use Boatrace\Types\Enums\Stadium;

$stadium = Stadium::from(22);           // Stadium::福岡
$stadium = Stadium::fromName('福岡');   // Stadium::福岡
$grade = Grade::from(5);                // Grade::OPEN
$rank = Rank::fromShortName('A1');      // Rank::A1級
$rank->name();                          // A1級

print_r(Grade::toArray());
```

<details>
<summary>取得結果</summary>

```php
Array
(
    [0] => Array
        (
            [number] => 1
            [name] => SG
        )

    [1] => Array
        (
            [number] => 2
            [name] => G1
        )

    [2] => Array
        (
            [number] => 3
            [name] => G2
        )

    [3] => Array
        (
            [number] => 4
            [name] => G3
        )

    [4] => Array
        (
            [number] => 5
            [name] => OPEN
        )

    [5] => Array
        (
            [number] => 6
            [name] => PG1
        )

)
```

</details>

| Enum | 値 | 説明 |
|---|---|---|
| `Stadium` | 1〜24 | 場（桐生〜大村） |
| `Grade` | 1〜6 | グレード（SG / G1 / G2 / G3 / OPEN / PG1） |
| `Rank` | 1〜4 | 級別（A1級〜B2級）。`shortName()` は `A1` |
| `Prefecture` | 1〜47 | 都道府県。`shortName()` は `福岡` のように末尾を除いた形 |
| `Place` | 1〜16, 99 | 着順と失格・返還の区分。`shortName()` は結果表の表記（`1`、`F`、`妨` など） |
| `Technique` | 1〜6 | 決まり手（逃げ〜恵まれ） |
| `Weather` | 1〜6, 99 | 天候。`shortName()` は `曇` のような 1 文字表記 |
| `WindDirection` | 1〜17 | 風向（北〜北北西、無風）。`fromValue()` は `null` を通す `from()` |
| `Part` | 1〜8 | 部品交換の部品。`fromShortName()` は公式サイトの略号（`キャブ`）から引く |
| `Absence` | 1〜4 | ボートキャストで本文を採れなかった理由（未公開 / 想定外 / 発売前 / 中止）。`fromStatus()` はファイルのステータス行から引く |

`fromName()` / `fromShortName()` は `null` を渡すと `null` を返し、未知の名前には `ValueError` を投げます。

### Contracts

`Contracts/` 配下に、各モジュールの facade / dispatcher / response の契約を置いています。実装は `boatrace/core` の `CoreContainer` が契約名から解決します。

| 名前空間 | 実装パッケージ |
|---|---|
| `Contracts\Core` / `Contracts\Definitions` | `boatrace/core` |
| `Contracts\Browser` / `Converter` / `Filter` / `Json` / `Normalizer` / `Progress` / `Throttler` / `Timing` / `Trimmer` / `Tsv` / `Validator` | `boatrace/support` |
| `Contracts\Scraper` / `BatchScraper` / `Parser` | `boatrace/scraper` |
| `Contracts\BoatcastScraper` / `BatchBoatcastScraper` | `boatrace/scraper-boatcast` |

利用側で実装を差し替える場合は、これらの契約を実装したクラスを `CoreContainer::addDefinitions()` で登録します。例えば `Contracts\Browser\BrowserObserver` を実装すると、HTTP レスポンスの `Server-Timing` を監視できます。

## 📄 License

Boatrace Types は [MIT license](LICENSE) の下で公開されています。
