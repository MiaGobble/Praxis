local Scores = {}

-- Imports
local Signal = require("@pkg/Signal")
local Typer = require("@pkg/Typer")
local Boosters = require("./Boosters")

Scores.OnScoreAdded = Signal.new()
Scores.OnScoreRemoved = Signal.new()

-- Set with DeclareSetScoreCallback
Scores.SetScore = (nil :: any) :: ((Player, string, number) -> ())

-- Set with DeclareGetScoreCallback
Scores.GetScore = (nil :: any) :: ((Player, string) -> (number))

local function AssertScoreCallbacks()
    Typer.TupleAssertion("function", "function")(Scores.SetScore, Scores.GetScore)
end

local function AssertScoreAsNumber(Value : any)
    Typer.Cast(Value)("number")

    if math.round(Value) ~= Value then
        error("Read score was not an integer")
    end
end

function Scores.DeclareSetScoreCallback(Callback : (Player : Player, ScoreType : string, ScoreValue : number) -> nil)
    if Scores.SetScore then
        error("Attempt to declare SetScore callback when it already exists")
    end

    Scores.SetScore = Callback
end

function Scores.DeclareGetScoreCallback(Callback : (Player : Player, ScoreType : string) -> nil)
    if Scores.GetScore then
        error("Attempt to declare GetScore callback when it already exists")
    end

    Scores.GetScore = Callback
end

function Scores.AddScoreForPlayer(Player : Player, ScoreType : string, AddedAmount : number)
    AssertScoreCallbacks()
    AssertScoreAsNumber(AddedAmount)
	
    local ExistingScore = Scores.GetScore(Player, ScoreType)

    AssertScoreAsNumber(ExistingScore)

    ExistingScore = math.floor(ExistingScore + AddedAmount * Boosters.GetScoreMultiplier(Player, ScoreType))
    Scores.SetScore(Player, ScoreType, ExistingScore)
    Scores.OnScoreAdded:Fire(Player, ScoreType, AddedAmount)
end

function Scores.AddScoreForPlayerRaw(Player : Player, ScoreType : string, AddedAmount : number)
    AssertScoreCallbacks()
    AssertScoreAsNumber(AddedAmount)

    local ExistingScore = Scores.GetScore(Player, ScoreType)

    AssertScoreAsNumber(ExistingScore)

    ExistingScore += AddedAmount
    Scores.SetScore(Player, ScoreType, ExistingScore)
    Scores.OnScoreAdded:Fire(Player, ScoreType, AddedAmount)
end

function Scores.RemoveScoreForPlayer(Player : Player, ScoreType : string, RemovedAmount : number)
    AssertScoreCallbacks()
    AssertScoreAsNumber(RemovedAmount)

    local ExistingScore = Scores.GetScore(Player, ScoreType)

    AssertScoreAsNumber(ExistingScore)

    ExistingScore -= RemovedAmount

    if ExistingScore < 0 then
        error("Attempt to remove more score than exists for type " .. ScoreType)
    end

    Scores.SetScore(Player, ScoreType, ExistingScore)
    Scores.OnScoreRemoved:Fire(Player, ScoreType, RemovedAmount)
end

function Scores.HasAtLeast(Player : Player, ScoreType : string, Minimum : number) : boolean
    AssertScoreCallbacks()
    AssertScoreAsNumber(Minimum)

    local ExistingScore = Scores.GetScore(Player, ScoreType)

    AssertScoreAsNumber(ExistingScore)

    if ExistingScore >= Minimum then
        return true
    end

    return false
end

return Scores