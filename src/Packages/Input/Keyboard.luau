--[=[
    Keyboard input capturer.

    @class Keyboard
]=]

local Keyboard = {}
Keyboard.__index = Keyboard

-- Services
local UserInputService = game:GetService("UserInputService")

-- Import
local Signal = require("@pkg/Signal")
local Bucket = require("@pkg/Bucket")

-- Types
type Keyboard = typeof(setmetatable({} :: {
    _Bucket : Bucket.Bucket,
    KeyDown : Signal.Signal<Enum.KeyCode, boolean>,
    KeyUp : Signal.Signal<Enum.KeyCode, boolean>,
}, Keyboard))

function Keyboard.new(): (Keyboard)
    local self = setmetatable({}, Keyboard) :: Keyboard

    self._Bucket = Bucket.new()

    self.KeyDown = Signal.new()
    self.KeyUp = Signal.new()

    self._Bucket:Add(self.KeyDown)
    self._Bucket:Add(self.KeyUp)

    self._Bucket:Add(UserInputService.InputBegan:Connect(function(InputObject, Processed)
        if InputObject.UserInputType == Enum.UserInputType.Keyboard then
            self.KeyDown:Fire(InputObject.KeyCode, Processed)
        end
    end))

    self._Bucket:Add(UserInputService.InputEnded:Connect(function(InputObject, Processed)
        if InputObject.UserInputType == Enum.UserInputType.Keyboard then
            self.KeyUp:Fire(InputObject.KeyCode, Processed)
        end
    end))

    return self
end

function Keyboard.IsKeyDown(self : Keyboard, KeyCode : Enum.KeyCode) : boolean
    if not self then
        error("Expected Keyboard self")
    end

    return UserInputService:IsKeyDown(KeyCode)
end

function Keyboard.AreKeysDown(self : Keyboard, KeyCodeOne : Enum.KeyCode, KeyCodeTwo : Enum.KeyCode) : boolean
    return self:IsKeyDown(KeyCodeOne) and self:IsKeyDown(KeyCodeTwo)
end

function Keyboard.AreEitherKeysDown(self : Keyboard, KeyCodeOne : Enum.KeyCode, KeyCodeTwo : Enum.KeyCode) : boolean
    return self:IsKeyDown(KeyCodeOne) or self:IsKeyDown(KeyCodeTwo)
end

function Keyboard.Destroy(self : Keyboard)
    self._Bucket:Destroy()
end

return Keyboard
