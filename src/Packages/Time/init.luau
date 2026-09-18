--[=[
    Utilities related to time, including for daily rewards.

    @class Time
]=]

local Time = {}

-- Constants
local SECONDS_PER_DAY = 24 * 60 * 60

export type DateTimeComponents = {
	Year: number,
	Month: number,
	Day: number,
	Hour: number,
	Minute: number,
	Second: number,
	Millisecond: number,
}

local function GetDateTimeUTC(unixTimestamp : number?) : DateTimeComponents
    if unixTimestamp == nil then
        return DateTime.now():ToUniversalTime() :: DateTimeComponents
    end

    return DateTime.fromUnixTimestamp(unixTimestamp):ToUniversalTime() :: DateTimeComponents
end

--[=[
    @param unixTimestamp number?
    @return number

    Returns the current unix timestamp in UTC, or the inputted timestamp if provided.
]=]

function Time.GetUnixTimestampUTC(unixTimestamp : number?) : number
    if unixTimestamp ~= nil then
        return unixTimestamp
    end

    return DateTime.now().UnixTimestamp
end

--[=[
    @param unixTimestamp number?
    @return DateTime

    Returns a `DateTime` converted to universal time.
]=]

function Time.GetDateTimeUTC(unixTimestamp : number?) : DateTimeComponents
    return GetDateTimeUTC(unixTimestamp)
end

--[=[
    @param unixTimestamp number?
    @return number

    Returns the unix timestamp for the start of the UTC day.
]=]

function Time.GetStartOfDayUTC(unixTimestamp : number?) : number
    local dateValue = GetDateTimeUTC(unixTimestamp)

    return DateTime.fromUniversalTime(
        dateValue.Year,
        dateValue.Month,
        dateValue.Day,
        0,
        0,
        0,
        0
    ).UnixTimestamp
end

--[=[
    @param unixTimestamp number?
    @return number

    Returns the unix timestamp for the start of the next UTC day.
]=]

function Time.GetStartOfNextDayUTC(unixTimestamp : number?) : number
    return Time.GetStartOfDayUTC(unixTimestamp) + SECONDS_PER_DAY
end

--[=[
    @param unixTimestamp number?
    @return number

    Returns the amount of seconds until the next UTC day begins.
]=]

function Time.GetSecondsUntilNextDayUTC(unixTimestamp : number?) : number
    local currentTimestamp = Time.GetUnixTimestampUTC(unixTimestamp)
    return Time.GetStartOfNextDayUTC(currentTimestamp) - currentTimestamp
end

--[=[
    @param firstUnixTimestamp number
    @param secondUnixTimestamp number
    @return boolean

    Returns `true` if both timestamps occur on the same UTC day.
]=]

function Time.IsSameDayUTC(firstUnixTimestamp : number, secondUnixTimestamp : number) : boolean
    return Time.GetStartOfDayUTC(firstUnixTimestamp) == Time.GetStartOfDayUTC(secondUnixTimestamp)
end

--[=[
    @param earlierUnixTimestamp number
    @param laterUnixTimestamp number
    @return number

    Returns the whole UTC day difference between two timestamps.
]=]

function Time.GetDayDifferenceUTC(earlierUnixTimestamp : number, laterUnixTimestamp : number) : number
    local earlierStart = Time.GetStartOfDayUTC(earlierUnixTimestamp)
    local laterStart = Time.GetStartOfDayUTC(laterUnixTimestamp)

    return math.floor((laterStart - earlierStart) / SECONDS_PER_DAY)
end

--[=[
    @param totalSeconds number
    @return string

    Converts a time duration in seconds to a formatted string of `xx:xx:xx`.
]=]

function Time.FormatSecondsToClockString(totalSeconds : number) : string
    local clampedSeconds = math.max(0, math.floor(totalSeconds))
    local hours = math.floor(clampedSeconds / 3600)
    local minutes = math.floor((clampedSeconds % 3600) / 60)
    local seconds = clampedSeconds % 60

    return string.format("%02d:%02d:%02d", hours, minutes, seconds)
end

--[=[
    @param lastClaimTimestampUTC number?
    @param currentTimestampUTC number?
    @return boolean

    Returns `true` if a daily reward can be claimed.
]=]

function Time.CanClaimDailyReward(lastClaimTimestampUTC : number?, currentTimestampUTC : number?) : boolean
    if lastClaimTimestampUTC == nil then
        return true
    end

    local currentTimestamp = Time.GetUnixTimestampUTC(currentTimestampUTC)
    return not Time.IsSameDayUTC(lastClaimTimestampUTC, currentTimestamp)
end

--[=[
    @param lastClaimTimestampUTC number?
    @param currentTimestampUTC number?
    @return boolean

    Returns `true` if more than one UTC day has passed since the last claim.
    This is useful for resetting daily reward streaks.
]=]

function Time.WasDailyRewardStreakMissed(lastClaimTimestampUTC : number?, currentTimestampUTC : number?) : boolean
    if lastClaimTimestampUTC == nil then
        return false
    end

    local currentTimestamp = Time.GetUnixTimestampUTC(currentTimestampUTC)
    return Time.GetDayDifferenceUTC(lastClaimTimestampUTC, currentTimestamp) > 1
end

return Time