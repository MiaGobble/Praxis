--[=[
    Utilities for checking and awarding Roblox badges with save-table support.

    @class Badges
]=]

local Badges = {}

-- Constants
local SERIALS_DATASTORE_NAME = "Praxis.Badges.Serials"
local SERIALS_KEY_PREFIX = "Badge_"

-- Services
local BadgeService = game:GetService("BadgeService")
local RunService = game:GetService("RunService")

-- Import
local Signal = require("@pkg/Signal")
local DataStore = require("@pkg/DataStore")

if RunService:IsClient() then
	-- Note: Returns an empty table at this point, but we should not return a new empty table literal as the type solver
	-- won't be able to figure out the types.
    return Badges
end

-- Variables
local SerialDataStore = DataStore.CreateStore({
    Name = SERIALS_DATASTORE_NAME,
    Template = {
        Value = 0,
    },
})

-- Types
export type BadgeAwardData = {
    BadgeId : number,
    AwardTimestampUTC : number,
    SerialNumber : number,
}

export type BadgeSaveData = {BadgeAwardData}

local function FindBadgeEntry(BadgeId : number, BadgeSaveData : BadgeSaveData?) : (BadgeAwardData?, number?)
    if not BadgeSaveData then
        return nil, nil
    end

    for Index, Entry in BadgeSaveData do
        if Entry.BadgeId == BadgeId then
            return Entry, Index
        end
    end

    return nil, nil
end

--[=[
    Checks badge ownership using only `BadgeSaveData`.

    @param BadgeId number
    @param BadgeSaveData BadgeSaveData?
    @return boolean
]=]

function Badges.SoftCheckBadgeOwnership(BadgeId : number, BadgeSaveData : BadgeSaveData?) : boolean
    local Entry = FindBadgeEntry(BadgeId, BadgeSaveData)
    return Entry ~= nil
end

--[=[
    Checks badge ownership using both `BadgeSaveData` and `BadgeService.UserHasBadgeAsync`.

    @param Player Player
    @param BadgeId number
    @param BadgeSaveData BadgeSaveData?
    @return boolean
]=]

function Badges.HardCheckBadgeOwnership(Player : Player, BadgeId : number, BadgeSaveData : BadgeSaveData?) : boolean
    if Badges.SoftCheckBadgeOwnership(BadgeId, BadgeSaveData) then
        return true
    end

    local Success, OwnsBadgeOrError = pcall(BadgeService.UserHasBadgeAsync, BadgeService, Player.UserId, BadgeId)

    if not Success then
        error("BadgeService.UserHasBadgeAsync failed: " .. tostring(OwnsBadgeOrError))
    end

    return OwnsBadgeOrError
end

--[=[
    Awards a badge if the player does not already own it.

    If `BadgeSaveData` is provided, a new entry is inserted in this format:
    `{BadgeId : number, AwardTimestampUTC : number, SerialNumber : number}`

    @param Player Player
    @param BadgeId number
    @param BadgeSaveData BadgeSaveData?
    @return boolean -- Whether this call awarded the badge.
    @return BadgeAwardData? -- The award info for this badge.
]=]

function Badges.AwardBadge(Player : Player, BadgeId : number, BadgeSaveData : BadgeSaveData?) : (boolean, BadgeAwardData?)
    if Badges.HardCheckBadgeOwnership(Player, BadgeId, BadgeSaveData) then
        return false, Badges.GetBadgeAwardInfo(BadgeId, BadgeSaveData)
    end

    local AwardSuccess, AwardError = pcall(BadgeService.AwardBadgeAsync, BadgeService, Player.UserId, BadgeId)

    if not AwardSuccess then
        error("BadgeService.AwardBadge failed: " .. tostring(AwardError))
    end

    local SerialData = DataStore.Update(SerialDataStore, SERIALS_KEY_PREFIX .. tostring(BadgeId), function(SaveData: { Value: number }): { Value: number }
        SaveData.Value += 1
        return SaveData
    end)

    if type(SerialData) ~= "table" or type(SerialData.Value) ~= "number" then
        error("Serial counter update returned invalid data")
    end

    local AwardInfo : BadgeAwardData = {
        BadgeId = BadgeId,
        AwardTimestampUTC = DateTime.now().UnixTimestamp,
        SerialNumber = SerialData.Value,
    }

    if BadgeSaveData then
        table.insert(BadgeSaveData, AwardInfo)
    end

    Badges.BadgeAwarded:Fire(Player, AwardInfo, BadgeSaveData)

    return true, AwardInfo
end

--[=[
    Gets all awarded badges from save data.

    @param BadgeSaveData BadgeSaveData?
    @return BadgeSaveData
]=]

function Badges.GetAllAwardedBadges(BadgeSaveData : BadgeSaveData?) : BadgeSaveData
    if not BadgeSaveData then
        return {}
    end

    return table.clone(BadgeSaveData)
end

--[=[
    Gets saved award info for a specific badge.

    @param BadgeId number
    @param BadgeSaveData BadgeSaveData?
    @return BadgeAwardData?
]=]

function Badges.GetBadgeAwardInfo(BadgeId : number, BadgeSaveData : BadgeSaveData?) : BadgeAwardData?
    local Entry = FindBadgeEntry(BadgeId, BadgeSaveData)

    if not Entry then
        return nil
    end

    return table.clone(Entry)
end

--[=[
    @prop BadgeAwarded Signal<(Player, BadgeAwardData, BadgeSaveData?) -> ()> -- Fires when a badge is awarded from module.
    @within Badges
]=]

Badges.BadgeAwarded = Signal.new() :: Signal.Signal<Player, BadgeAwardData, BadgeSaveData?>

return Badges
