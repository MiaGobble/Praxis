local Quests = {}

-- Services
local HttpService = game:GetService("HttpService")

-- Imports
local Signal = require("@pkg/Signal")

-- Types extended
export type QuestData = {
    QuestId : string,
    QuestName : string?,
    QuestDescription : string?,
    QuestReward : (Player : Player) -> nil,
    RequireStepsInOrder : boolean,

    QuestSteps : {[number] : {
        MaxProgressionAmount : number,
        StepName : string?,
        StepDescription : string?,
    }}
}

export type QuestProgress = {
    CompletedQuestIds : {string},

    QuestsInProgress : {
        {
            QuestId : string,
            StepProgress : {[number] : number},
            StepsCompleted : number,
            PercentCompleted : number,
        }
    }
}

export type Quest = QuestData & {
    OnStepIncrement : Signal.Signal<Player, number>,
    OnStart : Signal.Signal<Player>,
    OnComplete : Signal.Signal<Player>,
    OnStepComplete : Signal.Signal<Player>,

    Start : (Player : Player, ExistingProgress : QuestProgress) -> QuestProgress,
    MakeProgress : (Player : Player, ExistingProgress : QuestProgress, StepProgressed : number, AmountProgressed : number) -> QuestProgress,
}

local function RequireIndexes(Table : {[any] : any} | {}, Indexes : {any}, ObjectPrefix : string)
    for _, RequiredIndex in Indexes do
        if Table[RequiredIndex] == nil then
            error(`{ObjectPrefix} requires index {RequiredIndex}`)
        end
    end
end

function Quests.MakeQuest(QuestData : QuestData) : Quest
    local Quest = table.clone(QuestData) :: Quest

    RequireIndexes(QuestData, {"QuestId", "RequireStepsInOrder", "QuestSteps"}, "Quest")
    RequireIndexes(QuestData.QuestSteps, {1}, "Quest.QuestSteps")

    for Index, QuestStep in QuestData.QuestSteps do
        RequireIndexes(QuestStep, {"MaxProgressionAmount"}, `Quest.QuestSteps[{Index}]`)
    end

    Quest.OnStepIncrement = Signal.new()
    Quest.OnStart = Signal.new()
    Quest.OnComplete = Signal.new()
    Quest.OnStepComplete = Signal.new()

    function Quest.Start(Player : Player, ExistingProgress : QuestProgress) : QuestProgress
        if not Player then
            error("Can not start quest without player")
        end

        if not ExistingProgress then
            error("Can not start quest without ExistingProgress")
        end

        for _, QuestInProgress in ExistingProgress.QuestsInProgress do
            if QuestInProgress.QuestId == Quest.QuestId then
                error("Attempt to start a quest already in progress")
            end
        end

        local BlankStepProgress = {}

        for StepIndex, _ in Quest.QuestSteps do
            BlankStepProgress[StepIndex] = 0
        end

        table.insert(ExistingProgress.QuestsInProgress, {
            QuestId = Quest.QuestId,
            StepProgress = BlankStepProgress,
            StepsCompleted = 0,
            PercentCompleted = 0,
        })

        Quest.OnStart:Fire(Player)

        return ExistingProgress
    end

    function Quest.MakeProgress(Player : Player, ExistingProgress : QuestProgress, StepProgressed : number, AmountProgressed : number) : QuestProgress
        if not Player then
            error("Can not progress quest without player")
        end

        if not ExistingProgress then
            error("Can not progress quest without ExistingProgress")
        end

        if not StepProgressed then
            error("Can not progress quest without StepProgressed")
        end

        if not AmountProgressed then
            error("Can not progress quest without AmountProgressed")
        end
       
        local ProgressIndex = nil

        for Index, QuestInProgress in ExistingProgress.QuestsInProgress do
            if QuestInProgress.QuestId == Quest.QuestId then
                ProgressIndex = Index
                break
            end
        end

        if not ProgressIndex then
            error("Attempt to make progress on a quest that wasn't started")
        end

        local SubTable = ExistingProgress.QuestsInProgress[ProgressIndex]

        if not SubTable.StepProgress[StepProgressed] then
            error("Attempt to progress quest step that doesn't exist")
        end

        if SubTable.StepProgress[StepProgressed] >= Quest.QuestSteps[StepProgressed].MaxProgressionAmount then
            return ExistingProgress -- Don't progress a complete step
        end

        if SubTable.StepsCompleted + 1 < StepProgressed and Quest.RequireStepsInOrder then
            return ExistingProgress -- Don't progress out of order
        end

        local NewAmount = math.min(SubTable.StepProgress[StepProgressed] + AmountProgressed, Quest.QuestSteps[StepProgressed].MaxProgressionAmount)

        SubTable.StepProgress[StepProgressed] = NewAmount

        if NewAmount >= Quest.QuestSteps[StepProgressed].MaxProgressionAmount then
            -- Completed step

            SubTable.StepsCompleted += 1
            SubTable.PercentCompleted = SubTable.StepsCompleted / #Quest.QuestSteps

            Quest.OnStepComplete:Fire(Player)
            
            if SubTable.PercentCompleted == 1 then
                -- Completed quest

                table.insert(ExistingProgress.CompletedQuestIds, Quest.QuestId)
                table.remove(ExistingProgress.QuestsInProgress, ProgressIndex)
                Quest.OnComplete:Fire(Player)
                
                if Quest.QuestReward then
                    task.spawn(Quest.QuestReward, Player)
                end
            end
        end

        return ExistingProgress
    end

    return Quest
end

function Quests.GetBlankProgressTable() : QuestProgress
    local BlankProgress : QuestProgress = {
        CompletedQuestIds = {},
        QuestsInProgress = {},
    }

    return BlankProgress
end

function Quests.SerializeProgressTable(Progress : QuestProgress) : string
    return HttpService:JSONEncode(Progress)
end

function Quests.DeserializeProgressTable(ProgressSerialized : string) : QuestProgress
    return HttpService:JSONDecode(ProgressSerialized)
end

function Quests.HasCompletedQuest(ExistingProgress : QuestProgress, QuestId : string) : boolean
    if table.find(ExistingProgress.CompletedQuestIds, QuestId) then
        return true
    end

    return false
end

return Quests