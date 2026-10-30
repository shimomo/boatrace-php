<?php

declare(strict_types=1);

namespace Boatrace\Scraper\Tests\Parsers;

use BadMethodCallException;
use Boatrace\Scraper\Parsers\ProgramParser;
use Boatrace\Support\Converter\ConverterDispatcher;
use Boatrace\Support\Trimmer\TrimmerDispatcher;
use PHPUnit\Framework\Attributes\Test;
use PHPUnit\Framework\TestCase;

/**
 * @author shimomo
 */
final class ProgramParserTest extends TestCase
{
    /**
     * @psalm-suppress PropertyNotSetInConstructor
     * @var \Boatrace\Scraper\Parsers\ProgramParser
     */
    protected ProgramParser $programParser;

    /**
     * @return void
     */
    #[\Override]
    protected function setUp(): void
    {
        $trimmer = new TrimmerDispatcher();

        $this->programParser = new ProgramParser(new ConverterDispatcher($trimmer), $trimmer);
    }

    /**
     * @return void
     */
    #[Test]
    public function parseGradeMapsBothSuffixesToTheSameGrade(): void
    {
        $this->assertSame(
            ['grade_number_source' => 'SGA', 'grade_number' => 1],
            $this->programParser->parseGrade('SGA')
        );
        $this->assertSame(
            ['grade_number_source' => 'SGB', 'grade_number' => 1],
            $this->programParser->parseGrade('SGB')
        );
    }

    /**
     * @return void
     */
    #[Test]
    public function parseGradeSeparatesPremierFromRegularG1(): void
    {
        $premier = $this->programParser->parseGrade('G1A');
        $regular = $this->programParser->parseGrade('G1B');

        $this->assertNotSame($premier['grade_number'], $regular['grade_number']);
    }

    /**
     * @return void
     */
    #[Test]
    public function parseGradeKeepsSourceWhenNotMapped(): void
    {
        $this->assertSame(
            ['grade_number_source' => 'XX', 'grade_number' => null],
            $this->programParser->parseGrade('XX')
        );
    }

    /**
     * @return void
     */
    #[Test]
    public function parseGradeReturnsNullWhenValueIsEmpty(): void
    {
        $this->assertSame(
            ['grade_number_source' => null, 'grade_number' => null],
            $this->programParser->parseGrade(null)
        );
    }

    /**
     * @return void
     */
    #[Test]
    public function parseNumberAndRankNumberSplitsOnSlash(): void
    {
        $this->assertSame(
            ['number' => 4444, 'rank_number_source' => 'A1', 'rank_number' => 1],
            $this->programParser->parseNumberAndRankNumber('4444 / A1')
        );
    }

    /**
     * @return void
     */
    #[Test]
    public function parseNumberAndRankNumberReturnsNullWhenValueIsEmpty(): void
    {
        $this->assertSame(
            ['number' => null, 'rank_number_source' => null, 'rank_number' => null],
            $this->programParser->parseNumberAndRankNumber('')
        );
    }

    /**
     * @return void
     */
    #[Test]
    public function parseTitleKeepsThePrintedText(): void
    {
        $this->assertSame(
            ['title' => 'ヴィーナスシリーズ'],
            $this->programParser->parseTitle('ヴィーナスシリーズ')
        );
        $this->assertSame(['title' => null], $this->programParser->parseTitle(null));
    }

    /**
     * @return void
     */
    #[Test]
    public function parseStabilizerReturnsTrueWhenLabelIsPrinted(): void
    {
        $this->assertSame(
            ['is_stabilizer_used_source' => '安定板使用', 'is_stabilizer_used' => true],
            $this->programParser->parseStabilizer('安定板使用')
        );
    }

    /**
     * @return void
     */
    #[Test]
    public function parseStabilizerPicksOnlyTheStabilizerLabel(): void
    {
        $this->assertSame(
            ['is_stabilizer_used_source' => '安定板使用', 'is_stabilizer_used' => true],
            $this->programParser->parseStabilizer("進入固定\n\t\t\t安定板使用")
        );
    }

    /**
     * @return void
     */
    #[Test]
    public function parseStabilizerReturnsFalseWhenLabelsAreEmpty(): void
    {
        $this->assertSame(
            ['is_stabilizer_used_source' => null, 'is_stabilizer_used' => false],
            $this->programParser->parseStabilizer('')
        );
        $this->assertSame(
            ['is_stabilizer_used_source' => null, 'is_stabilizer_used' => false],
            $this->programParser->parseStabilizer('進入固定')
        );
    }

    /**
     * @return void
     */
    #[Test]
    public function parseStabilizerReturnsNullWhenLabelsAreMissing(): void
    {
        $this->assertSame(
            ['is_stabilizer_used_source' => null, 'is_stabilizer_used' => null],
            $this->programParser->parseStabilizer(null)
        );
    }

    /**
     * @return void
     */
    #[Test]
    public function throwsBadMethodCallExceptionWhenCallingUndefinedMethod(): void
    {
        $this->expectException(BadMethodCallException::class);
        $this->expectExceptionMessageIs(
            'Call to undefined method `Boatrace\Scraper\Parsers\ProgramParser::ghost()`.'
        );

        /** @psalm-suppress UndefinedMagicMethod */
        $this->programParser->ghost();
    }
}
