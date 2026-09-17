--[=[
    Gamepad input capturer.

    @class Gamepad
]=]

local Gamepad = {}
Gamepad.__index = Gamepad

-- Services
local GuiService = game:GetService("GuiService")
local HapticService = game:GetService("HapticService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

-- Imports
local Signal = require("@pkg/Signal")
local Bucket = require("@pkg/Bucket")

-- Types
type GamepadState = {[Enum.KeyCode] : InputObject}
type Gamepad = typeof(setmetatable({} :: {
    _Bucket : Bucket.Bucket,
    _GamepadBucket : Bucket.Bucket,
    _GamepadInput : Enum.UserInputType?,
    _SetMotorIds : {[Enum.VibrationMotor] : number},
    ButtonDown : Signal.Signal<Enum.KeyCode, boolean>,
    ButtonUp : Signal.Signal<Enum.KeyCode, boolean>,
    Connected : Signal.Signal<>,
    Disconnected : Signal.Signal<>,
    GamepadChanged : Signal.Signal<Enum.UserInputType?>,
    DefaultDeadzone : number,
    SupportsVibration : boolean,
    State : GamepadState,
}, Gamepad))

local function ApplyDeadzone(Value : number, Threshold : number) : number
    if math.abs(Value) < Threshold then
        return 0
    end

    return ((math.abs(Value) - Threshold) / (1 - Threshold)) * math.sign(Value)
end

local function GetActiveGamepad() : Enum.UserInputType?
    local ActiveGamepad = nil
    local NavigationGamepads = UserInputService:GetNavigationGamepads()

    if #NavigationGamepads > 1 then
        for _, NavigationGamepad in NavigationGamepads do
            if ActiveGamepad == nil or NavigationGamepad.Value < ActiveGamepad.Value then
                ActiveGamepad = NavigationGamepad
            end
        end
    else
        local ConnectedGamepads = UserInputService:GetConnectedGamepads()

        for _, ConnectedGamepad in ConnectedGamepads do
            if ActiveGamepad == nil or ConnectedGamepad.Value < ActiveGamepad.Value then
                ActiveGamepad = ConnectedGamepad
            end
        end
    end

    if ActiveGamepad and not UserInputService:GetGamepadConnected(ActiveGamepad) then
        ActiveGamepad = nil
    end

    return ActiveGamepad
end

local function HeartbeatDelay(Duration : number, Callback : () -> ()) : RBXScriptConnection
    local Started = time()
    local Connection : RBXScriptConnection

    Connection = RunService.Heartbeat:Connect(function()
        local Elapsed = time() - Started

        if Elapsed >= Duration then
            Connection:Disconnect()
            Callback()
        end
    end)

    return Connection
end

function Gamepad.new(GamepadInput : Enum.UserInputType?): (Gamepad)
    local self = setmetatable({}, Gamepad) :: Gamepad

    self._Bucket = Bucket.new()
    self._GamepadBucket = Bucket.new()

    self._Bucket:Add(self._GamepadBucket)

    self.ButtonDown = Signal.new()
    self.ButtonUp = Signal.new()
    self.Connected = Signal.new()
    self.Disconnected = Signal.new()
    self.GamepadChanged = Signal.new()

    self._Bucket:Add(self.ButtonDown)
    self._Bucket:Add(self.ButtonUp)
    self._Bucket:Add(self.Connected)
    self._Bucket:Add(self.Disconnected)
    self._Bucket:Add(self.GamepadChanged)

    self.DefaultDeadzone = 0.05
    self.SupportsVibration = false
    self.State = {}

    self:_SetupMotors()
    self:_SetupGamepad(GamepadInput)

    return self
end

function Gamepad._SetupActiveGamepad(self : Gamepad, GamepadInput : Enum.UserInputType?): ()
    local LastGamepad = self._GamepadInput

    if GamepadInput == LastGamepad then
        return
    end

    self._GamepadBucket:Destroy()
    self._GamepadBucket = Bucket.new()
    self._Bucket:Add(self._GamepadBucket)

    table.clear(self.State)

    self._GamepadInput = GamepadInput
    self.SupportsVibration = if GamepadInput then HapticService:IsVibrationSupported(GamepadInput) else false

    if not GamepadInput then
        if LastGamepad ~= nil then
            self.Disconnected:Fire()
        end

        self.GamepadChanged:Fire(nil)
        return
    end

    for _, InputObject : InputObject in UserInputService:GetGamepadState(GamepadInput) do
        self.State[InputObject.KeyCode] = InputObject
    end

    self._GamepadBucket:Add(function()
        self:StopMotors()
    end)

    self._GamepadBucket:Add(UserInputService.InputBegan:Connect(function(InputObject, Processed)
        if InputObject.UserInputType == GamepadInput then
            self.State[InputObject.KeyCode] = InputObject
            self.ButtonDown:Fire(InputObject.KeyCode, Processed)
        end
    end))

    self._GamepadBucket:Add(UserInputService.InputEnded:Connect(function(InputObject, Processed)
        if InputObject.UserInputType == GamepadInput then
            self.State[InputObject.KeyCode] = InputObject
            self.ButtonUp:Fire(InputObject.KeyCode, Processed)
        end
    end))

    self._GamepadBucket:Add(UserInputService.InputChanged:Connect(function(InputObject)
        if InputObject.UserInputType == GamepadInput then
            self.State[InputObject.KeyCode] = InputObject
        end
    end))

    if LastGamepad == nil then
        self.Connected:Fire()
    end

    self.GamepadChanged:Fire(GamepadInput)
end

function Gamepad._SetupGamepad(self : Gamepad, ForcedGamepad : Enum.UserInputType?)
    if ForcedGamepad then
        self._Bucket:Add(UserInputService.GamepadConnected:Connect(function(GamepadInput)
            if GamepadInput == ForcedGamepad then
                self:_SetupActiveGamepad(ForcedGamepad)
            end
        end))

        self._Bucket:Add(UserInputService.GamepadDisconnected:Connect(function(GamepadInput)
            if GamepadInput == ForcedGamepad then
                self:_SetupActiveGamepad(nil)
            end
        end))

        if UserInputService:GetGamepadConnected(ForcedGamepad) then
            self:_SetupActiveGamepad(ForcedGamepad)
        else
            self:_SetupActiveGamepad(nil)
        end
    else
        local function CheckToSetupActive()
            local ActiveGamepad = GetActiveGamepad()

            if ActiveGamepad ~= self._GamepadInput then
                self:_SetupActiveGamepad(ActiveGamepad)
            end
        end

        self._Bucket:Add(UserInputService.GamepadConnected:Connect(CheckToSetupActive))
        self._Bucket:Add(UserInputService.GamepadDisconnected:Connect(CheckToSetupActive))

        self:_SetupActiveGamepad(GetActiveGamepad())
    end
end

function Gamepad._SetupMotors(self : Gamepad)
    self._SetMotorIds = {}

    for _, Motor in Enum.VibrationMotor:GetEnumItems() do
        self._SetMotorIds[Motor] = 0
    end
end

function Gamepad.GetThumbstick(self : Gamepad, Thumbstick : Enum.KeyCode, DeadzoneThreshold : number?) : Vector2
    local InputObject = self.State[Thumbstick]

    if not InputObject then
        return Vector2.zero
    end

    local Position = InputObject.Position
    local Deadzone = DeadzoneThreshold or self.DefaultDeadzone

    return Vector2.new(
        ApplyDeadzone(Position.X, Deadzone),
        ApplyDeadzone(Position.Y, Deadzone)
    )
end

function Gamepad.GetTrigger(self : Gamepad, Trigger : Enum.KeyCode, DeadzoneThreshold : number?) : number
    local InputObject = self.State[Trigger]

    if not InputObject then
        return 0
    end

    return ApplyDeadzone(InputObject.Position.Z, DeadzoneThreshold or self.DefaultDeadzone)
end

function Gamepad.IsButtonDown(self : Gamepad, GamepadButton : Enum.KeyCode) : boolean
    if not self._GamepadInput then
        return false
    end

    return UserInputService:IsGamepadButtonDown(self._GamepadInput, GamepadButton)
end

function Gamepad.IsMotorSupported(self : Gamepad, Motor : Enum.VibrationMotor) : boolean
    if not self._GamepadInput then
        return false
    end

    return HapticService:IsMotorSupported(self._GamepadInput, Motor)
end

function Gamepad.SetMotor(self : Gamepad, Motor : Enum.VibrationMotor, Intensity : number) : number
    self._SetMotorIds[Motor] += 1

    local Id = self._SetMotorIds[Motor]

    if self._GamepadInput and self:IsMotorSupported(Motor) then
        HapticService:SetMotor(self._GamepadInput, Motor, Intensity)
    end

    return Id
end

function Gamepad.PulseMotor(self : Gamepad, Motor : Enum.VibrationMotor, Intensity : number, Duration : number)
    local Id = self:SetMotor(Motor, Intensity)

    local HeartbeatConnection = HeartbeatDelay(Duration, function()
        if self._SetMotorIds[Motor] ~= Id then
            return
        end

        self:StopMotor(Motor)
    end)

    self._GamepadBucket:Add(HeartbeatConnection)
end

function Gamepad.StopMotor(self : Gamepad, Motor : Enum.VibrationMotor)
    self:SetMotor(Motor, 0)
end

function Gamepad.StopMotors(self : Gamepad)
    for _, Motor in Enum.VibrationMotor:GetEnumItems() do
        if self:IsMotorSupported(Motor) then
            self:StopMotor(Motor)
        end
    end
end

function Gamepad.IsConnected(self : Gamepad) : boolean
    if not self._GamepadInput then
        return false
    end

    return UserInputService:GetGamepadConnected(self._GamepadInput)
end

function Gamepad.GetUserInputType(self : Gamepad) : Enum.UserInputType?
    return self._GamepadInput
end

function Gamepad.SetAutoSelectGui(self : Gamepad, Enabled : boolean)
    if not self then
        error("Expected Gamepad self")
    end

    GuiService.AutoSelectGuiEnabled = Enabled
end

function Gamepad.IsAutoSelectGuiEnabled(self : Gamepad) : boolean
    if not self then
        error("Expected Gamepad self")
    end

    return GuiService.AutoSelectGuiEnabled
end

function Gamepad.Destroy(self : Gamepad)
    self._Bucket:Destroy()
end

return Gamepad
