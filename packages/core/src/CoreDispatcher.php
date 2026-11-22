<?php

declare(strict_types=1);

namespace Boatrace\Core;

use Boatrace\Core\Concerns\RejectsUndefinedCalls;
use Boatrace\Types\Contracts\Core\CoreDispatcher as CoreDispatcherContract;

/**
 * @author shimomo
 */
final class CoreDispatcher implements CoreDispatcherContract
{
    use RejectsUndefinedCalls;
}
