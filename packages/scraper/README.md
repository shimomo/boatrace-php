# 🚤 Boatrace Scraper

[![php](https://poser.pugx.org/boatrace/scraper/require/php)](https://packagist.org/packages/boatrace/scraper)
[![stable](https://poser.pugx.org/boatrace/scraper/v/stable)](https://packagist.org/packages/boatrace/scraper)
[![license](https://poser.pugx.org/boatrace/scraper/license)](https://packagist.org/packages/boatrace/scraper)

Boatrace Scraper は、ボートレースの公式サイトから開催場、出走表、直前情報、オッズ、結果をスクレイピングするための PHP ライブラリです。

## 📦 Requirements

- php: ^8.4
- boatrace/core: ^0.1
- boatrace/support: ^0.1
- boatrace/types: ^0.1
- nesbot/carbon: ^3.8.4
- symfony/browser-kit: ^8.0
- symfony/css-selector: ^8.0
- symfony/dom-crawler: ^8.0
- symfony/http-client: ^8.0

## 💾 Installation

```bash
composer require boatrace/scraper
```

## ⚡ Usage

### サポートメソッド一覧

| メソッド | 引数 |
|---|---|
| 開催場を取得<br>`Scraper::scrapeStadium($date)` | `$date` : DateTimeInterface インスタンスまたは DateTimeInterface 対応日付文字列 |
| 出走表を取得<br>`Scraper::scrapeProgram($date, $stadiumNumber, $raceNumber)` | `$date` : 同上<br>`$stadiumNumber` : 1〜24<br>`$raceNumber` : 1〜12 |
| 出走表を一括取得<br>`BatchScraper::scrapeProgram($date [, $stadiumNumbers, $raceNumbers])` | `$date` : 同上<br>`$stadiumNumbers` : [1〜24]（省略時は開催中の全場）<br>`$raceNumbers` : [1〜12]（省略時は全レース） |
| 直前情報を取得<br>`Scraper::scrapePreview($date, $stadiumNumber, $raceNumber)` | `$date` : 同上<br>`$stadiumNumber` : 1〜24<br>`$raceNumber` : 1〜12 |
| 直前情報を一括取得<br>`BatchScraper::scrapePreview($date [, $stadiumNumbers, $raceNumbers])` | 同上 |
| オッズを取得<br>`Scraper::scrapeOdds($date, $stadiumNumber, $raceNumber)` | `$date` : 同上<br>`$stadiumNumber` : 1〜24<br>`$raceNumber` : 1〜12 |
| オッズを一括取得<br>`BatchScraper::scrapeOdds($date [, $stadiumNumbers, $raceNumbers])` | 同上 |
| 結果を取得<br>`Scraper::scrapeResult($date, $stadiumNumber, $raceNumber)` | `$date` : 同上<br>`$stadiumNumber` : 1〜24<br>`$raceNumber` : 1〜12 |
| 結果を一括取得<br>`BatchScraper::scrapeResult($date [, $stadiumNumbers, $raceNumbers])` | 同上 |

戻り値はレスポンスオブジェクトです。値は `getValue()` で取り出します。

### 設定・ユーティリティ

| メソッド | 説明 |
|---|---|
| `Scraper::getMinCallIntervalSeconds()` | 呼び出し間隔（秒）を取得します |
| `Scraper::setMinCallIntervalSeconds($seconds)` | 呼び出し間隔（秒）を設定します。既定は 1.0 秒、負値は指定できません |
| `Scraper::throttle()` | 前回の呼び出しから最小間隔が経過するまで待機します |
| `BatchScraper::getShowProgress()` | 一括取得時のプログレスバー表示を取得します |
| `BatchScraper::setShowProgress($showProgress)` | 一括取得時のプログレスバー表示を設定します。既定は false |

### 基本的な使い方

```php
<?php

require __DIR__ . '/vendor/autoload.php';

use Boatrace\Scraper\BatchScraper;
use Boatrace\Scraper\Scraper;

// 開催場を取得
$stadium = Scraper::scrapeStadium('2026-08-01')->getValue();

// 出走表を取得
$program = Scraper::scrapeProgram('2026-08-01', 22, 1)->getValue();
$programBatch = BatchScraper::scrapeProgram('2026-08-01', [22, 23], [1, 2])->getValue();

// 直前情報・オッズ・結果も同じ形で取得できます
$preview = Scraper::scrapePreview('2026-08-01', 22, 1)->getValue();
$odds = Scraper::scrapeOdds('2026-08-01', 22, 1)->getValue();
$result = Scraper::scrapeResult('2026-08-01', 22, 1)->getValue();
```

### Scraper::scrapeStadium()

```php
// 例: 2026年08月01日 に開催している場を取得
$stadium = Scraper::scrapeStadium('2026-08-01')->getValue();

print_r($stadium);
```

<details>
<summary>取得結果</summary>

```php
Array
(
    [1] => 桐生
    [5] => 多摩川
    [6] => 浜名湖
    [8] => 常滑
    [9] => 津
    [10] => 三国
    [11] => びわこ
    [13] => 尼崎
    [15] => 丸亀
    [16] => 児島
    [18] => 徳山
    [20] => 若松
    [22] => 福岡
    [23] => 唐津
)
```

</details>

### Scraper::scrapeProgram()

```php
// 例: 2026年08月01日 の 福岡（22）1 レースの出走表を取得
$program = Scraper::scrapeProgram('2026-08-01', 22, 1)->getValue();

print_r($program);
```

<details>
<summary>取得結果（2〜6号艇は 1 号艇と同じ構造のため省略）</summary>

```php
Array
(
    [date] => 2026-08-01
    [stadium_number] => 22
    [race_number] => 1
    [closed_at] => 2026-08-01 12:17:00
    [grade_number_source] => ippan
    [grade_number] => 5
    [title] => 西部ボートレース記者クラブ杯
    [subtitle] => カタメン1予選
    [distance_source] => 1800m
    [distance] => 1800
    [is_stabilizer_used_source] =>
    [is_stabilizer_used] =>
    [day_number_source] => 4日目
    [day_number] => 4
    [racers] => Array
        (
            [1] => Array
                (
                    [entry_number] => 1
                    [name] => 金田 諭
                    [number] => 4036
                    [rank_number_source] => A1
                    [rank_number] => 1
                    [branch_number_source] => 埼玉
                    [branch_number] => 11
                    [birthplace_number_source] => 埼玉
                    [birthplace_number] => 11
                    [age_source] => 47歳
                    [age] => 47
                    [weight_source] => 52.0kg
                    [weight] => 52
                    [flying_count_source] => F0
                    [flying_count] => 0
                    [late_count_source] => L0
                    [late_count] => 0
                    [average_start_timing] => 0.16
                    [national_win_rate] => 6.46
                    [national_top_2_percent] => 44.03
                    [national_top_3_percent] => 70.15
                    [local_win_rate] => 7.22
                    [local_top_2_percent] => 50
                    [local_top_3_percent] => 83.33
                    [motor_number] => 73
                    [motor_top_2_percent] => 28.7
                    [motor_top_3_percent] => 48.15
                    [boat_number] => 149
                    [boat_top_2_percent] => 29.49
                    [boat_top_3_percent] => 46.15
                )

        )

)
```

</details>

### Scraper::scrapePreview()

`weather_as_of_*` は水面気象の見出し（`水面気象情報　11R時点`）から読んだ計測の時点です。2R 以降は1つ前のレースが走った時点で固定され（`weather_as_of_race_number` が `race_number - 1` になる）、それまではより古い時点の値が載ります。1R は前のレースが無いため `18:08現在` の形で一日じゅう更新され、開催後に取得するとその日の最後の計測値になります。見出しが未知の文言なら `weather_as_of_source` だけが入り、残り2つは `null` です。

```php
// 例: 2026年08月01日 の 福岡（22）1 レースの直前情報を取得
$preview = Scraper::scrapePreview('2026-08-01', 22, 1)->getValue();

print_r($preview);
```

<details>
<summary>取得結果（2〜6号艇は 1 号艇と同じ構造のため省略）</summary>

```php
Array
(
    [date] => 2026-08-01
    [stadium_number] => 22
    [race_number] => 1
    [weather_as_of_source] => 18:08現在
    [weather_as_of_race_number] =>
    [weather_as_of_time] => 18:08
    [wind_speed_source] => 3m
    [wind_speed] => 3
    [wind_direction_number_source] => 南南東
    [wind_direction_number] => 8
    [wave_height_source] => 3cm
    [wave_height] => 3
    [weather_number_source] => 晴
    [weather_number] => 1
    [air_temperature_source] => 33.0℃
    [air_temperature] => 33
    [water_temperature_source] => 29.0℃
    [water_temperature] => 29
    [racers] => Array
        (
            [1] => Array
                (
                    [entry_number] => 1
                    [course_number] => 1
                    [start_timing_source] => .12
                    [start_timing] => 0.12
                    [weight_source] => 52.0kg
                    [weight] => 52
                    [weight_adjustment_source] => 0.0
                    [weight_adjustment] => 0
                    [exhibition_time_source] => 6.94
                    [exhibition_time] => 6.94
                    [tilt_adjustment_source] => -0.5
                    [tilt_adjustment] => -0.5
                )

        )

)
```

</details>

### Scraper::scrapeOdds()

3連単は 120 通り、3連複は 20 通りといったように、賭式ごとに全組番を返します。

```php
// 例: 2026年08月01日 の 福岡（22）1 レースのオッズを取得
$odds = Scraper::scrapeOdds('2026-08-01', 22, 1)->getValue();

echo $odds['trifecta'][1][2][3];  // 6.9（3連単 1-2-3）
echo $odds['win'][1];             // 1.1（単勝 1）
```

<details>
<summary>取得結果（1 号艇絡み以外は省略）</summary>

```php
Array
(
    [date] => 2026-08-01
    [stadium_number] => 22
    [race_number] => 1
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

    [trio] => Array
        (
            [1] => Array
                (
                    [2] => Array
                        (
                            [3] => 3.8
                            [4] => 3.3
                            [5] => 4.3
                            [6] => 25.3
                        )

                )

        )

    [exacta] => Array
        (
            [1] => Array
                (
                    [2] => 2.3
                    [3] => 7.4
                    [4] => 4.1
                    [5] => 5.7
                    [6] => 70.5
                )

        )

    [quinella] => Array
        (
            [1] => Array
                (
                    [2] => 1.7
                    [3] => 6.8
                    [4] => 3.9
                    [5] => 5.6
                    [6] => 35.5
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
        )

    [place] => Array
        (
            [1] => Array
                (
                    [lower_limit] => 1
                    [upper_limit] => 1
                )

        )

)
```

</details>

### Scraper::scrapeResult()

```php
// 例: 2026年08月01日 の 福岡（22）1 レースの結果を取得
$result = Scraper::scrapeResult('2026-08-01', 22, 1)->getValue();

print_r($result);
```

<details>
<summary>取得結果（2〜6号艇と一部の賭式は省略）</summary>

```php
Array
(
    [date] => 2026-08-01
    [stadium_number] => 22
    [race_number] => 1
    [wind_speed_source] => 3m
    [wind_speed] => 3
    [wind_direction_number_source] => 南南東
    [wind_direction_number] => 8
    [wave_height_source] => 3cm
    [wave_height] => 3
    [weather_number_source] => 晴
    [weather_number] => 1
    [air_temperature_source] => 33.0℃
    [air_temperature] => 33
    [water_temperature_source] => 29.0℃
    [water_temperature] => 29
    [technique_number_source] => 逃げ
    [technique_number] => 1
    [racers] => Array
        (
            [1] => Array
                (
                    [entry_number] => 1
                    [course_number] => 1
                    [start_timing_source] => .14
                    [start_timing] => 0.14
                    [place_number_source] => 1
                    [place_number] => 1
                    [number_source] => 4036
                    [number] => 4036
                    [name] => 金田 諭
                )

        )

    [payouts] => Array
        (
            [trifecta] => Array
                (
                    [0] => Array
                        (
                            [combination] => 1-2-3
                            [amount] => 690
                        )

                )

            [trio] => Array
                (
                    [0] => Array
                        (
                            [combination] => 1=2=3
                            [amount] => 380
                        )

                )

        )

)
```

</details>

## ⚠️ Notes

- **スクレイピング対象の公式サイトの構造が変更された場合**、正しくデータを取得できなくなる可能性があります。
- 取得できなかった艇も、キーを揃えて null で返します。
- レース確定から数十分のあいだは結果表が公開されず払戻表だけが先に出るため、結果の `racers` がすべて null になることがあります。
- 利用時は対象サイトの利用規約を遵守してください。

## 📄 License

Boatrace Scraper は [MIT license](LICENSE) の元で公開されています。
