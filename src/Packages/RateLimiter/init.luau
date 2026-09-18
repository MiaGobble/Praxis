--[=[
    @class RateLimiter

    A simple OOP class for rate limiting.
]=]

local RateLimiter = {}
RateLimiter.__index = RateLimiter

-- Types
type RateLimiter = typeof(setmetatable({} :: {
    LastTrigger : number,
    Cooldown : number,
}, RateLimiter))

--[=[
    @param cooldown number -- The cooldown time in seconds.
    @return RateLimiter

    Creates a new RateLimiter instance.
]=]

function RateLimiter.new(cooldown : number) : RateLimiter
    local self = setmetatable({}, RateLimiter) :: RateLimiter

    self.LastTrigger = 0
    self.Cooldown = cooldown

    return self
end

--[=[
    @return boolean

    Checks if the rate limiter is ready to be triggered.
]=]

function RateLimiter.IsReady(self : RateLimiter) : boolean
    return os.clock() - self.LastTrigger >= self.Cooldown
end

--[=[
    Triggers the rate limiter, updating the last trigger time.
]=]

function RateLimiter.Trigger(self : RateLimiter)
    self.LastTrigger = os.clock()
end

--[=[
    Resets the rate limiter, allowing it to be triggered immediately.
]=]

function RateLimiter.Reset(self : RateLimiter)
    self.LastTrigger = 0
end

--[=[
    @param callback () -> nil -- The callback function to execute if the rate limiter is ready.

    Executes the callback if the rate limiter is ready, and triggers the rate limiter.
]=]

function RateLimiter.Compute(self : RateLimiter, callback : () -> nil)
    if self:IsReady() then
        self:Trigger()
        task.spawn(callback)
    end
end

return RateLimiter