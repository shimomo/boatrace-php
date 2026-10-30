<?php

declare(strict_types=1);

namespace Boatrace\Scraper\Tests\Scrapers;

/**
 * @author shimomo
 */
final class ProgramScraperDataProvider
{
    /**
     * @return non-empty-list<array{
     *     key: non-empty-string,
     *     expected: int|float|string|bool|null,
     * }>
     */
    public static function raceProvider(): array
    {
        return [
            ['key' => 'date', 'expected' => '2026-08-01'],
            ['key' => 'stadium_number', 'expected' => 22],
            ['key' => 'race_number', 'expected' => 1],
            ['key' => 'closed_at', 'expected' => '2026-08-01 12:17:00'],
            ['key' => 'grade_number_source', 'expected' => 'ippan'],
            ['key' => 'grade_number', 'expected' => 5],
            ['key' => 'title', 'expected' => '西部ボートレース記者クラブ杯'],
            ['key' => 'subtitle', 'expected' => 'カタメン1予選'],
            ['key' => 'distance_source', 'expected' => '1800m'],
            ['key' => 'distance', 'expected' => 1800],
            ['key' => 'is_stabilizer_used_source', 'expected' => null],
            ['key' => 'is_stabilizer_used', 'expected' => false],
            ['key' => 'day_number_source', 'expected' => '4日目'],
            ['key' => 'day_number', 'expected' => 4],
        ];
    }

    /**
     * @return non-empty-list<array{
     *     key: non-empty-string,
     *     expected: int|float|string|null,
     * }>
     */
    public static function racerProvider(): array
    {
        return [
            ['key' => 'entry_number', 'expected' => 1],
            ['key' => 'name', 'expected' => '金田 諭'],
            ['key' => 'number', 'expected' => 4036],
            ['key' => 'rank_number_source', 'expected' => 'A1'],
            ['key' => 'rank_number', 'expected' => 1],
            ['key' => 'branch_number_source', 'expected' => '埼玉'],
            ['key' => 'branch_number', 'expected' => 11],
            ['key' => 'birthplace_number', 'expected' => 11],
            ['key' => 'age', 'expected' => 47],
            ['key' => 'weight', 'expected' => 52.0],
            ['key' => 'flying_count', 'expected' => 0],
            ['key' => 'late_count', 'expected' => 0],
            ['key' => 'average_start_timing', 'expected' => 0.16],
            ['key' => 'national_win_rate', 'expected' => 6.46],
            ['key' => 'national_top_2_percent', 'expected' => 44.03],
            ['key' => 'national_top_3_percent', 'expected' => 70.15],
            ['key' => 'local_win_rate', 'expected' => 7.22],
            ['key' => 'motor_number', 'expected' => 73],
            ['key' => 'motor_top_2_percent', 'expected' => 28.7],
            ['key' => 'boat_number', 'expected' => 149],
            ['key' => 'boat_top_3_percent', 'expected' => 46.15],
        ];
    }
}
