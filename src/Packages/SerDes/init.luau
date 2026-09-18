--[=[
    Serialization and deserialization utilities using ValuePacker with buffer support.

    @class SerDes
]=]

local SerDes = {}

-- Services
local HttpService = game:GetService("HttpService")

-- Imports
local ValuePacker = require("@pkg/ValuePacker")

-- Types
type EncodedNode = {
    t : string,
    v : any?,
    vt : string?,
    d : {number}?,
    e : {{k : EncodedNode, v : EncodedNode}}?,
}

local VALUE_PACKER_TYPES : {[string] : boolean} = {
    number = true,
    CFrame = true,
    Color3 = true,
    ColorSequenceKeypoint = true,
    DateTime = true,
    NumberRange = true,
    NumberSequenceKeypoint = true,
    PhysicalProperties = true,
    Ray = true,
    Rect = true,
    Region3 = true,
    Region3int16 = true,
    UDim = true,
    UDim2 = true,
    Vector2 = true,
    Vector2int16 = true,
    Vector3 = true,
    Vector3int16 = true,
}

local function BufferToByteArray(PackedBuffer : buffer) : {number}
    local ByteLength = buffer.len(PackedBuffer)
    local Bytes = table.create(ByteLength) :: {number}

    for Index = 0, ByteLength - 1 do
        Bytes[Index + 1] = buffer.readu8(PackedBuffer, Index)
    end

    return Bytes
end

local function ByteArrayToBuffer(Bytes : {number}) : buffer
    local PackedBuffer = buffer.create(#Bytes)

    for Index, Byte in Bytes do
        if type(Byte) ~= "number" or Byte < 0 or Byte > 255 or math.floor(Byte) ~= Byte then
            error("Corrupted byte array during deserialization")
        end

        buffer.writeu8(PackedBuffer, Index - 1, Byte)
    end

    return PackedBuffer
end

local function Encode(Value : any) : EncodedNode
    if Value == nil then
        return {t = "nil"}
    end

    local ValueType = typeof(Value)

    if ValueType == "boolean" or ValueType == "string" then
        return {
            t = ValueType,
            v = Value,
        }
    end

    if VALUE_PACKER_TYPES[ValueType] then
        return {
            t = "vp",
            vt = ValueType,
            d = ValuePacker.UnpackValue(Value, ValueType),
        }
    end

    if ValueType == "table" then
        local Entries = {}

        for Key, SubValue in Value do
            table.insert(Entries, {
                k = Encode(Key),
                v = Encode(SubValue),
            })
        end

        return {
            t = "table",
            e = Entries,
        }
    end

    error("Unsupported value type for serialization: " .. ValueType)
end

local function Decode(Node : EncodedNode) : any
    if Node.t == "nil" then
        return nil
    end

    if Node.t == "boolean" or Node.t == "string" then
        return Node.v
    end

    if Node.t == "vp" then
        if not Node.vt or not Node.d then
            error("Corrupted vp node during deserialization")
        end

        return ValuePacker.PackValue(Node.d, Node.vt)
    end

    if Node.t == "table" then
        local NewTable = {}

        for _, Entry in Node.e or {} do
            NewTable[Decode(Entry.k)] = Decode(Entry.v)
        end

        return NewTable
    end

    error("Unsupported encoded node type during deserialization: " .. tostring(Node.t))
end

--[=[
    Serializes any supported value into a buffer.

    @param Value any
    @return buffer
]=]
function SerDes.SerializeToBuffer(Value : any) : buffer
    local Encoded = Encode(Value)
    local Json = HttpService:JSONEncode(Encoded)
    return buffer.fromstring(Json)
end

--[=[
    Deserializes a value from a buffer.

    @param PackedBuffer buffer
    @return any
]=]
function SerDes.DeserializeFromBuffer(PackedBuffer : buffer) : any
    local Json = buffer.tostring(PackedBuffer)
    local Encoded = HttpService:JSONDecode(Json)
    return Decode(Encoded)
end

--[=[
    Serializes any supported value to a DataStore-safe string.

    @param Value any
    @return string
]=]
function SerDes.SerializeForDataStore(Value : any) : string
    local PackedBuffer = SerDes.SerializeToBuffer(Value)
    local Payload = {
        v = 1,
        b = BufferToByteArray(PackedBuffer),
    }

    return HttpService:JSONEncode(Payload)
end

--[=[
    Deserializes a value from a DataStore-safe string.

    @param Encoded string
    @return any
]=]
function SerDes.DeserializeFromDataStore(Encoded : string) : any
    local Payload = HttpService:JSONDecode(Encoded)

    if type(Payload) ~= "table" or type(Payload.b) ~= "table" then
        error("Corrupted datastore payload during deserialization")
    end

    local PackedBuffer = ByteArrayToBuffer(Payload.b)
    return SerDes.DeserializeFromBuffer(PackedBuffer)
end

return SerDes