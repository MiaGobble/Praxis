--[=[
    Binds OOP classes to Roblox instances through CollectionService tags.

    @class Binder
]=]

local Binder = {}
Binder.__index = Binder

-- Services
local CollectionService = game:GetService("CollectionService")

-- Imports
local Bucket = require("@pkg/Bucket")
local Signal = require("@pkg/Signal")
local TagUtils = require("@pkg/TagUtils")

-- Types
type Class<T> = {
    new: (instance: Instance) -> T,
}

export type Binder<T> = setmetatable<{
	Tag: string,
    Class: Class<T>,
    Bound: Signal.Signal<Instance, T>,
    Unbound: Signal.Signal<Instance, T?>,
    Bucket: Bucket.Bucket,
    ListeningBucket: Bucket.Bucket,
    Started: boolean,
    Objects: {[Instance]: T},
    ObjectBuckets: {[Instance]: Bucket.Bucket},
}, typeof(Binder)>

--[=[
    @param tag string
    @param class table
    @return Binder

    Creates a new binder for the given CollectionService tag and OOP class.
]=]

function Binder.new<T>(tag : string, class : Class<T>) : Binder<T>
    local self = setmetatable({}, Binder) :: Binder<T>

    self.Tag = tag
    self.Class = class
    self.Bound = Signal.new()
    self.Unbound = Signal.new()
    self.Bucket = Bucket.new()
    self.ListeningBucket = Bucket.new()
    self.Started = false
    self.Objects = {}
    self.ObjectBuckets = {}

    self.Bucket:Add(self.Bound)
    self.Bucket:Add(self.Unbound)
    self.Bucket:Add(self.ListeningBucket)

    self:Start()

    return self
end

--[=[
    @param self Binder
    @param instance Instance
    @return any?

    Returns the bound object for the given instance, or nil if it is not bound.
]=]

function Binder.Get(self : Binder<any>, instance : Instance) : any?
    return self.Objects[instance]
end

--[=[
    @param self Binder
    @return {[Instance]: any}

    Returns the dictionary of currently bound instances to objects.
]=]

function Binder.GetAll(self : Binder<any>) : {[Instance]: any}
    return table.clone(self.Objects)
end

--[=[
    @param self Binder
    @param instance Instance
    @return any?

    Binds the class to the instance if it is not already bound.
]=]

function Binder.Bind(self : Binder<any>, instance : Instance) : any?
    if self.Objects[instance] then
        return self.Objects[instance]
    end

    local Object = self.Class.new(instance)
    local ObjectBucket = Bucket.new()

    ObjectBucket:Add(Object)

    self.Objects[instance] = Object
    self.ObjectBuckets[instance] = ObjectBucket

    self.Bound:Fire(instance, Object)

    return Object
end

--[=[
    @param self Binder
    @param instance Instance

    Unbinds the class from the instance if it is currently bound.
]=]

function Binder.Unbind(self : Binder<any>, instance : Instance)
    local Object = self.Objects[instance]

    if not Object then
        return
    end

    local ObjectBucket = self.ObjectBuckets[instance]

    self.Objects[instance] = nil
    self.ObjectBuckets[instance] = nil

    if ObjectBucket then
        ObjectBucket:Destroy()
    end

    self.Unbound:Fire(instance, Object)
end

--[=[
    @param self Binder
    @param instance Instance
    @return any?

    Adds the binder tag to an instance and binds it.
]=]

function Binder.TagInstance(self : Binder<any>, instance : Instance) : any?
    CollectionService:AddTag(instance, self.Tag)
    return self:Bind(instance)
end

--[=[
    @param self Binder
    @param instance Instance

    Removes the binder tag from an instance and unbinds it.
]=]

function Binder.UntagInstance(self : Binder<any>, instance : Instance)
    CollectionService:RemoveTag(instance, self.Tag)
    self:Unbind(instance)
end

--[=[
    @param self Binder

    Starts listening to CollectionService and binds all existing tagged instances.
]=]

function Binder.Start(self : Binder<any>)
    if self.Started then
        return
    end

    self.Started = true
    self.ListeningBucket = Bucket.new()
    self.Bucket:Add(self.ListeningBucket)

    self.ListeningBucket:Add(TagUtils.OnInstanceAdded(self.Tag, function(instance)
        self:Bind(instance)
    end))

    self.ListeningBucket:Add(TagUtils.OnInstanceRemoved(self.Tag, function(instance)
        self:Unbind(instance)
    end))
end

--[=[
    @param self Binder

    Stops listening and unbinds all currently bound instances.
]=]

function Binder.Stop(self : Binder<any>)
    if not self.Started then
        return
    end

    self.Started = false

    for InstanceObject, _ in self.Objects do
        self:Unbind(InstanceObject)
    end

    self.ListeningBucket:Destroy()
    self.ListeningBucket = Bucket.new()
    self.Bucket:Add(self.ListeningBucket)
end

--[=[
    @param self Binder

    Destroys the binder and all bound objects.
]=]

function Binder.Destroy(self : Binder<any>)
    self:Stop()
    self.Bound:Destroy()
    self.Unbound:Destroy()
    self.Bucket:Destroy()
    table.clear(self)
end

return Binder