--[=[
	Used for cleanup of various data types and instances.

	@class Bucket
]=]

local Bucket = {}
Bucket.__index = Bucket

-- Types
export type Bucket = setmetatable<{
	CleanupQueue: {[any]: (any) -> nil},
	IsCleaning: boolean,
}, typeof(Bucket)>

-- Constants
local TABLE_CLEANUP_METHODS = {
	"Destroy",
	"Disconnect",
	"Cleanup",
	"Clean",
	"Cancel",
}

local CLEANUP_METHOD_NAMES = {
	["Instance"] = "Destroy",
	["RBXScriptConnection"] = "Disconnect",
}

-- Imports
local Typer = require("@pkg/Typer")

local function GetMatchingCleanupCallback(Object : any, CleanupMethodName : string?): ((() -> (nil)) | ((Object) -> (nil)))
	local ThisType = typeof(Object)

	if ThisType == "function" then
		return Object
	elseif ThisType == "thread" then
		return function()
			task.cancel(Object)
			return nil
		end
	end

	if CLEANUP_METHOD_NAMES[ThisType] then
		return Object[CLEANUP_METHOD_NAMES[ThisType]] :: (Object) -> nil
	end

	if ThisType == "table" then
		if CleanupMethodName then
			return Object[CleanupMethodName] :: (Object) -> nil
		end

		for _, GenericCleanupName in TABLE_CLEANUP_METHODS do
			if typeof(Object[GenericCleanupName]) == "function" then
				return Object[GenericCleanupName] :: (Object) -> nil
			end

			if typeof(Object[GenericCleanupName:lower()]) == "function" then
				return Object[GenericCleanupName:lower()] :: (Object) -> nil
			end
		end
	end

	error(`No cleanup function found for object: {Object}`)
end

local function AssertPromiseValidity(Object : any)
	local Success = pcall(function()
		Typer.TupleAssertion("table", "function", "function", "function")(Object, Object.getStatus, Object.finally, Object.cancel)
	end)

	if not Success then
		error(`Expected object ({Object}) to be a promise`)
	end
end

--[=[
	Creates a new bucket instance.

	```lua
	local BucketInstance = Bucket.new()

	BucketInstance:Add(...)
	BucketInstance:Remove(...)
	BucketInstance:Destroy()
	```

	@return Bucket
]=]

function Bucket.new() : Bucket
	local self = setmetatable({}, Bucket) :: Bucket

	self.CleanupQueue = {}
	self.IsCleaning = false

	return self
end

--[=[
	Adds userdata or an instance to the bucket. Supported types include: Instance, RBXScriptConnection, function, thread, or table.

	```lua
	local BucketInstance = Bucket.new()

	BucketInstance:Add(workspace.Baseplate)

	BucketInstance:Add(RunService.RenderStepped:Connect(function()
		-- ...
	end))

	BucketInstance:Add(function()
		-- ...
	end)
	```

	@param Object any -- The object to be cleaned up
	@param CleanupMethodName string? -- If you're passing a table, this is an optional setting to choose the cleanup function name (defaults to Destroy or Disconnect)
	@return any -- The object you inputted
]=]

function Bucket.Add(self : Bucket, Object : any, CleanupMethodName : string?)
	if self.IsCleaning then
		error("Cannot add an object to bucket during cleanup")
	end

	self.CleanupQueue[Object] = GetMatchingCleanupCallback(Object, CleanupMethodName)
end

--[=[
	Adds a promise to the bucket. Will return the promise, meaning it can be chained.

	```lua
	-- local MyPromise = ...

	local BucketInstance = Bucket.new()

	BucketInstance:AddPromise(MyPromise)
	```

	@param Object Promise -- The promise to be cleaned up
	@return Promise -- The same promise that was inputted
]=]

function Bucket.AddPromise(self : Bucket, Object : any)
	if self.IsCleaning then
		error("Cannot add a promise to bucket during cleanup")
	end

	AssertPromiseValidity(Object)

	if Object:getStatus() == "Started" then
		Object:finally(function()
			if self.IsCleaning then
				return
			end

			self.CleanupQueue[Object] = nil
		end)

		self:Add(Object)
	end

	return Object
end

--[=[
	Tells the Bucket to destroy itself when the inputted instance is destroyed or parented to nil.

	```lua
	local BucketInstance = Bucket.new()

	BucketInstance:AttachToInstance(PartInstance)
	```

	@param Object Instance -- The instance to track
]=]

function Bucket.AttachToInstance(self : Bucket, Object : Instance)
	if self.IsCleaning then
		error("Can't attach to instance when cleaning")
	elseif not Object:IsDescendantOf(game) then
		error("Can't attach to already destroyed instance")
	end

	local Connection = Object.Destroying:Once(function()
		self:Destroy()
	end)

	self:Add(Connection)

	return Connection
end

--[=[
	Creates another Bucket and adds it to this (the parent) one.

	```lua
	local BucketInstance = Bucket.new()

	local SubBucketInstance = BucketInstance:Extend()
	```

	@return Bucket -- The sub-Bucket
]=]

function Bucket.Extend(self : Bucket)
	if self.IsCleaning then
		error("Can't extend bucket when cleaning")
	end

	local SubBucket = Bucket.new()

	self:Add(SubBucket)

	return SubBucket
end

--[=[
	Removes an object from Bucket's cleanup.

	```lua
	local BucketInstance = Bucket.new()

	BucketInstance:Add(Value)
	BucketInstance:Remove(Value) -- No longer cleaned up
	```

	@param Object any -- The object to be removed from cleanup
]=]

function Bucket.Remove(self : Bucket, Object : any)
	if self.IsCleaning then
		error("Can't remove object when cleaning")
	end

	self.CleanupQueue[Object] = nil
end

--[=[
	Returns a function that, when called, destroys the Bucket.

	```lua
	local BucketInstance = Bucket.new()

	local Destroy = BucketInstance:GetWrappedDestroy()

	Destroy()
	```

	@return () -> nil
]=]

function Bucket.GetWrappedDestroy(self : Bucket)
	return function()
		self:Destroy()
	end
end

--[=[
	Destroys the Bucket, cleaning up all objects and promises inside of it.

	```lua
	local BucketInstance = Bucket.new()

	-- Add stuff...

	BucketInstance:Destroy()
	```
]=]

function Bucket.Destroy(self : Bucket)
	if not self.CleanupQueue or self.IsCleaning then
		return
	end
	
	self.IsCleaning = true

	for Object : any, CleanupCallback : (any) -> nil in self.CleanupQueue do
		task.spawn(CleanupCallback, Object)
		self.CleanupQueue[Object] = nil
	end

	table.clear(self)
end

return Bucket