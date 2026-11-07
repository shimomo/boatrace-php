# 🚤 Boatrace Scraper Boatcast

[![php](https://poser.pugx.org/boatrace/scraper-boatcast/require/php)](https://packagist.org/packages/boatrace/scraper-boatcast)
[![stable](https://poser.pugx.org/boatrace/scraper-boatcast/v/stable)](https://packagist.org/packages/boatrace/scraper-boatcast)
[![license](https://poser.pugx.org/boatrace/scraper-boatcast/license)](https://packagist.org/packages/boatrace/scraper-boatcast)

Boatrace Scraper Boatcast は、ボートキャスト（BOATCAST）からオリジナル展示データ、発売票数、オッズをスクレイピングするための PHP ライブラリです。

オリジナル展示データ（一周・まわり足・直線など）と発売票数は公式サイトでは公開されていません。ボートキャストは全場を同じ仕組みで配信しているため、場ごとの実装を持たずに取得できます。

オッズは公式サイトでも公開されていますが、こちらは 1 レースあたり 3 リクエストで済みます（公式サイトは賭式ごとにページが分かれるため 5 リクエスト）。戻り値のキーと形は `boatrace/scraper` の `Scraper::scrapeOdds()` に揃えてあり、そのまま差し替えられます。

## 📦 Requirements

- php: ^8.4
- boatrace/core: ^0.2.0
- boatrace/support: ^0.2.0
- boatrace/types: ^0.2.0
- nesbot/carbon: ^3.8.4
- symfony/browser-kit: ^8.0
- symfony/http-client: ^8.0

## 💾 Installation

```bash
composer require boatrace/scraper-boatcast
```

## ⚡ Usage

### サポートメソッド一覧

| メソッド | 引数 |
|---|---|
| 開催場を取得<br>`BoatcastScraper::scrapeStadium($date)` | `$date` : DateTimeInterface インスタンスまたは DateTimeInterface 対応日付文字列 |
| オリジナル展示データを取得<br>`BoatcastScraper::scrapeTime($date, $stadiumNumber, $raceNumber)` | `$date` : 同上<br>`$stadiumNumber` : 1〜24<br>`$raceNumber` : 1〜12 |
| オリジナル展示データを一括取得<br>`BatchBoatcastScraper::scrapeTime($date [, $stadiumNumbers, $raceNumbers])` | `$date` : 同上<br>`$stadiumNumbers` : [1〜24]（省略時は開催中の全場）<br>`$raceNumbers` : [1〜12]（省略時は全レース） |
| 発売票数を取得<br>`BoatcastScraper::scrapeVote($date, $stadiumNumber, $raceNumber)` | `$date` : 同上<br>`$stadiumNumber` : 1〜24<br>`$raceNumber` : 1〜12 |
| 発売票数を一括取得<br>`BatchBoatcastScraper::scrapeVote($date [, $stadiumNumbers, $raceNumbers])` | 同上 |
| オッズを取得<br>`BoatcastScraper::scrapeOdds($date, $stadiumNumber, $raceNumber)` | `$date` : 同上<br>`$stadiumNumber` : 1〜24<br>`$raceNumber` : 1〜12 |
| オッズを一括取得<br>`BatchBoatcastScraper::scrapeOdds($date [, $stadiumNumbers, $raceNumbers])` | 同上 |

戻り値はレスポンスオブジェクトです。値は `getValue()` で取り出します。

### 設定・ユーティリティ

| メソッド | 説明 |
|---|---|
| `BatchBoatcastScraper::getShowProgress()` | 一括取得時のプログレスバー表示を取得します |
| `BatchBoatcastScraper::setShowProgress($showProgress)` | 一括取得時のプログレスバー表示を設定します。既定は false |

呼び出し間隔は `Boatrace\Support\Throttler\Throttler` で設定します（既定は 1.0 秒）。

### 基本的な使い方

```php
<?php

require __DIR__ . '/vendor/autoload.php';

use Boatrace\BoatcastScraper\BatchBoatcastScraper;
use Boatrace\BoatcastScraper\BoatcastScraper;

// オリジナル展示データを取得
$time = BoatcastScraper::scrapeTime('2026-08-01', 22, 1)->getValue();
$timeBatch = BatchBoatcastScraper::scrapeTime('2026-08-01', [22, 23], [1, 2])->getValue();

// 発売票数を取得
$vote = BoatcastScraper::scrapeVote('2026-08-01', 22, 1)->getValue();

// オッズを取得
$odds = BoatcastScraper::scrapeOdds('2026-08-01', 22, 1)->getValue();
```

### BoatcastScraper::scrapeTime()

計測項目は場によって異なります。桐生は一周ではなく半周ラップを計測するため `half_lap_time` に、住之江は直線を計測しないため `straight_time` が null になります。**キーは全場で共通**で、持たない項目は null です。

```php
// 例: 2026年08月01日 の 福岡（22）1 レースのオリジナル展示データを取得
$time = BoatcastScraper::scrapeTime('2026-08-01', 22, 1)->getValue();

print_r($time);
```

<details>
<summary>取得結果（3〜6号艇は省略）</summary>

```php
Array
(
    [date] => 2026-08-01
    [stadium_number] => 22
    [race_number] => 1
    [racers] => Array
        (
            [1] => Array
                (
                    [entry_number] => 1
                    [name] => 井上 恵一
                    [lap_time] => 36.88
                    [half_lap_time] =>
                    [turn_time] => 7.73
                    [straight_time] => 7.78
                )

            [2] => Array
                (
                    [entry_number] => 2
                    [name] => 田中 孝明
                    [lap_time] => 37.1
                    [half_lap_time] =>
                    [turn_time] => 7.98
                    [straight_time] => 7.73
                )

        )

)
```

</details>

### BoatcastScraper::scrapeVote()

賭式ごとに全組番の票数を返します。`totals` は賭式ごとの合計・返還・差引です。

確定値を先に取りに行き、まだ無ければ発売中の値へフォールバックします。`is_fixed` は3賭式すべてが確定値だったときだけ true になります。

```php
// 例: 2026年08月01日 の 福岡（22）1 レースの発売票数を取得
$vote = BoatcastScraper::scrapeVote('2026-08-01', 22, 1)->getValue();

echo $vote['trifecta'][1][2][3];        // 19241（3連単 1-2-3）
echo $vote['totals']['trifecta']['total'];  // 178529（3連単の合計）
```

<details>
<summary>取得結果（1 号艇絡み以外は省略）</summary>

```php
Array
(
    [date] => 2026-08-01
    [stadium_number] => 22
    [race_number] => 1
    [is_fixed] => 1
    [trifecta] => Array
        (
            [1] => Array
                (
                    [2] => Array
                        (
                            [3] => 19241
                            [4] => 25522
                            [5] => 16430
                            [6] => 2199
                        )

                )

        )

    [win] => Array
        (
            [1] => 127
            [2] => 15
            [3] => 5
            [4] => 27
            [5] => 10
            [6] => 4
        )

    [totals] => Array
        (
            [trifecta] => Array
                (
                    [total] => 178529
                    [refund] => 0
                    [difference] => 178529
                )

            [trio] => Array
                (
                    [total] => 2227
                    [refund] => 0
                    [difference] => 2227
                )

        )

)
```

</details>

`trifecta` / `trio` / `exacta` / `quinella` / `quinella_place` / `win` / `place` の 7 賭式を返します。組番のキーは `boatrace/scraper` のオッズと同じ形なので、同じ添字で突き合わせられます。

### BoatcastScraper::scrapeOdds()

賭式ごとに全組番のオッズを返します。`quinella_place`（拡連複）と `place`（複勝）は幅を持つため、`lower_limit` / `upper_limit` の組で返します。

発売票数と同じく、確定値を先に取りに行き、まだ無ければ発売中の値へフォールバックします。`is_fixed` は3賭式すべてが確定値だったときだけ true になります。

```php
// 例: 2026年08月01日 の 福岡（22）1 レースのオッズを取得
$odds = BoatcastScraper::scrapeOdds('2026-08-01', 22, 1)->getValue();

echo $odds['trifecta'][1][2][3];              // 6.9（3連単 1-2-3）
echo $odds['win'][1];                         // 1.1（単勝 1）
echo $odds['place'][2]['lower_limit'];        // 2.3（複勝 2 の下限）
echo $odds['quinella_place'][1][2]['upper_limit'];  // 2.4（拡連複 1=2 の上限）
```

<details>
<summary>取得結果（1 号艇絡み以外は省略）</summary>

```php
Array
(
    [date] => 2026-08-01
    [stadium_number] => 22
    [race_number] => 1
    [is_fixed] => 1
    [trifecta] => Array
        (
            [1] => Array
                (
                    [2] => Array
                        (
                            [3] => 6.9
                            [4] => 5.2
                            [5] => 8.1
                            [6] => 60.8
                        )

                )

        )

    [quinella_place] => Array
        (
            [1] => Array
                (
                    [2] => Array
                        (
                            [lower_limit] => 1.7
                            [upper_limit] => 2.4
                        )

                )

        )

    [win] => Array
        (
            [1] => 1.1
            [2] => 9.4
            [3] => 28.2
            [4] => 5.2
            [5] => 14.1
            [6] => 35.2
        )

    [place] => Array
        (
            [1] => Array
                (
                    [lower_limit] => 1.0
                    [upper_limit] => 1.0
                )

            [2] => Array
                (
                    [lower_limit] => 2.3
                    [upper_limit] => 4.6
                )

        )

)
```

</details>

**オッズが無い組番は null になります**。これは 2 通りの場合に起きます。

- **返還艇を含んで成立しない組番**。行・列がずれることはないので、該当する組番だけが null になり、残りは通常どおり読めます。
- **発売直後でまだ1票も入っていないとき**。この間は全組番が null になります。オッズは最低でも 1.0 倍なので、0 倍を返すことはありません。

票待ちかどうかは `is_fixed` が false かつ全組番が null かで判定できます。

## ⚠️ Notes

- **スクレイピング対象のサイトの構造が変更された場合**、正しくデータを取得できなくなる可能性があります。
- **江戸川（03）にはオリジナル展示という区分がありません**。取得すると全項目 null で返ります。将来実装された場合は、そのまま値が入ります。
- 発売前・レース中止・計測できなかったレースも、キーを揃えて null で返します。
- 発売票数とオッズは、それぞれ 1 レースあたり 3 リクエストを要します。一括取得では件数に注意してください。
- 利用時は対象サイトの利用規約を遵守してください。

## 📄 License

Boatrace Scraper Boatcast は [MIT license](LICENSE) の元で公開されています。
