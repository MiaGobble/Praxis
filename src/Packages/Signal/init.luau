-- Authors:
-- stravant - July 31st, 2021 - Created the file.     
-- sleitnick - August 3rd, 2021 - Modified for Knit. 
-- iGottic - April 18th, 2026 - Modified for Praxis.

--[=[
	@class Signal

	A Signal is a data structure that allows events to be dispatched
	and observed.

	This implementation is a direct copy of the de facto standard, [GoodSignal](https://devforum.roblox.com/t/lua-signal-class-comparison-optimal-goodsignal-class/1387063),
	with some added methods and typings.

	For example:
	```lua
	local SignalInstance = Signal.new()

	-- Subscribe to a signal:
	SignalInstance:Connect(function(msg)
		print("Got message:", msg)
	end)

	-- Dispatch an event:
	SignalInstance:Fire("Hello world!")
	```
]=]

--[=[
	@within Signal
	@type ConnectionFn (...any) -> ()

	A function connected to a signal.
]=]

local Signal = {}
Signal.__index = Signal

-- Imports
local Connection = require("@self/Connection")

-- Types extended
export type Connection = Connection.Connection

export type Signal<T...> = {
	Fire: (self: Signal<T...>, T...) -> (),
	FireDeferred: (self: Signal<T...>, T...) -> (),
	Connect: (self: Signal<T...>, fn: (T...) -> ()) -> Connection,
	Once: (self: Signal<T...>, fn: (T...) -> ()) -> Connection,
	DisconnectAll: (self: Signal<T...>) -> (),
	GetConnections: (self: Signal<T...>) -> { Connection },
	Destroy: (self: Signal<T...>) -> (),
	Wait: (self: Signal<T...>) -> T...,
}

local FreeRunnerThread: thread? = nil

local function AcquireRunnerThreadAndCallEventHandler(fn, ...)
	local AcquiredRunnerThread = FreeRunnerThread
	FreeRunnerThread = nil
	fn(...)
	-- The handler finished running, this runner thread is free again.
	FreeRunnerThread = AcquiredRunnerThread
end

local function RunEventHandlerInFreeThread(...)
	AcquireRunnerThreadAndCallEventHandler(...)

	while true do
		AcquireRunnerThreadAndCallEventHandler(coroutine.yield())
	end
end

--[=[
	Constructs a new Signal

	@return Signal
]=]

function Signal.new<T...>(): Signal<T...>
	local self = setmetatable({
		_HandlerListHead = false,
		_ProxyHandler = nil,
		_YieldedThreads = nil,
	}, Signal)

	return self :: any
end

--[=[
	Constructs a new Signal that wraps around an RBXScriptSignal.

	@param rbxScriptSignal RBXScriptSignal -- Existing RBXScriptSignal to wrap
	@return Signal

	For example:

	```lua
	local SignalInstance = Signal.Wrap(workspace.ChildAdded)
	SignalInstance:Connect(function(part) print(part.Name .. " added") end)
	Instance.new("Part").Parent = workspace
	```
]=]

function Signal.Wrap<T...>(rbxScriptSignal: RBXScriptSignal): Signal<T...>
	assert(
		typeof(rbxScriptSignal) == "RBXScriptSignal",
		"Argument #1 to Signal.Wrap must be a RBXScriptSignal; got " .. typeof(rbxScriptSignal)
	)

	local signal = Signal.new() :: any
	signal._ProxyHandler = rbxScriptSignal:Connect(function(...)
		signal:Fire(...)
	end)

	return signal
end

--[=[
	Checks if the given object is a Signal.

	@param obj any -- Object to check
	@return boolean -- `true` if the object is a Signal.
]=]

function Signal.Is(obj: any): boolean
	return type(obj) == "table" and getmetatable(obj) == Signal
end

--[=[
	@param fn ConnectionFn
	@return SignalConnection

	Connects a function to the signal, which will be called anytime the signal is fired.
	```lua
	SignalInstance:Connect(function(msg, num)
		print(msg, num)
	end)

	SignalInstance:Fire("Hello", 25)
	```
]=]

function Signal.Connect<T...>(self: Signal<T...>, fn)
	local ThisConnection = setmetatable({
		Connected = true,
		_Signal = self,
		_Fn = fn,
		_Next = false,
	}, Connection) :: any

	if (self :: any)._HandlerListHead then
		ThisConnection._Next = self._HandlerListHead;
		(self :: any)._HandlerListHead = ThisConnection
	else
		(self :: any)._HandlerListHead = ThisConnection
	end

	return ThisConnection
end

--[=[
	@deprecated v1.3.0 -- Use `Signal:Once` instead.
	@param fn ConnectionFn
	@return SignalConnection
]=]

function Signal.ConnectOnce<T...>(self: Signal<T...>, fn)
	return self:Once(fn)
end

--[=[
	@param fn ConnectionFn
	@return SignalConnection

	Connects a function to the signal, which will be called the next time the signal fires. Once
	the connection is triggered, it will disconnect itself.

	```lua
	SignalInstance:Once(function(msg, num)
		print(msg, num)
	end)

	SignalInstance:Fire("Hello", 25)
	SignalInstance:Fire("This message will not go through", 10)
	```
]=]

function Signal.Once<T...>(self: Signal<T...>, fn)
	local ThisConnection: Connection
	local Done = false

	ThisConnection = self:Connect(function(...)
		if Done then
			return
		end

		Done = true
		ThisConnection:Disconnect()
		fn(...)
	end)

	return ThisConnection
end

function Signal.GetConnections<T...>(self: Signal<T...>)
	local Items = {}

	local Item = (self :: any)._HandlerListHead
	while Item do
		table.insert(Items, Item)
		Item = Item._Next
	end

	return Items
end

--[=[
	Disconnects all connections from the signal.
	```lua
	signal:DisconnectAll()
	```
]=]

function Signal.DisconnectAll<T...>(self: Signal<T...>)
	local Item = (self :: any)._HandlerListHead
	while Item do
		Item.Connected = false
		Item = Item._Next
	end
	(self :: any)._HandlerListHead = false

	local YieldedThreads = rawget(self :: any, "_YieldedThreads") :: {[thread]: unknown}?
	if YieldedThreads then
		for thread in YieldedThreads do
			if coroutine.status(thread) == "suspended" then
				warn(debug.traceback(thread, "signal disconnected; yielded thread cancelled", 2))
				task.cancel(thread)
			end
		end
		table.clear((self :: any)._YieldedThreads)
	end
end

--[=[
	@param ... any

	Fire the signal, which will call all of the connected functions with the given arguments.
	```lua
	signal:Fire("Hello")

	-- Any number of arguments can be fired:
	signal:Fire("Hello", 32, {Test = "Test"}, true)
	```
]=]

function Signal.Fire<T...>(self: Signal<T...>, ...)
	local Item = (self :: any)._HandlerListHead
	while Item do
		if Item.Connected then
			-- Fix: We must check the status of the cached thread before attempting to reuse it, as it could have been
			-- closed externally, and that would break dispatch.
			if not FreeRunnerThread or coroutine.status(FreeRunnerThread :: thread) ~= "suspended" then
				FreeRunnerThread = coroutine.create(RunEventHandlerInFreeThread)
			end
			task.spawn(FreeRunnerThread :: thread, Item._Fn, ...)
		end
		Item = Item._Next
	end
end

--[=[
	@param ... any

	Same as `Fire`, but uses `task.defer` internally & doesn't take advantage of thread reuse.
	```lua
	signal:FireDeferred("Hello")
	```
]=]

function Signal.FireDeferred<T...>(self: Signal<T...>, ...)
	local Item = (self :: any)._HandlerListHead
	while Item do
		local Conn = Item
		task.defer(function(...)
			if Conn.Connected then
				Conn._Fn(...)
			end
		end, ...)
		Item = Item._Next
	end
end

--[=[
	@return ... any
	@yields

	Yields the current thread until the signal is fired, and returns the arguments fired from the signal.
	Yielding the current thread is not always desirable. If the desire is to only capture the next event
	fired, using `Once` might be a better solution.
	```lua
	task.spawn(function()
		local msg, num = SignalInstance:Wait()
		print(msg, num) --> "Hello", 32
	end)
	SignalInstance:Fire("Hello", 32)
	```
]=]

function Signal.Wait<T...>(self: Signal<T...>)
	local YieldedThreads = rawget(self :: any, "_YieldedThreads") :: {[thread]: unknown}?
	if not YieldedThreads then
		YieldedThreads = {} :: {[thread]: unknown}?
		rawset(self :: any, "_YieldedThreads", YieldedThreads)
	end

	local _: typeof(assert(YieldedThreads))
	local Thread = coroutine.running()
	YieldedThreads[Thread] = true

	self:Once(function(...)
		local _: typeof(assert(YieldedThreads))
		YieldedThreads[Thread] = nil

		if coroutine.status(Thread) == "suspended" then
			task.spawn(Thread, ...)
		end
	end)

	return coroutine.yield()
end

--[=[
	Cleans up the signal.

	Technically, this is only necessary if the signal is created using
	`Signal.Wrap`. Connections should be properly GC'd once the signal
	is no longer referenced anywhere. However, it is still good practice
	to include ways to strictly clean up resources. Calling `Destroy`
	on a signal will also disconnect all connections immediately.
	```lua
	SignalInstance:Destroy()
	```
]=]

function Signal.Destroy<T...>(self: Signal<T...>)
	self:DisconnectAll()

	local ProxyHandler = rawget(self :: any, "_ProxyHandler")
	if ProxyHandler then
		ProxyHandler:Disconnect()
	end
end

-- Make signal strict
setmetatable(Signal, {
	__index = function(_tb, key)
		error(("Attempt to get Signal::%s (not a valid member)"):format(tostring(key)), 2)
	end,
	__newindex = function(_tb, key, _value)
		error(("Attempt to set Signal::%s (not a valid member)"):format(tostring(key)), 2)
	end,
})

return Signal