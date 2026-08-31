local Replicator = {}
Replicator.__index = Replicator

-- Types
export type Replicator = typeof(setmetatable({}, Replicator)) & {
	Name : string,
	CurrentState : {[string]: any},
	Changed : RBXScriptSignal & {Fire : () -> nil},
	SubscribedPlayers : {Player},
	Connections : {RBXScriptConnection},
}

export type Diff = {
	Path : {string},
	Value : any,
}

-- Constants
local TICK_RATE = 1 / 15

-- Services
local RunService = game:GetService("RunService")
local PlayersService = game:GetService("Players")

-- Imports
local Packages = script:FindFirstChild("roblox_packages")
	or script:FindFirstChild("Packages")
	or script.Parent
local SerDes = require(Packages.SerDes)
local Signal = require(Packages.Signal)

-- Variables
local OccupiedIdentifiers = {}
local QueuedReplication = {}
local MainRemote : RemoteEvent = nil
local RequestAllDataRemote : RemoteEvent = nil

function Replicator.new(identifier  : string, baseData : {[string]: any})
	if OccupiedIdentifiers[identifier] then
		error(`Identifier '{identifier}' is already in use`)
	end

	local self = setmetatable({}, Replicator)

	self.Identifier = identifier
	self.CurrentState = table.clone(baseData)
	self.Changed = Signal.new()
	self.SubscribedPlayers = {}
	self.Connections = {}

	OccupiedIdentifiers[identifier] = self

	return self
end

function Replicator.getReplicator(identifier : string) : Replicator?
	return OccupiedIdentifiers[identifier]
end

function Replicator.waitForReplicator(identifier : string, maxTime : number?) : Replicator?
	if not maxTime then
		maxTime = math.huge
	end

	local startTime = os.clock()

	while not OccupiedIdentifiers[identifier] and os.clock() - startTime < maxTime do
		task.wait()
	end

	return OccupiedIdentifiers[identifier]
end

function Replicator.initClient()
	if RunService:IsServer() then
		error("Replicator.initClient() must be called on the client")
	end

	MainRemote = script:WaitForChild("MainRemote")
	RequestAllDataRemote = script:WaitForChild("RequestAllDataRemote")

	MainRemote.OnClientEvent:Connect(function(identifier : string, diff : buffer)
		local ReplicatorInstance = OccupiedIdentifiers[identifier]

		if not ReplicatorInstance then
			OccupiedIdentifiers[identifier] = Replicator.new(identifier, {})
			ReplicatorInstance = OccupiedIdentifiers[identifier]
		end

		local DiffDeserialized : Diff = SerDes.DeserializeFromBuffer(diff)
		local Path = DiffDeserialized.Path
		local Value = DiffDeserialized.Value
		local Root = ReplicatorInstance.CurrentState

		if #Path == 0 then
			ReplicatorInstance.CurrentState = Value
		else
			for index, key in Path do
				if index == #Path then
					Root[key] = Value
				else
					if not Root[key] then
						Root[key] = {}
					end

					Root = Root[key]
				end
			end
		end

		ReplicatorInstance.Changed:Fire(Path, Value)
	end)

	RequestAllDataRemote:FireServer()
end

function Replicator.initServer()
	if RunService:IsClient() then
		error("Replicator.initServer() must be called on the server")
	end

	MainRemote = script:FindFirstChild("MainRemote")

	if MainRemote then
		error("Replicator has already been initialized on the server")
	end

	MainRemote = Instance.new("RemoteEvent")
	MainRemote.Name = "MainRemote"
	MainRemote.Parent = script

	RequestAllDataRemote = Instance.new("RemoteEvent")
	RequestAllDataRemote.Name = "RequestAllDataRemote"
	RequestAllDataRemote.Parent = script

	local LastTick = os.clock()

	RunService.Heartbeat:Connect(function()
		if os.clock() - LastTick < TICK_RATE then
			return
		end

		LastTick = os.clock()

		for _, queuedReplication in QueuedReplication do
			MainRemote:FireClient(queuedReplication.Player, queuedReplication.Identifier, SerDes.SerializeToBuffer({
				Path = queuedReplication.Path,
				Value = queuedReplication.Value,
			}))
			
			table.remove(QueuedReplication, table.find(QueuedReplication, queuedReplication))
		end
	end)

	RequestAllDataRemote.OnServerEvent:Connect(function(player : Player)
		if player:GetAttribute("_Replicator_HasRequestedAllData") then
			return
		end

		player:SetAttribute("_Replicator_HasRequestedAllData", true)

		for identifier, replicator in OccupiedIdentifiers do
			if not table.find(replicator.SubscribedPlayers, player) then
				continue
			end

			MainRemote:FireClient(player, identifier, SerDes.SerializeToBuffer({
				Path = {},
				Value = replicator.CurrentState,
			}))
		end
	end)
end

function Replicator.Set(self : Replicator, path : {string}, value : any)
	if RunService:IsClient() then
		error("Replicator:Set() must be called on the server")
	end

	local Root = self.CurrentState

	if #path == 0 then
		self.CurrentState = value
	else
		for index, key in path do
			if index == #path then
				Root[key] = value
			else
				if not Root[key] then
					Root[key] = {}
				end

				Root = Root[key]
			end
		end
	end

	self.Changed:Fire(path, value)

	for _, player in self.SubscribedPlayers do
		table.insert(QueuedReplication, {
			Player = player,
			Identifier = self.Identifier,
			Path = path,
			Value = value,
		})
	end
end

function Replicator.Get(self : Replicator)
	return table.clone(self.CurrentState)
end

function Replicator.Subscribe(self : Replicator, player : Player)
	if RunService:IsClient() then
		error("Replicator:Subscribe() must be called on the server")
	end

	if table.find(self.SubscribedPlayers, player) then
		return
	end

	table.insert(self.SubscribedPlayers, player)

	table.insert(QueuedReplication, {
		Player = player,
		Identifier = self.Identifier,
		Path = {},
		Value = self.CurrentState,
	})
end

function Replicator.Unsubscribe(self : Replicator, player : Player)
	if RunService:IsClient() then
		error("Replicator:Unsubscribe() must be called on the server")
	end

	for index, subscribedPlayer in self.SubscribedPlayers do
		if subscribedPlayer == player then
			table.remove(self.SubscribedPlayers, index)
		end
	end
end

function Replicator.SubscribeAll(self : Replicator)
	for _, player in PlayersService:GetPlayers() do
		self:Subscribe(player)
	end

	table.insert(self.Connections, PlayersService.PlayerAdded:Connect(function(player : Player)
		self:Subscribe(player)
	end))
end

function Replicator.Destroy(self : Replicator)
	if RunService:IsClient() then
		error("Replicator:Destroy() must be called on the server")
	end

	for _, player in self.SubscribedPlayers do
		self:Unsubscribe(player)
	end

	self.Changed:Destroy()
	self.CurrentState = nil
	OccupiedIdentifiers[self.Identifier] = nil

	for _, connection in self.Connections do
		connection:Disconnect()
	end

	self.Connections = nil

	table.freeze(self)
end

return Replicator