# 🚤 Boatrace Support

[![php](https://poser.pugx.org/boatrace/support/require/php)](https://packagist.org/packages/boatrace/support)
[![stable](https://poser.pugx.org/boatrace/support/v/stable)](https://packagist.org/packages/boatrace/support)
[![license](https://poser.pugx.org/boatrace/support/license)](https://packagist.org/packages/boatrace/support)

Boatrace Support は、`boatrace/*` パッケージ群が共有する汎用モジュール（HTTP ブラウザ、呼び出し間隔の制御、値の変換・正規化、XPath 抽出など）を提供する PHP ライブラリです。ボートレース固有の知識は持ちません。

`boatrace/scraper` や `boatrace/scraper-boatcast` が依存しているため、通常は個別にインストールする必要はありません。

## 📦 Requirements

- php: ^8.4
- boatrace/core: ^0.2.0
- boatrace/types: ^0.2.0
- symfony/browser-kit: ^8.0
- symfony/console: ^8.0
- symfony/css-selector: ^8.0
- symfony/dom-crawler: ^8.0
- symfony/http-client: ^8.0

## 💾 Installation

```bash
composer require boatrace/support
```

## ⚡ Usage

すべてのモジュールは静的に呼び出せます。戻り値はレスポンスオブジェクトで、値は `getValue()` で取り出します。

```php
<?php

require __DIR__ . '/vendor/autoload.php';

use Boatrace\Support\Converter\Converter;
use Boatrace\Support\Throttler\Throttler;
use Boatrace\Support\Trimmer\Trimmer;

$value = Trimmer::trimOrNull('　福岡　')->getValue();  // 福岡
$value = Converter::toInt('22')->getValue();           // 22

Throttler::setMinCallIntervalSeconds(2.0);
Throttler::throttle();
```

### モジュール一覧

| モジュール | メソッド | 説明 |
|---|---|---|
| `Browser` | `create($serverParameters = [])` | ブラウザらしいヘッダを備えた `HttpBrowser` を生成します。トランスポート例外と 423 / 425 / 429 / 5xx は自動で再試行します |
| `Throttler` | `getMinCallIntervalSeconds()`<br>`setMinCallIntervalSeconds($seconds)`<br>`throttle()` | 呼び出し間隔を制御します。既定は 1.0 秒で、0.5〜1.5 倍のゆらぎが付きます。プロセス全体で共有されます |
| `Trimmer` | `trimOrNull($value, $characters = null)`<br>`ltrimOrNull(...)`<br>`rtrimOrNull(...)` | `mb_trim` 系で全角空白を含めて trim します。null は null のまま返します |
| `Converter` | `toInt($value)`<br>`toFloat($value)`<br>`toString($value)`<br>`toKana($value)`<br>`toDayNumber($value)`<br>`toCamelCaseKeys($value)`<br>`toEnumOrNull($resolver)` など | 型変換です。null は null のまま返します。`*Strict` は null を受け付けず、`*OrReturn` は変換できなければ入力をそのまま返します |
| `Normalizer` | `normalize($value, $options = [])` | 文字列中の空白・数字を整え、数値文字列は int / float にします。配列は再帰的に処理します |
| `Filter` | `byXPath($crawler, $xpath)`<br>`byXPathAsAttribute($crawler, $xpath, $attribute)`<br>`byXPathAsPattern($crawler, $xpath, $attribute, $pattern)` | `Crawler` から XPath で文字列や属性値を抽出します。見つからなければ null を返します |
| `Validator` | `between($value, $minimum, $maximum, $name = '$value')` | 範囲を検証します。範囲外なら `ValueError` を投げ、null は null のまま返します |
| `Progress` | `isEnabled()`<br>`setEnabled($enabled)`<br>`start($totalSteps, $message = null)`<br>`advance($step = 1)`<br>`finish($message = null)` | コンソールにプログレスバーを表示します。既定は無効です |
| `Timing` | `parse($value)` | `Server-Timing` ヘッダを指標ごとの `dur` / `desc` に分解します |
| `Tsv` | `parse($value)` | TSV 文字列を行・列の配列にします。壊れた入力は空配列を返します |
| `Json` | `decode($value)` | JSON 文字列を配列にします。壊れた入力は null を返します |

### Browser

boatrace.jp は Akamai の背後にあり、ブラウザらしくないリクエストは拒否ではなく 8〜10 秒待たされた上で 200 が返ります。`Browser::create()` が返す `HttpBrowser` は、`User-Agent` / `Sec-CH-UA` / `Sec-Fetch-*` / `Accept-Language` をあらかじめ備えています。

```php
use Boatrace\Support\Browser\Browser;

$httpBrowser = Browser::create()->getValue();
$crawler = $httpBrowser->request('GET', 'https://www.boatrace.jp/owpc/pc/race/index');
```

遅延したかどうかは `Server-Timing` ヘッダの `edge` に現れます。監視したい場合は `Boatrace\Types\Contracts\Browser\BrowserObserver` を実装し、`boatrace/core` の `CoreContainer::addDefinitions()` で定義を差し替えます。閾値や通知先はライブラリでは持ちません。

## 📄 License

Boatrace Support は [MIT license](LICENSE) の元で公開されています。
