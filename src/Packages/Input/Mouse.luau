--[=[
    Mouse input capturer.

    @class Mouse
]=]

local Mouse = {}
Mouse.__index = Mouse

-- Constants
local RAY_DISTANCE = 1000

-- Services
local UserInputService = game:GetService("UserInputService")

-- Imports

local Signal = require("@pkg/Signal")
local Bucket = require("@pkg/Bucket")

-- Types
type Mouse = typeof(setmetatable({} :: {
    _Bucket : Bucket.Bucket,
    LeftDown : Signal.Signal<boolean>,
    LeftUp : Signal.Signal<boolean>,
    RightDown : Signal.Signal<boolean>,
    RightUp : Signal.Signal<boolean>,
    MiddleDown : Signal.Signal<boolean>,
    MiddleUp : Signal.Signal<boolean>,
    Moved : Signal.Signal<Vector2, boolean>,
    Scrolled : Signal.Signal<number, boolean>,
}, Mouse))

function Mouse.new(): (Mouse)
    local self = setmetatable({}, Mouse) :: Mouse

    self._Bucket = Bucket.new()

    self.LeftDown = Signal.new()
    self.LeftUp = Signal.new()
    self.RightDown = Signal.new()
    self.RightUp = Signal.new()
    self.MiddleDown = Signal.new()
    self.MiddleUp = Signal.new()
    self.Moved = Signal.new()
    self.Scrolled = Signal.new()

    self._Bucket:Add(self.LeftDown)
    self._Bucket:Add(self.LeftUp)
    self._Bucket:Add(self.RightDown)
    self._Bucket:Add(self.RightUp)
    self._Bucket:Add(self.MiddleDown)
    self._Bucket:Add(self.MiddleUp)
    self._Bucket:Add(self.Moved)
    self._Bucket:Add(self.Scrolled)

    self._Bucket:Add(UserInputService.InputBegan:Connect(function(InputObject, Processed)
        if InputObject.UserInputType == Enum.UserInputType.MouseButton1 then
            self.LeftDown:Fire(Processed)
        elseif InputObject.UserInputType == Enum.UserInputType.MouseButton2 then
            self.RightDown:Fire(Processed)
        elseif InputObject.UserInputType == Enum.UserInputType.MouseButton3 then
            self.MiddleDown:Fire(Processed)
        end
    end))

    self._Bucket:Add(UserInputService.InputEnded:Connect(function(InputObject, Processed)
        if InputObject.UserInputType == Enum.UserInputType.MouseButton1 then
            self.LeftUp:Fire(Processed)
        elseif InputObject.UserInputType == Enum.UserInputType.MouseButton2 then
            self.RightUp:Fire(Processed)
        elseif InputObject.UserInputType == Enum.UserInputType.MouseButton3 then
            self.MiddleUp:Fire(Processed)
        end
    end))

    self._Bucket:Add(UserInputService.InputChanged:Connect(function(InputObject, Processed)
        if InputObject.UserInputType == Enum.UserInputType.MouseMovement then
            local Position = InputObject.Position
            self.Moved:Fire(Vector2.new(Position.X, Position.Y), Processed)
        elseif InputObject.UserInputType == Enum.UserInputType.MouseWheel then
            self.Scrolled:Fire(InputObject.Position.Z, Processed)
        end
    end))

    return self
end

function Mouse.IsLeftDown(self : Mouse) : boolean
    if not self then
        error("Expected Mouse self")
    end

    return UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
end

function Mouse.IsRightDown(self : Mouse) : boolean
    if not self then
        error("Expected Mouse self")
    end

    return UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
end

function Mouse.IsMiddleDown(self : Mouse) : boolean
    if not self then
        error("Expected Mouse self")
    end

    return UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton3)
end

function Mouse.GetPosition(self : Mouse) : Vector2
    if not self then
        error("Expected Mouse self")
    end

    return UserInputService:GetMouseLocation()
end

function Mouse.GetDelta(self : Mouse) : Vector2
    if not self then
        error("Expected Mouse self")
    end

    return UserInputService:GetMouseDelta()
end

function Mouse.GetRay(self : Mouse, OverridePos : Vector2?) : Ray
    if not self then
        error("Expected Mouse self")
    end

    local CurrentCamera = workspace.CurrentCamera

    if not CurrentCamera then
        error("Can not build mouse ray without workspace.CurrentCamera")
    end

    local MousePos = OverridePos or UserInputService:GetMouseLocation()
    return CurrentCamera:ViewportPointToRay(MousePos.X, MousePos.Y)
end

function Mouse.Raycast(self : Mouse, RaycastParams : RaycastParams, Distance : number?, OverridePos : Vector2?) : RaycastResult?
    local ViewportMouseRay = self:GetRay(OverridePos)

    return workspace:Raycast(
        ViewportMouseRay.Origin,
        ViewportMouseRay.Direction * (Distance or RAY_DISTANCE),
        RaycastParams
    )
end

function Mouse.Project(self : Mouse, Distance : number?, OverridePos : Vector2?) : Vector3
    local ViewportMouseRay = self:GetRay(OverridePos)
    return ViewportMouseRay.Origin + (ViewportMouseRay.Direction.Unit * (Distance or RAY_DISTANCE))
end

function Mouse.Lock(self : Mouse)
    if not self then
        error("Expected Mouse self")
    end

    UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
end

function Mouse.LockCenter(self : Mouse)
    if not self then
        error("Expected Mouse self")
    end

    UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
end

function Mouse.Unlock(self : Mouse)
    if not self then
        error("Expected Mouse self")
    end

    UserInputService.MouseBehavior = Enum.MouseBehavior.Default
end

function Mouse.Destroy(self : Mouse)
    self._Bucket:Destroy()
end

return Mouse
