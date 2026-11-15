<?php

declare(strict_types=1);

namespace Boatrace\Scraper\Tests\Scrapers;

use Boatrace\Scraper\Tests\MockBrowser;
use Boatrace\Scraper\Tests\ScraperFactory;
use PHPUnit\Framework\Attributes\DataProviderExternal;
use PHPUnit\Framework\Attributes\Test;
use PHPUnit\Framework\TestCase;

/**
 * @author shimomo
 */
final class ProgramScraperTest extends TestCase
{
    /**
     * @var ?array<non-empty-string, mixed>
     */
    private static ?array $cache = null;

    /**
     * @psalm-suppress PropertyNotSetInConstructor
     * @var array<non-empty-string, mixed>
     */
    protected array $response;

    /**
     * @return void
     */
    #[\Override]
    protected function setUp(): void
    {
        self::$cache ??= ScraperFactory::createProgramScraper()
            ->scrape('2026-08-01', 22, 1, MockBrowser::create('program.html'));

        $this->response = self::$cache;
    }

    /**
     * @param non-empty-string $key
     * @param int|float|string|bool|null $expected
     * @return void
     */
    #[Test]
    #[DataProviderExternal(ProgramScraperDataProvider::class, 'raceProvider')]
    public function scrapeReturnsRace(string $key, int|float|string|bool|null $expected): void
    {
        $this->assertSame($expected, $this->response[$key] ?? null);
    }

    /**
     * @param non-empty-string $key
     * @param int|float|string|null $expected
     * @return void
     */
    #[Test]
    #[DataProviderExternal(ProgramScraperDataProvider::class, 'racerProvider')]
    public function scrapeReturnsRacer(string $key, int|float|string|null $expected): void
    {
        $racers = $this->response['racers'];

        $this->assertIsArray($racers);
        $this->assertIsArray($racers[1]);
        $this->assertSame($expected, $racers[1][$key] ?? null);
    }

    /**
     * @return void
     */
    #[Test]
    public function scrapeReturnsSixRacers(): void
    {
        $racers = $this->response['racers'];

        $this->assertIsArray($racers);
        $this->assertCount(6, $racers);
        $this->assertSame([1, 2, 3, 4, 5, 6], array_keys($racers));
    }

    /**
     * @return void
     */
    #[Test]
    public function scrapeReturnsSameKeysForEveryRacer(): void
    {
        $racers = $this->response['racers'];

        $this->assertIsArray($racers);
        $this->assertIsArray($racers[1]);

        $keys = array_keys($racers[1]);

        foreach (range(1, 6) as $entryNumber) {
            $this->assertIsArray($racers[$entryNumber]);
            $this->assertSame($keys, array_keys($racers[$entryNumber]));
        }
    }

    /**
     * @return void
     */
    #[Test]
    public function scrapeReturnsEmptyRacersWhenProgramTableIsMissing(): void
    {
        $response = ScraperFactory::createProgramScraper()
            ->scrape('2026-08-01', 22, 1, MockBrowser::create('stadium.html'));

        $racers = $response['racers'];

        $this->assertIsArray($racers);
        $this->assertCount(6, $racers);
        $this->assertIsArray($racers[3]);
        $this->assertSame(3, $racers[3]['entry_number']);
        $this->assertNull($racers[3]['name']);
        $this->assertNull($racers[3]['motor_top_2_percent']);
        $this->assertCount(30, $racers[3]);
    }

    /**
     * @return void
     */
    #[Test]
    public function scrapeReturnsStabilizerWhenLabelIsPrinted(): void
    {
        $response = ScraperFactory::createProgramScraper()
            ->scrape('2017-10-19', 3, 12, MockBrowser::create('program-stabilizer.html'));

        $this->assertSame('安定板使用', $response['is_stabilizer_used_source']);
        $this->assertTrue($response['is_stabilizer_used']);
    }

    /**
     * @return void
     */
    #[Test]
    public function scrapeReturnsNullStabilizerWhenLabelsAreMissing(): void
    {
        $response = ScraperFactory::createProgramScraper()
            ->scrape('2026-08-01', 22, 1, MockBrowser::create('stadium.html'));

        $this->assertArrayHasKey('is_stabilizer_used', $response);
        $this->assertNull($response['is_stabilizer_used_source']);
        $this->assertNull($response['is_stabilizer_used']);
    }

    /**
     * @return void
     */
    #[Test]
    public function scrapeReturnsFixedCourseWhenLabelIsPrinted(): void
    {
        $response = ScraperFactory::createProgramScraper()
            ->scrape('2026-08-01', 8, 1, MockBrowser::create('program-course-fixed.html'));

        $this->assertSame('進入固定', $response['is_course_fixed_source']);
        $this->assertTrue($response['is_course_fixed']);
        $this->assertNull($response['is_stabilizer_used_source']);
        $this->assertFalse($response['is_stabilizer_used']);
    }

    /**
     * @return void
     */
    #[Test]
    public function scrapeReturnsBothLabelsWhenBothArePrinted(): void
    {
        $response = ScraperFactory::createProgramScraper()
            ->scrape('2026-03-03', 24, 1, MockBrowser::create('program-course-fixed-stabilizer.html'));

        $this->assertSame('安定板使用', $response['is_stabilizer_used_source']);
        $this->assertTrue($response['is_stabilizer_used']);
        $this->assertSame('進入固定', $response['is_course_fixed_source']);
        $this->assertTrue($response['is_course_fixed']);
    }

    /**
     * @return void
     */
    #[Test]
    public function scrapeReturnsNullFixedCourseWhenLabelsAreMissing(): void
    {
        $response = ScraperFactory::createProgramScraper()
            ->scrape('2026-08-01', 22, 1, MockBrowser::create('stadium.html'));

        $this->assertArrayHasKey('is_course_fixed', $response);
        $this->assertNull($response['is_course_fixed_source']);
        $this->assertNull($response['is_course_fixed']);
    }
}
