--[=[
    DataStore wrapper with serialized table saves and reconciliation support.

    @class DataStore
]=]

local DataStore = {}

-- Constants
local DEFAULT_MAX_RETRIES = 5
local DEFAULT_RETRY_DELAY_SECONDS = 1

-- Services
local RunService = game:GetService("RunService")
local DataStoreService = game:GetService("DataStoreService")

-- Imports
local SerDes = require("@pkg/SerDes")

-- Types
export type SaveTable = {[any] : any}

export type Config = {
    Name : string,
    Scope : string?,
    Template : SaveTable,
    MaxRetries : number?,
    RetryDelaySeconds : number?,
}

export type StoreHandle = Config & {
    Store : GlobalDataStore,
}

if RunService:IsClient() then
	-- Note: Returns an empty table at this point, but we should not return a new empty table literal as the type solver
	-- won't be able to figure out the types.
    return DataStore
end

local function Retry(OperationName : string, Callback : () -> any, MaxRetries : number?, RetryDelaySeconds : number?)
    local Attempts = MaxRetries or DEFAULT_MAX_RETRIES
    local Delay = RetryDelaySeconds or DEFAULT_RETRY_DELAY_SECONDS
    local LastError = nil

    for Attempt = 1, Attempts do
        local Success, ResultOrError = pcall(Callback)

        if Success then
            return ResultOrError
        end

        LastError = ResultOrError

        if Attempt < Attempts then
            task.wait(Delay)
        end
    end

    error(`DataStore {OperationName} failed after {Attempts} attempts: {tostring(LastError)}`)
end

local function DeepClone(Value : any) : any
    if type(Value) ~= "table" then
        return Value
    end

    local NewTable = {}

    for Key, SubValue in Value do
        NewTable[DeepClone(Key)] = DeepClone(SubValue)
    end

    return NewTable
end

local function ReconcileInto(Template : SaveTable, Existing : SaveTable) : SaveTable
    local Result = DeepClone(Existing)

    for Key, TemplateValue in Template do
        local ExistingValue = Result[Key]

        if ExistingValue == nil then
            Result[Key] = DeepClone(TemplateValue)
        elseif type(TemplateValue) == "table" and type(ExistingValue) == "table" then
            Result[Key] = ReconcileInto(TemplateValue, ExistingValue)
        end
    end

    return Result
end

--[=[
    Creates a validated datastore handle from config.

    @param Config Config
    @return StoreHandle
]=]
function DataStore.CreateStore(Config : Config) : StoreHandle
    if type(Config) ~= "table" then
        error("DataStore.CreateStore expects a config table")
    end

    if type(Config.Name) ~= "string" then
        error("DataStore config requires Name as string")
    end

    if type(Config.Template) ~= "table" then
        error("DataStore config requires Template as table")
    end

    return {
        Name = Config.Name,
        Scope = Config.Scope,
        Template = DeepClone(Config.Template),
        MaxRetries = Config.MaxRetries or DEFAULT_MAX_RETRIES,
        RetryDelaySeconds = Config.RetryDelaySeconds or DEFAULT_RETRY_DELAY_SECONDS,
        Store = DataStoreService:GetDataStore(Config.Name, Config.Scope),
    }
end

--[=[
    Reconciles existing save data with template.

    Missing keys in existing save data are filled from template recursively.

    @param Template SaveTable
    @param ExistingSaveData SaveTable?
    @return SaveTable
]=]
function DataStore.Reconcile(Template : SaveTable, ExistingSaveData : SaveTable?) : SaveTable
    if ExistingSaveData == nil then
        return DeepClone(Template)
    end

    if type(ExistingSaveData) ~= "table" then
        error("Reconcile expects existing save data to be a table or nil")
    end

    return ReconcileInto(Template, ExistingSaveData)
end

--[=[
    Loads and deserializes save data as a table, then reconciles with template.

    @param StoreHandle StoreHandle
    @param Key string
    @return SaveTable
]=]
function DataStore.Load(StoreHandle : StoreHandle, Key : string) : SaveTable
    local Encoded = Retry("GetAsync", function()
        return StoreHandle.Store:GetAsync(Key)
    end, StoreHandle.MaxRetries, StoreHandle.RetryDelaySeconds)

    if Encoded == nil then
        return DataStore.Reconcile(StoreHandle.Template, nil)
    end

    if type(Encoded) ~= "string" then
        error("Stored save value must be a serialized string")
    end

    local SaveData = SerDes.DeserializeFromDataStore(Encoded)

    if type(SaveData) ~= "table" then
        error("Deserialized save value must be a table")
    end

    return DataStore.Reconcile(StoreHandle.Template, SaveData)
end

--[=[
    Serializes and saves a table.

    @param StoreHandle StoreHandle
    @param Key string
    @param SaveData SaveTable
]=]
function DataStore.Save(StoreHandle : StoreHandle, Key : string, SaveData : SaveTable)
    if type(SaveData) ~= "table" then
        error("Save expects SaveData as table")
    end

    local Reconciled = DataStore.Reconcile(StoreHandle.Template, SaveData)
    local Encoded = SerDes.SerializeForDataStore(Reconciled)

    Retry("SetAsync", function()
        StoreHandle.Store:SetAsync(Key, Encoded)
        return true
    end, StoreHandle.MaxRetries, StoreHandle.RetryDelaySeconds)
end

--[=[
    Atomically updates save data as a table.

    @param StoreHandle StoreHandle
    @param Key string
    @param Transform (SaveData : SaveTable) -> SaveTable
    @return SaveTable
]=]
function DataStore.Update(StoreHandle : StoreHandle, Key : string, Transform : (SaveData : SaveTable) -> SaveTable) : SaveTable
    local Encoded = Retry("UpdateAsync", function()
        return StoreHandle.Store:UpdateAsync(Key, function(CurrentEncoded)
            local CurrentData : SaveTable?

            if CurrentEncoded ~= nil then
                if type(CurrentEncoded) ~= "string" then
                    error("Stored save value must be a serialized string")
                end

                local Decoded = SerDes.DeserializeFromDataStore(CurrentEncoded)

                if type(Decoded) ~= "table" then
                    error("Deserialized save value must be a table")
                end

                CurrentData = Decoded
            end

            local Reconciled = DataStore.Reconcile(StoreHandle.Template, CurrentData)
            local Updated = Transform(Reconciled)

            if type(Updated) ~= "table" then
                error("Update transform must return a table")
            end

            local UpdatedReconciled = DataStore.Reconcile(StoreHandle.Template, Updated)
            return SerDes.SerializeForDataStore(UpdatedReconciled)
        end)
    end, StoreHandle.MaxRetries, StoreHandle.RetryDelaySeconds)

    if Encoded == nil then
        return DataStore.Reconcile(StoreHandle.Template, nil)
    end

    if type(Encoded) ~= "string" then
        error("Stored save value must be a serialized string")
    end

    local SaveData = SerDes.DeserializeFromDataStore(Encoded)

    if type(SaveData) ~= "table" then
        error("Deserialized save value must be a table")
    end

    return DataStore.Reconcile(StoreHandle.Template, SaveData)
end

return DataStore
