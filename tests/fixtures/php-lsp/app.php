<?php

declare(strict_types=1);

require_once __DIR__ . '/src/Greeter.php';

use VimConfigFixture\Greeter;

function vim_config_fixture_caller(): string
{
    $greeter = new Greeter();
    return $greeter->greet('Reader');
}

vim_config_fixture_caller();
