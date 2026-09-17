--[=[
    A collection of utilities for progression-related development.

    @class ProgressionUtils
]=]

local ProgressionUtils = {}

-- Imports
local Quests = require("@self/Quests")
local Scores = require("@self/Scores")
local Boosters = require("@self/Boosters")
local Inventory = require("@self/Inventory")

--[=[
    Utilities for managing quest data and progress.

    ### `Quests.MakeQuest : (QuestData : QuestData) -> Quest`
    Creates a quest instance that can be started and progressed by players.

    ### `Quest`
    Created by `Quests.MakeQuest`.

    ```lua
    type Quest = QuestData & {
        OnStepIncrement : Types.Signal<Player, number>, -- A signal that fires when a step of a quest is incremented
        OnStart : Types.Signal<Player>, -- A signal that fires when a quest is started
        OnComplete : Types.Signal<Player>, -- A signal that fires when a quest is completed
        OnStepComplete : Types.Signal<Player>, -- A signal that fires when a quest step is completed

        Start : (Player : Player, ExistingProgress : QuestProgress) -> QuestProgress, -- A function that takes a player and their existing progress, and begins the quest. Returns the updated quest progress table.
        MakeProgress : (Player : Player, ExistingProgress : QuestProgress, StepProgressed : number, AmountProgressed : number) -> QuestProgress, -- A function that takes a player and their existing progress, as well as the step progress and the amount progressed, and makes progress on that quest step. If the quest is complete, it will be marked as complete. Returns current the quest progress
    }
    ```

    To start a quest, call `Quest.Start()`, like so:

    ```lua
    local NewProgress = ExampleQuest.Start(Player, ExistingProgress)
    ```

    Then, when progressing a quest, call `Quest.MakeProgress()`, like so:

    ```lua
    local NewProgress = ExampleQuest.MakeProgress(Player, ExistingProgress, 1, 1)
    ```

    ### `Quests.GetBlankProgressTable : () -> QuestProgress`
    Returns a dictionary of blank quest progress of `QuestProgress` type.

    ### `Quests.SerializeProgressTable : (Progress : QuestProgress) -> string`
    Equivalent to `HttpService:JSONEncode()`; serializes a progress table to a string.

    ### `Quests.DeserializeProgressTable : (ProgressSerialized : string) -> QuestProgress`
    Equivalent to `HttpService:JSONDecode()`; deserializes a string to a table of `QuestProgress` type.

    ### `Quests.HasCompletedQuest : (ExistingProgress : QuestProgress, QuestId : string)`
    Checks if a quest is completed, given the existing progress and quest id.

    ### `type QuestData`
    QuestData is a dictionary of the following type:

    ```lua
    type QuestData = {
        QuestId : string, -- An indentifier string for the quest, must be unique
        QuestName : string?, -- The frontend name for the quest
        QuestDescription : string?, -- A frontend description of the quest
        QuestReward : (Player : Player) -> nil, -- The quest reward, which is a function that takes the player completing the quest
        RequireStepsInOrder : boolean, -- If true, QuestSteps must be done in order

        QuestSteps : {[number] : { -- Array of quest steps
            MaxProgressionAmount : number, -- For this step, what the maximum count of an action is
            StepName : string?, -- The frontend name for the step
            StepDescription : string?, -- The frontend description for the step
        }}
    }
    ```

    ### `type QuestProgress`
    QuestProgress is a dictionary of the following type:

    ```lua
    type QuestProgress = {
    CompletedQuestIds : {string}, -- Quest ids representing completed quests

    QuestsInProgress : { -- Quest data for in-progress quests
            {
                QuestId : string, -- Id of in-progress quest
                StepProgress : {[number] : number}, -- Progress of quest steps
                StepsCompleted : number, -- Number of steps completed
                PercentCompleted : number, -- Percent of steps completed
            }
        }
    }
    ```

    @prop Quests Quests
    @within ProgressionUtils
]=]

ProgressionUtils.Quests = Quests

--[=[
    Utilities for managing scores, which is helpful for things like XP or currency.

    :::warning

    Make sure to guarantee that you call `DeclareSetScoreCallback` and `DeclareGetScoreCallback` before `SetScore` and `GetScore`.
    Not doing so will lead to a race condition.

    :::

    ### `Scores.DeclareSetScoreCallback : (Callback : (Player, string, number))`
    Sets `Scores.SetScore` to a callback used by the rest of the module.

    ### `Scores.DeclareGetScoreCallback : (Callback : (Player, string))`
    Sets `Scores.GetScore` to a callback used by the rest of the module.

    ### `Scores.SetScore : (Player : Player, ScoreType : string, ScoreValue : number)`
    Sets the score for a player, given a score type and value. **This function doesn't exist until `Scores.DeclareSetScoreCallback()` is called!**

    ### `Scores.GetScore : (Player : Player, ScoreType : string)`
    Gets the score for a player, given a score type. **This function doesn't exist until `Scores.DeclareGetScoreCallback()` is called!**

    ### `Scores.AddScoreForPlayer : (Player : Player, ScoreType : string, AddedAmount : number)`
    Adds score to a player, given the type and added amount. This can be multiplied by boosters.

    ### `Scores.AddScoreForPlayerRaw : (Player : Player, ScoreType : string, AddedAmount : number)`
    Adds score to a player, given the type and added amount. This can **not** be multiplied by boosters.

    ### `Scores.RemoveScoreForPlayer : (Player : Player, ScoreType : string, RemovedAmount : number)`
    Removes score from a player, given the type and removed amount. This is never affected by boosters.

    ### `Scores.HasAtLeast : (Player : Player, ScoreType : number, Minimum : number) -> boolean`
    Returns `true` if the player has an amount of score of certain type.

    @prop Scores Scores
    @within ProgressionUtils
]=]

ProgressionUtils.Scores = Scores

--[=[
    Utilities for applying boosters, which affects scores.

    ### `Boosters.ApplyBooster : (Player : Player, BoosterData : BoosterDataInput)`
    Applies a booster to a player, given the inputted booster data as a table. Automatically cleans up after the time is complete, and does not carry between servers.

    ### `Boosters.BoosterApplied : Signal<Player, BoosterData>`
    A signal that fires when a booster is applied to a player.

    ### `Boosters.BoosterEnded : Signal<Player, BoosterData>`
    A signal that fires when a booster is removed from a player.

    ### `Boosters.GetActiveBoosters : (Player : Player) -> {BoosterData}`
    Gets all active boosters for player.

    ### `Boosters.GetTimeLeftForBooster : (Player : Player, BoosterId : string) -> number`
    Gets time left for newest booster of given id for a player. If no booster is in progress for the player, this returns `0`.

    ### `Boosters.IsBoosterActive : (Player : Player, BoosterId : string) -> boolean`
    Returns `true` if the player is using at least one booster of the given id.

    ### `Boosters.GetScoreMultiplier : (Player : Player, ScoreId : string) -> number`
    Gets a multiplier applied to a score given the boosters from a player. If no boosters are affecting that score, this returns `1`.

    ### `type BoosterDataInput`
    BoosterDataInput is the following type:

    ```lua
    type BoosterDataInput = {
        BoosterId : string, -- The unique identifier for the booster
        ScoreId : string, -- The id of the score affected by the booster
        BoostMultiplier : number, -- The multiplier applied to the score (e.g. 1.5 to give +50% boost)
        StackMethod : "AddTime" | "Separate", -- Declares how the booster stacks with the same type. AddTime adds time, Separate adds a separate boost which stacks multiplier
        TotalTime : number, -- How long the boost lasts, in seconds
    }
    ```

    ### `type BoosterData`
    BoosterData is the following type:

    ```lua
    type BoosterData = BoosterDataInput & {
        StartingTime : number,
        Bucket : any,
    }
    ```

    @prop Boosters Boosters
    @within ProgressionUtils
]=]

ProgressionUtils.Boosters = Boosters

--[=[
    Utilities for basic inventory management.

    ### `Inventory.AddItemInventory : (InventoryData : InventoryData, ItemData : ItemDataInput, MaxStack : number) -> InventoryData`
    Adds/stacks an item in an inventory given existing inventory data, the item data, and max stack. If a stack of an item goes above `MaxStack`, it will automatically create a new stack.
    Returns the new inventory data.

    ### `Inventory.RemoveItemFromInventory : (InventoryData : InventoryData, ItemId : string) -> InventoryData`
    Removes an item in an inventory given existing inventory data and item id. If the item has more than one in a stack, it just reduces the quantity in the stack by 1.
    Returns the new inventory data.

    ### `Inventory.DoesOwnItem : (InventoryData : InventoryData, ItemId : string) -> boolean`
    Returns `true` if an item of given id is in the inventory data.

    ### `Inventory.GetBlankInventoryData : () -> InventoryData`
    Returns a blank inventory formatted to `InventoryData` type.

    ### `Inventory.SerializeInventory : (InventoryData : InventoryData) : string`
    Equivalent to `HttpService:JSONEncode()`; turns inventory data into a string.

    ### `Inventory.DeserializeInventory : (SerializedData : string) : InventoryData`
    Equivalent to `HttpService:JSONDecode()`; turns serialized inventory data into an inventory data table.

    ### `type ItemDataInput`
    This is the type for ItemDataInput:

    ```lua
    type ItemDataInput = {
        ItemId : string, -- The unique id of the item 
        [string] : any, -- Any other properties you want to add, all optional and not used by the system
    }
    ```

    ### `type ItemData`
    This is the type for ItemData:

    ```lua
    type ItemData = ItemDataInput & {
        Quantity : number,
    }
    ```

    ### `type InventoryData`
    This is the type for InventoryData:

    ```lua
    type InventoryData = {
        Items : {ItemData}
    }
    ```

    @prop Inventory Inventory
    @within ProgressionUtils
]=]

ProgressionUtils.Inventory = Inventory

return ProgressionUtils