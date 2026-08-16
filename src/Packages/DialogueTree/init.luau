--[=[
    @class DialogueTree

    Backend code to process dialogue trees, with built-in functionality for sessions and memory. Uses signals to communicate with the front-end.
]=]

local DialogueTree = {}
DialogueTree.__index = DialogueTree

-- Types
export type DialogueMemory = {[any] : any}
export type Data = string | {Data} | (self : DialogueTree, player : Player) -> Data

export type Options = {{
    Input : string,
    Response : DialogueTreeData,
}} | (self : DialogueTree, player : Player) -> {{
    Input : string,
    Response : DialogueTreeData?,
}}

export type DialogueTreeData = {
    Text : Data,
    Options : Options,
}

export type Dialogue = {
    CharacterName : string,
    DialogueTreeData : DialogueTreeData,
}

-- Imports
local Signal = require("@pkg/Signal")

-- Types Extended
export type Session = {
    Memory : DialogueMemory,
    ShowNext : Signal.Signal<string, Options>,
    Respond : Signal.Signal<number?>,
    CurrentData : DialogueTreeData,
    TextProcessMetadata : any,
}

export type DialogueTree = typeof(setmetatable({}, DialogueTree)) & {
    Sessions : {[Player] : Session},
    Dialogue : Dialogue,
}

local function ProcessTextAsync(self : DialogueTree, player : Player, forcedText : Data?)
    local Session : Session = self.Sessions[player]
    local Text = forcedText or Session.CurrentData.Text

    local function ProcessOptions()
        if Session.TextProcessMetadata and Session.TextProcessMetadata.ForcedOptions then
            return Session.TextProcessMetadata.ForcedOptions
        elseif typeof(Session.CurrentData.Options) == "function" then
            return Session.CurrentData.Options(self, player)
        else
            return Session.CurrentData.Options
        end
    end

    if typeof(Text) == "string" then
        Session.ShowNext:Fire(Text, ProcessOptions())
    elseif typeof(Text) == "table" then
        if Session.TextProcessMetadata then
            Session.TextProcessMetadata.Index += 1
        else
            Session.TextProcessMetadata = {
                Index = 1,
                ForcedOptions = {
                    {
                        Input = "...",
                        Response = {Text = ""},
                        IsDummy = true,
                    },
                }
            }
        end

        if Session.TextProcessMetadata.Index == #Text then
            Session.TextProcessMetadata = nil
            Session.ShowNext:Fire(Text[#Text] :: string, ProcessOptions())
        else
            Session.ShowNext:Fire(Text[Session.TextProcessMetadata.Index] :: string, ProcessOptions())
        end
    elseif typeof(Text) == "function" then
        ProcessTextAsync(self, player, Text(self, player))
        return
    end

    Session.Respond:Once(function(pickedOptionIndex : number?)
        if pickedOptionIndex then
            local pickedOption = ProcessOptions()[pickedOptionIndex]

            if not pickedOption then
                warn(`Attempted to pick option {pickedOptionIndex} when it does not exist`)
                return
            end

            if pickedOption.Response then
                if pickedOption.IsDummy then
                    ProcessTextAsync(self, player)
                else
                    Session.CurrentData = pickedOption.Response
                    ProcessTextAsync(self, player)
                end
            else
                self:End(player)
            end
        else
            self:End(player)
        end
    end)
end

--[=[
    @param Dialogue Dialogue
    @return DialogueTree

    Creates a new DialogueTree instance with the given dialogue data.

    Example:

    ```lua
    local Praxis = require(game.ReplicatedStorage.Praxis)

    return Praxis.DialogueTree.new({
        CharacterName = "Joe",
        
        DialogueTreeData = {
            Text = function(self, player : Player)
                if self:Recall(player, "HasMet") then
                    return "Hello again! What do you need?"
                else
                    return "Oh, hello there, nice to meet you! How can I help?"
                end
            end,
            
            Options = function(self, player : Player)
                if self:Recall(player, "HasMet") then
                    return {
                        {
                            Input = "Nothing",
                        },
                        
                        {
                            Input = "Can you tell me more?",
                            
                            Response = {
                                Text = {"Yes!", "I am the color blue!", "And not green!"}
                            }
                        }
                    }
                else
                    return {
                        {
                            Input = "Tell me about yourself",
                            
                            Response = {
                                Text = {"Sure!", "I am awesome, swag, and cool", "And that's all!"}
                            }
                        }
                    }
                end
            end,
        }
    })
    ```
]=]

function DialogueTree.new(Dialogue : Dialogue) : DialogueTree
    local self = setmetatable({}, DialogueTree) :: DialogueTree

    self.Sessions = {}
    self.Dialogue = Dialogue

    return self
end

--[=[
    @param player Player
    @param memory DialogueMemory?
    @return Signal.Signal<string, Options>

    Starts a new dialogue session for the given player. If a session already exists for the player, a warning will be issued and no new session will be created.

    Example:

    ```lua
    local TestDialogue = require(path.to.dialogue) -- Using our example from DialogueTree.new

    local SessionSignal = TestDialogue:Converse(player)

    if SessionSignal then
        SessionSignal:Connect(function(text : string, options : Options)
            print(`Showing text: {text}`) -- Text that shows in dialogue box

            for index, option in options do
                print(`Option {index}: {option.Input}`)
            end
        end)
    end
    ```
]=]

function DialogueTree.Converse(self : DialogueTree, player : Player, memory : DialogueMemory?) : Signal.Signal<string, Options>
    if self.Sessions[player] then
		-- Note: This should probably error instead, but I am preserving the original behavior here.
        warn(`Attempted to start session when player {player} already has active session`)
		return nil :: any
    end

    local Session : Session = {
        Memory = memory or {},
        ShowNext = Signal.new(),
        Respond = Signal.new(),
        CurrentData = self.Dialogue.DialogueTreeData,
        TextProcessMetadata = nil,
    }

    task.defer(ProcessTextAsync, self, player, nil)

    self.Sessions[player] = Session

    return Session.ShowNext
end

--[=[
    @param player Player

    Ends the dialogue session for the given player. If no session exists for the player, a warning will be issued and no action will be taken.
]=]

function DialogueTree.End(self : DialogueTree, player : Player)
    if not self.Sessions[player] then
        warn(`Attempted to end session when player {player} does not have active session`)
        return
    end

    local Session : Session = self.Sessions[player]

    Session.ShowNext:Destroy()
    Session.Respond:Destroy()
    self.Sessions[player] = nil
    Session.ShowNext:Fire() -- TODO: verify if this is intentional
end

--[=[
    @param player Player
    @param pickedOptionIndex number?

    Responds to the current dialogue session for the given player with the selected option index. If no session exists for the player, a warning will be issued and no action will be taken.

    If pickedOptionIndex is nil, the session will be ended. This is the most common way to end dialogue sessions, as it allows the front-end to handle the end of the session gracefully.

    Example:

    ```lua
    local TestDialogue = require(path.to.dialogue) -- Using our example from DialogueTree.new

    -- Run code elsewhere to begin conversation

    local function OnOptionPicked(player : Player, pickedOptionIndex : number?) -- Mock function for UI button that picks option
        TestDialogue:Respond(player, pickedOptionIndex)
    end
    ```
]=]

function DialogueTree.Respond(self : DialogueTree, player : Player, pickedOptionIndex : number?)
    if not self.Sessions[player] then
        warn(`Attempted to respond when player {player} does not have active session`)
        return
    end

    local Session : Session = self.Sessions[player]

    Session.Respond:Fire(pickedOptionIndex)
end

--[=[
    @param player Player
    @param index any
    @param value any

    Remembers a value in the session's memory, using the original memory table inserted with `DialogueTree:Converse`. If no session exists for the player, a warning will be issued and no action will be taken.

    Example:

    ```lua
    local TestDialogue = require(path.to.dialogue) -- Using our example from DialogueTree.new

    -- Run code elsewhere to begin conversation

    TestDialogue:Remember(player, "HasMet", true)
    ```
]=]

function DialogueTree.Remember(self : DialogueTree, player : Player, index : any, value : any)
    if not self.Sessions[player] then
        warn(`Attempted to make memory when player {player} does not have active session`)
        return
    end

    self.Sessions[player].Memory[index] = value
end

--[=[
    @param player Player
    @param index any

    Forgets a value in the session's memory, using the original memory table inserted with `DialogueTree:Converse`. If no session exists for the player, a warning will be issued and no action will be taken.

    Example:

    ```lua
    local TestDialogue = require(path.to.dialogue) -- Using our example from DialogueTree.new

    -- Run code elsewhere to begin conversation

    TestDialogue:Forget(player, "HasMet")
    ```
]=]

function DialogueTree.Forget(self : DialogueTree, player : Player, index : any)
    if not self.Sessions[player] then
        warn(`Attempted to forget memory when player {player} does not have active session`)
        return
    end

    self.Sessions[player].Memory[index] = nil
end

--[=[
    @param player Player
    @param index any

    Recalls a value in the session's memory, using the original memory table inserted with `DialogueTree:Converse`. If no session exists for the player, a warning will be issued and nil will be returned.

    Example:

    ```lua
    local TestDialogue = require(path.to.dialogue) -- Using our example from DialogueTree.new

    -- Run code elsewhere to begin conversation

    local HasMet = TestDialogue:Recall(player, "HasMet")
    ```
]=]

function DialogueTree.Recall(self : DialogueTree, player : Player, index : any) : any
    if not self.Sessions[player] then
        warn(`Attempted to recall memory when player {player} does not have active session`)
        return nil
    end

    return self.Sessions[player].Memory[index]
end

--[=[
    Clears all sessions for all players. It's recommended to call this when dialogue source is cleaned up.
]=]

function DialogueTree.ClearSessions(self : DialogueTree)
    self.Sessions = {}
end

return DialogueTree