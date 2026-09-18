local Boosters = {}

-- Types
type BoosterDataCore = {
    ScoreId : string,
    BoostMultiplier : number,
    StackMethod : "AddTime" | "Separate",
    TotalTime : number,
}

type BoosterDataInput = BoosterDataCore & {
    BoosterId : string,
}

export type BoosterData = BoosterDataInput & {
    StartingTime : number,
	TimeStarted : number,
    Bucket : any,
	[number]: BoosterDataInput & {
		StartingTime: number,
		Bucket: Bucket.Bucket,
	}
}

-- Services
local RunService = game:GetService("RunService")

-- Imports
local Signal = require("@pkg/Signal")
local Bucket = require("@pkg/Bucket")

-- Variables
local ActiveBoosters : {[Player] : BoosterData} = {}

-- Properties
Boosters.BoosterApplied = Signal.new()
Boosters.BoosterEnded = Signal.new()

function Boosters.ApplyBooster(Player : Player, BoosterData : BoosterDataInput)
    if not ActiveBoosters[Player] then
        ActiveBoosters[Player] = {} :: any
    end

    if BoosterData.StackMethod == "AddTime" then
        for _, ThisData : BoosterData in ActiveBoosters[Player] do
            if ThisData.BoosterId == BoosterData.BoosterId then
                if ThisData.StackMethod ~= "AddTime" then
                    error("Mismatched stack methods for boosters")
                end

                ThisData.TotalTime += BoosterData.TotalTime
                return
            end
        end
    end

    local ThisBucket = Bucket.new()

    local Data = {
        ScoreId = BoosterData.ScoreId,
        BoostMultiplier = BoosterData.BoostMultiplier,
        BoosterId = BoosterData.BoosterId,
        StackMethod = BoosterData.StackMethod,
        TotalTime = BoosterData.TotalTime,
        StartingTime = os.clock(),
        Bucket = ThisBucket,
    }

    ThisBucket:Add(RunService.Heartbeat:Connect(function()
        if os.clock() - Data.StartingTime >= Data.TotalTime then
            ThisBucket:Destroy()
        end
    end))

    ThisBucket:Add(Player.AncestryChanged:Connect(function()
        task.defer(function()
            if not Player.Parent then
                ThisBucket:Destroy()
            end
        end)
    end))

    ThisBucket:Add(function()
        if not Player.Parent then
            ActiveBoosters[Player] = nil
            return
        end

        local Index = table.find(ActiveBoosters[Player], Data)

        if not Index then
            return
        end

        table.remove(ActiveBoosters[Player], Index)

        if #ActiveBoosters[Player] == 0 then
            ActiveBoosters[Player] = nil
        end

        Boosters.BoosterEnded:Fire(Player, Data)
    end)

    table.insert(ActiveBoosters[Player], Data)
    Boosters.BoosterApplied:Fire(Player, Data)
end

function Boosters.GetActiveBoosters(Player : Player) : BoosterData
    return ActiveBoosters[Player] or {} :: any
end

function Boosters.GetTimeLeftForBooster(Player : Player, BoosterId : string) : number
    if not ActiveBoosters[Player] then
        return 0
    end

    local MaxTimeLeft = 0

    for _, BoosterData : BoosterData in ActiveBoosters[Player] do
        if BoosterData.BoosterId == BoosterId then
            local TimePassed = os.clock() - BoosterData.TimeStarted
            local TimeLeft = BoosterData.TotalTime - TimePassed
            MaxTimeLeft = math.max(TimeLeft, MaxTimeLeft)
        end
    end

    return MaxTimeLeft
end

function Boosters.IsBoosterActive(Player : Player, BoosterId : string) : boolean
    return Boosters.GetTimeLeftForBooster(Player, BoosterId) > 0
end

function Boosters.GetScoreMultiplier(Player : Player, ScoreId : string) : number
    if not ActiveBoosters[Player] then
        return 1
    end

    local Multiplier = 1

    for _, BoosterData : BoosterData in ActiveBoosters[Player] do
        if BoosterData.ScoreId == ScoreId then
            Multiplier *= BoosterData.BoostMultiplier
        end
    end

    return Multiplier
end

return Boosters