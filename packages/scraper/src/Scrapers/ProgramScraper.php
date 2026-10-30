<?php

declare(strict_types=1);

namespace Boatrace\Scraper\Scrapers;

use Boatrace\Core\Concerns\RejectsUndefinedCalls;
use Boatrace\Types\Contracts\Browser\BrowserDispatcher as BrowserDispatcherContract;
use Boatrace\Types\Contracts\Converter\ConverterDispatcher as ConverterDispatcherContract;
use Boatrace\Types\Contracts\Filter\FilterDispatcher as FilterDispatcherContract;
use Boatrace\Types\Contracts\Parser\ProgramParser as ProgramParserContract;
use Boatrace\Types\Contracts\Parser\RacerParser as RacerParserContract;
use Boatrace\Types\Contracts\Scraper\ProgramScraper as ProgramScraperContract;
use Carbon\CarbonImmutable as Carbon;
use DateTimeInterface;
use Symfony\Component\BrowserKit\HttpBrowser;
use Symfony\Component\DomCrawler\Crawler;

/**
 * @author shimomo
 */
final class ProgramScraper implements ProgramScraperContract
{
    use RejectsUndefinedCalls;

    /**
     * @var non-empty-string
     */
    private const string GRADE_PATTERN = '/is-([a-zA-Z0-9]+)/u';

    /**
     * @var non-empty-string
     */
    private const string BASE_URL = 'https://www.boatrace.jp';

    /**
     * @var non-empty-string
     */
    private const string BASE_XPATH = 'descendant-or-self::body/main/div/div/div';

    /**
     * @var non-empty-list<non-empty-string>
     */
    private const array RACER_KEYS = [
        'entry_number',
        'name',
        'number',
        'rank_number_source',
        'rank_number',
        'branch_number_source',
        'branch_number',
        'birthplace_number_source',
        'birthplace_number',
        'age_source',
        'age',
        'weight_source',
        'weight',
        'flying_count_source',
        'flying_count',
        'late_count_source',
        'late_count',
        'average_start_timing',
        'national_win_rate',
        'national_top_2_percent',
        'national_top_3_percent',
        'local_win_rate',
        'local_top_2_percent',
        'local_top_3_percent',
        'motor_number',
        'motor_top_2_percent',
        'motor_top_3_percent',
        'boat_number',
        'boat_top_2_percent',
        'boat_top_3_percent',
    ];

    /**
     * @param \Boatrace\Types\Contracts\Browser\BrowserDispatcher $browser
     * @param \Boatrace\Types\Contracts\Converter\ConverterDispatcher $converter
     * @param \Boatrace\Types\Contracts\Filter\FilterDispatcher $filter
     * @param \Boatrace\Types\Contracts\Parser\RacerParser $racerParser
     * @param \Boatrace\Types\Contracts\Parser\ProgramParser $programParser
     */
    public function __construct(
        private readonly BrowserDispatcherContract $browser,
        private readonly ConverterDispatcherContract $converter,
        private readonly FilterDispatcherContract $filter,
        private readonly RacerParserContract $racerParser,
        private readonly ProgramParserContract $programParser,
    ) {
        //
    }

    /**
     * @param \DateTimeInterface|non-empty-string $date
     * @param int<1, 24> $stadiumNumber
     * @param int<1, 12> $raceNumber
     * @param ?\Symfony\Component\BrowserKit\HttpBrowser $httpBrowser
     * @return array<non-empty-string, mixed>
     */
    #[\Override]
    public function scrape(
        DateTimeInterface|string $date,
        int $stadiumNumber,
        int $raceNumber,
        ?HttpBrowser $httpBrowser = null,
    ): array {
        $date = Carbon::parse($date);

        $scraperFormat = '%s/owpc/pc/race/racelist?hd=%s&jcd=%02d&rno=%d';
        $scraperUrl = sprintf($scraperFormat, self::BASE_URL, $date->format('Ymd'), $stadiumNumber, $raceNumber);
        $scraper = ($httpBrowser ?? $this->browser->create())->request('GET', $scraperUrl);

        $levelFormat = '%s/div[2]/div[3]/ul/li';
        $levelXPath = sprintf($levelFormat, self::BASE_XPATH);

        $baseLevel = 0;
        if ($this->filter->byXPath($scraper, $levelXPath) !== null) {
            $baseLevel = 1;
        }

        $closeTimeFormat = '%s/div[2]/div[2]/table/tbody/tr[1]/td[%s]';
        $closeTimeXPath = sprintf($closeTimeFormat, self::BASE_XPATH, $raceNumber + 1);
        $closeTimeSource = $this->filter->byXPath($scraper, $closeTimeXPath);

        $closedAt = null;
        if ($closeTimeSource !== null) {
            $closedAt = $date->setTimeFromTimeString($closeTimeSource)
                ->format('Y-m-d H:i:s');
        }

        $gradeFormat = '%s/div[1]/div/div[2]';
        $gradeXPath = sprintf($gradeFormat, self::BASE_XPATH);
        $gradeSource = $this->filter->byXPathAsPattern($scraper, $gradeXPath, 'class', self::GRADE_PATTERN);
        $grade = $this->programParser->parseGrade($gradeSource);

        $titleFormat = '%s/div[1]/div/div[2]/h2';
        $titleXPath = sprintf($titleFormat, self::BASE_XPATH);
        $titleSource = $this->filter->byXPath($scraper, $titleXPath);
        $title = $this->programParser->parseTitle($titleSource);

        $subtitleAndDistanceFormat = '%s/div[2]/div[%d]/h3';
        $subtitleAndDistanceXPath = sprintf($subtitleAndDistanceFormat, self::BASE_XPATH, $baseLevel + 3);
        $subtitleAndDistanceSource = $this->filter->byXPath($scraper, $subtitleAndDistanceXPath);
        $subtitleAndDistance = $this->programParser->parseSubtitleAndDistance($subtitleAndDistanceSource);

        $stabilizerFormat = '%s/div[2]/div[%d]/div';
        $stabilizerXPath = sprintf($stabilizerFormat, self::BASE_XPATH, $baseLevel + 3);
        $stabilizerSource = $this->filter->byXPath($scraper, $stabilizerXPath);
        $stabilizer = $this->programParser->parseStabilizer($stabilizerSource);

        $response = [];

        $response['date'] = $date->format('Y-m-d');
        $response['stadium_number'] = $stadiumNumber;
        $response['race_number'] = $raceNumber;
        $response['closed_at'] = $closedAt;

        $response += $grade;
        $response += $title;
        $response += $subtitleAndDistance;
        $response += $stabilizer;

        $response += $this->resolveDayNumber($scraper);
        $response += $this->scrapeRacers($scraper, $baseLevel);

        return $response;
    }

    /**
     * @param \Symfony\Component\DomCrawler\Crawler $scraper
     * @return array{
     *     day_number_source: ?string,
     *     day_number: ?int,
     * }
     */
    private function resolveDayNumber(Crawler $scraper): array
    {
        $dayNumberSourceFormat = '%s/div[2]/div[1]/ul/li[%s]/span/span';

        foreach (range(1, 14) as $index) {
            $dayNumberSourceXPath = sprintf($dayNumberSourceFormat, self::BASE_XPATH, $index);
            $dayNumberSource = $this->filter->byXPath($scraper, $dayNumberSourceXPath);

            if ($dayNumberSource !== null) {
                $dayNumber = match ($dayNumberSource) {
                    '初日' => 1,
                    '最終日' => $this->resolveLastDayNumber($scraper, $index),
                    default => preg_match('/[\p{Nd}]+/u', $dayNumberSource, $matches)
                        ? $this->converter->toDayNumber($matches[0])
                        : null,
                };

                return ['day_number_source' => $dayNumberSource, 'day_number' => $dayNumber];
            }
        }

        return ['day_number_source' => null, 'day_number' => null];
    }

    /**
     * @param \Symfony\Component\DomCrawler\Crawler $scraper
     * @param int $index
     * @return ?int
     */
    private function resolveLastDayNumber(Crawler $scraper, int $index): ?int
    {
        $previousDayNumberSourceFormat = '%s/div[2]/div[1]/ul/li[%s]/a/span';

        foreach (range(1, 14) as $previousIndex) {
            $previousDayNumberSourceXPath = sprintf($previousDayNumberSourceFormat, self::BASE_XPATH, $index - $previousIndex);
            $previousDayNumberSource = $this->filter->byXPath($scraper, $previousDayNumberSourceXPath);

            if ($previousDayNumberSource === null) {
                continue;
            }

            if (preg_match('/[\p{Nd}]+/u', $previousDayNumberSource, $matches)) {
                if (is_int($previousDayNumber = $this->converter->toDayNumber($matches[0]))) {
                    return $previousDayNumber + 1;
                }
            }
        }

        return null;
    }

    /**
     * @param \Symfony\Component\DomCrawler\Crawler $scraper
     * @param int $baseLevel
     * @return array{
     *     racers: array<int, array<non-empty-string, mixed>>,
     * }
     */
    private function scrapeRacers(Crawler $scraper, int $baseLevel): array
    {
        $racers = $this->scrapeProgramTable($scraper, $baseLevel);

        $template = array_fill_keys(self::RACER_KEYS, null);

        $response = ['racers' => []];

        foreach (range(1, 6) as $entryNumberKey) {
            $response['racers'][$entryNumberKey] = array_replace($template, [
                'entry_number' => $entryNumberKey,
            ], $racers[$entryNumberKey] ?? []);
        }

        return $response;
    }

    /**
     * @param \Symfony\Component\DomCrawler\Crawler $scraper
     * @param int $baseLevel
     * @return array<int, array<non-empty-string, mixed>>
     */
    private function scrapeProgramTable(Crawler $scraper, int $baseLevel): array
    {
        $response = [];

        foreach (range(1, 6) as $index) {
            $entryNumberFormat = '%s/div[2]/div[%d]/table/tbody[%s]/tr[1]/td[1]';
            $entryNumberXPath = sprintf($entryNumberFormat, self::BASE_XPATH, $baseLevel + 5, $index);
            $entryNumberSource = $this->filter->byXPath($scraper, $entryNumberXPath);
            $entryNumber = $this->racerParser->parseEntryNumber($entryNumberSource);

            $nameFormat = '%s/div[2]/div[%d]/table/tbody[%s]/tr[1]/td[3]/div[2]/a';
            $nameXPath = sprintf($nameFormat, self::BASE_XPATH, $baseLevel + 5, $index);
            $nameSource = $this->filter->byXPath($scraper, $nameXPath);
            $name = $this->racerParser->parseName($nameSource);

            $numberAndRankNumberFormat = '%s/div[2]/div[%d]/table/tbody[%s]/tr[1]/td[3]/div[1]';
            $numberAndRankNumberXPath = sprintf($numberAndRankNumberFormat, self::BASE_XPATH, $baseLevel + 5, $index);
            $numberAndRankNumberSource = $this->filter->byXPath($scraper, $numberAndRankNumberXPath);
            $numberAndRankNumber = $this->programParser->parseNumberAndRankNumber($numberAndRankNumberSource);

            $branchNumberAndBirthplaceNumberAndAgeAndWeightFormat = '%s/div[2]/div[%d]/table/tbody[%s]/tr[1]/td[3]/div[3]';
            $branchNumberAndBirthplaceNumberAndAgeAndWeightXPath = sprintf($branchNumberAndBirthplaceNumberAndAgeAndWeightFormat, self::BASE_XPATH, $baseLevel + 5, $index);
            $branchNumberAndBirthplaceNumberAndAgeAndWeightSource = $this->filter->byXPath($scraper, $branchNumberAndBirthplaceNumberAndAgeAndWeightXPath);
            $branchNumberAndBirthplaceNumberAndAgeAndWeight = $this->programParser->parseBranchNumberAndBirthplaceNumberAndAgeAndWeight($branchNumberAndBirthplaceNumberAndAgeAndWeightSource);

            $flyingCountAndLateCountAndAverageStartTimingFormat = '%s/div[2]/div[%d]/table/tbody[%s]/tr[1]/td[4]';
            $flyingCountAndLateCountAndAverageStartTimingXPath = sprintf($flyingCountAndLateCountAndAverageStartTimingFormat, self::BASE_XPATH, $baseLevel + 5, $index);
            $flyingCountAndLateCountAndAverageStartTimingSource = $this->filter->byXPath($scraper, $flyingCountAndLateCountAndAverageStartTimingXPath);
            $flyingCountAndLateCountAndAverageStartTiming = $this->programParser->parseFlyingCountAndLateCountAndAverageStartTiming($flyingCountAndLateCountAndAverageStartTimingSource);

            $nationalWinRateAndNationalTop23PercentFormat = '%s/div[2]/div[%d]/table/tbody[%s]/tr[1]/td[5]';
            $nationalWinRateAndNationalTop23PercentXPath = sprintf($nationalWinRateAndNationalTop23PercentFormat, self::BASE_XPATH, $baseLevel + 5, $index);
            $nationalWinRateAndNationalTop23PercentSource = $this->filter->byXPath($scraper, $nationalWinRateAndNationalTop23PercentXPath);
            $nationalWinRateAndNationalTop23Percent = $this->programParser->parseNationalWinRateAndNationalTop23Percent($nationalWinRateAndNationalTop23PercentSource);

            $localWinRateAndLocalTop23PercentFormat = '%s/div[2]/div[%d]/table/tbody[%s]/tr[1]/td[6]';
            $localWinRateAndLocalTop23PercentXPath = sprintf($localWinRateAndLocalTop23PercentFormat, self::BASE_XPATH, $baseLevel + 5, $index);
            $localWinRateAndLocalTop23PercentSource = $this->filter->byXPath($scraper, $localWinRateAndLocalTop23PercentXPath);
            $localWinRateAndLocalTop23Percent = $this->programParser->parseLocalWinRateAndLocalTop23Percent($localWinRateAndLocalTop23PercentSource);

            $motorNumberAndMotorTop23PercentFormat = '%s/div[2]/div[%d]/table/tbody[%s]/tr[1]/td[7]';
            $motorNumberAndMotorTop23PercentXPath = sprintf($motorNumberAndMotorTop23PercentFormat, self::BASE_XPATH, $baseLevel + 5, $index);
            $motorNumberAndMotorTop23PercentSource = $this->filter->byXPath($scraper, $motorNumberAndMotorTop23PercentXPath);
            $motorNumberANDMotorTop23Percent = $this->programParser->parseMotorNumberAndMotorTop23Percent($motorNumberAndMotorTop23PercentSource);

            $boatNumberAndBoatTop23PercentFormat = '%s/div[2]/div[%d]/table/tbody[%s]/tr[1]/td[8]';
            $boatNumberAndMotorTop23PercentXPath = sprintf($boatNumberAndBoatTop23PercentFormat, self::BASE_XPATH, $baseLevel + 5, $index);
            $boatNumberAndBoatTop23PercentSource = $this->filter->byXPath($scraper, $boatNumberAndMotorTop23PercentXPath);
            $boatNumberANDBoatTop23Percent = $this->programParser->parseBoatNumberAndBoatTop23Percent($boatNumberAndBoatTop23PercentSource);

            if (!isset($entryNumber['entry_number'])) {
                $entryNumber['entry_number'] = $index;
            }

            /** @var mixed $entryNumberKey */
            $entryNumberKey = $entryNumber['entry_number'];

            if (!is_int($entryNumberKey) || !in_array($entryNumberKey, range(1, 6), true)) {
                continue;
            }

            $response[$entryNumberKey] ??= [];
            $response[$entryNumberKey] += $entryNumber;
            $response[$entryNumberKey] += $name;
            $response[$entryNumberKey] += $numberAndRankNumber;
            $response[$entryNumberKey] += $branchNumberAndBirthplaceNumberAndAgeAndWeight;
            $response[$entryNumberKey] += $flyingCountAndLateCountAndAverageStartTiming;
            $response[$entryNumberKey] += $nationalWinRateAndNationalTop23Percent;
            $response[$entryNumberKey] += $localWinRateAndLocalTop23Percent;
            $response[$entryNumberKey] += $motorNumberANDMotorTop23Percent;
            $response[$entryNumberKey] += $boatNumberANDBoatTop23Percent;
        }

        return $response;
    }
}
