--[=[
    Touch input capturer.

    @class Touch
]=]

local Touch = {}
Touch.__index = Touch

-- Services
local UserInputService = game:GetService("UserInputService")

-- Imports
local Signal = require("@pkg/Signal")
local Bucket = require("@pkg/Bucket")

-- Types
type Touch = typeof(setmetatable({} :: {
    _Bucket : Bucket.Bucket,
    TouchTap : Signal.Signal<{Vector2}, boolean>,
    TouchTapInWorld : Signal.Signal<Vector2, boolean>,
    TouchMoved : Signal.Signal<InputObject, boolean>,
    TouchLongPress : Signal.Signal<{Vector2}, Enum.UserInputState, boolean>,
    TouchPan : Signal.Signal<{Vector2}, Vector2, Vector2, Enum.UserInputState, boolean>,
    TouchPinch : Signal.Signal<{Vector2}, number, Vector2, Enum.UserInputState, boolean>,
    TouchRotate : Signal.Signal<{Vector2}, number, number, Enum.UserInputState, boolean>,
    TouchSwipe : Signal.Signal<Enum.SwipeDirection, number, boolean>,
    TouchStarted : Signal.Signal<InputObject, boolean>,
    TouchEnded : Signal.Signal<InputObject, boolean>,
}, Touch))

function Touch.new(): (Touch)
    local self = setmetatable({}, Touch) :: Touch

    self._Bucket = Bucket.new()

    self.TouchTap = Signal.Wrap(UserInputService.TouchTap)
    self.TouchTapInWorld = Signal.Wrap(UserInputService.TouchTapInWorld)
    self.TouchMoved = Signal.Wrap(UserInputService.TouchMoved)
    self.TouchLongPress = Signal.Wrap(UserInputService.TouchLongPress)
    self.TouchPan = Signal.Wrap(UserInputService.TouchPan)
    self.TouchPinch = Signal.Wrap(UserInputService.TouchPinch)
    self.TouchRotate = Signal.Wrap(UserInputService.TouchRotate)
    self.TouchSwipe = Signal.Wrap(UserInputService.TouchSwipe)
    self.TouchStarted = Signal.Wrap(UserInputService.TouchStarted)
    self.TouchEnded = Signal.Wrap(UserInputService.TouchEnded)

    self._Bucket:Add(self.TouchTap)
    self._Bucket:Add(self.TouchTapInWorld)
    self._Bucket:Add(self.TouchMoved)
    self._Bucket:Add(self.TouchLongPress)
    self._Bucket:Add(self.TouchPan)
    self._Bucket:Add(self.TouchPinch)
    self._Bucket:Add(self.TouchRotate)
    self._Bucket:Add(self.TouchSwipe)
    self._Bucket:Add(self.TouchStarted)
    self._Bucket:Add(self.TouchEnded)

    return self
end

function Touch.IsTouchEnabled(self : Touch) : boolean
    if not self then
        error("Expected Touch self")
    end

    return UserInputService.TouchEnabled
end

function Touch.Destroy(self : Touch)
    self._Bucket:Destroy()
end

return Touch
