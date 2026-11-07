# 🚤 Boatrace Core

[![php](https://poser.pugx.org/boatrace/core/require/php)](https://packagist.org/packages/boatrace/core)
[![stable](https://poser.pugx.org/boatrace/core/v/stable)](https://packagist.org/packages/boatrace/core)
[![license](https://poser.pugx.org/boatrace/core/license)](https://packagist.org/packages/boatrace/core)

Boatrace Core は、`boatrace/*` パッケージ群が共有する PHP-DI コンテナと、facade / dispatcher / response の3クラス構成を支える共通部品を提供する PHP ライブラリです。

`boatrace/scraper` や `boatrace/scraper-boatcast` が依存しているため、通常は個別にインストールする必要はありません。

## 📦 Requirements

- php: ^8.4
- boatrace/types: ^0.2.0
- php-di/php-di: ^7.0
- symfony/browser-kit: ^8.0

## 💾 Installation

```bash
composer require boatrace/core
```

## ⚡ Usage

### CoreContainer

| メソッド | 説明 |
|---|---|
| `CoreContainer::getInstance($name)` | 契約（interface）名から実装を取得します。同じ契約は同じインスタンスを返します |
| `CoreContainer::getContainer()` | PHP-DI の `Container` をそのまま取得します |
| `CoreContainer::addDefinitions(...$paths)` | 定義ファイルを追加します。既存の定義を上書きでき、コンテナは再構築されます |

コンテナは `boatrace/support` / `boatrace/scraper` / `boatrace/scraper-boatcast` の各パッケージが持つ `config/definitions.php` を自動で集約します。インストールされていないパッケージは無視されます。

### 定義の上書き

利用側で定義ファイルを用意し、`addDefinitions()` で読み込むと、ライブラリ側の定義を差し替えられます。

```php
<?php

require __DIR__ . '/vendor/autoload.php';

use Boatrace\Core\CoreContainer;

CoreContainer::addDefinitions(__DIR__ . '/definitions.php');
```

例えば、呼び出し間隔を 2.0 秒に変えるには次のように書きます。

```php
<?php

// definitions.php

use Boatrace\Support\Throttler\ThrottlerDispatcher;
use Boatrace\Types\Contracts\Converter\ConverterDispatcher as ConverterDispatcherContract;
use Boatrace\Types\Contracts\Throttler\ThrottlerDispatcher as ThrottlerDispatcherContract;

return [
    ThrottlerDispatcherContract::class => \DI\autowire(ThrottlerDispatcher::class)
        ->constructor(\DI\get(ConverterDispatcherContract::class), 2.0),
];
```

HTTP レスポンスの `Server-Timing` を監視するには、`BrowserObserver` 契約を実装して定義を差し替えます。

```php
<?php

// definitions.php

use App\MyBrowserObserver;
use Boatrace\Types\Contracts\Browser\BrowserObserver as BrowserObserverContract;

return [
    BrowserObserverContract::class => \DI\autowire(MyBrowserObserver::class),
];
```

### Concerns

facade / dispatcher / response の定型処理を trait として提供します。`boatrace/*` の各パッケージが利用しています。

| trait | 説明 |
|---|---|
| `RejectsUndefinedCalls` | 未定義メソッドの呼び出しで `BadMethodCallException` を投げます |
| `ResolvesFacadeResponse` | facade の戻り値を Response 契約へ包み、型を検査します |
| `IteratesBatchTargets` | 一括取得で「開催中の場 × 指定レース」を走査し、進捗を表示します |

## 📄 License

Boatrace Core は [MIT license](LICENSE) の元で公開されています。
