<?php

declare(strict_types=1);

namespace Boatrace\Types\Contracts\Parser;

/**
 * @author shimomo
 */
interface ProgramParser extends Parser
{
    /**
     * @param ?string $value
     * @return array<non-empty-string, mixed>
     */
    public function parseGrade(?string $value): array;

    /**
     * @param ?string $value
     * @return array<non-empty-string, mixed>
     */
    public function parseTitle(?string $value): array;

    /**
     * @param ?string $value
     * @return array<non-empty-string, mixed>
     */
    public function parseSubtitleAndDistance(?string $value): array;

    /**
     * @param ?string $value
     * @return array<non-empty-string, mixed>
     */
    public function parseStabilizer(?string $value): array;

    /**
     * @param ?string $value
     * @return array<non-empty-string, mixed>
     */
    public function parseNumberAndRankNumber(?string $value): array;

    /**
     * @param ?string $value
     * @return array<non-empty-string, mixed>
     */
    public function parseBranchNumberAndBirthplaceNumberAndAgeAndWeight(?string $value): array;

    /**
     * @param ?string $value
     * @return array<non-empty-string, mixed>
     */
    public function parseFlyingCountAndLateCountAndAverageStartTiming(?string $value): array;

    /**
     * @param ?string $value
     * @return array<non-empty-string, mixed>
     */
    public function parseNationalWinRateAndNationalTop23Percent(?string $value): array;

    /**
     * @param ?string $value
     * @return array<non-empty-string, mixed>
     */
    public function parseLocalWinRateAndLocalTop23Percent(?string $value): array;

    /**
     * @param ?string $value
     * @return array<non-empty-string, mixed>
     */
    public function parseMotorNumberAndMotorTop23Percent(?string $value): array;

    /**
     * @param ?string $value
     * @return array<non-empty-string, mixed>
     */
    public function parseBoatNumberAndBoatTop23Percent(?string $value): array;
}
