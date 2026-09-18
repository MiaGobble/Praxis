local Inventory = {}

-- Types
type ItemDataInput = {
    ItemId : string,
    [string] : any,
}

export type ItemData = ItemDataInput & {
    Quantity : number,
}

export type InventoryData = {
    Items : {ItemData}
}

-- Services
local HttpService = game:GetService("HttpService")

-- Imports
local Typer = require("@pkg/Typer")

function Inventory.AddItemToInventory(InventoryData : InventoryData, ItemData : ItemDataInput, MaxStack : number) : InventoryData
    Typer.TupleAssertion("table", "string")(ItemData, ItemData.ItemId)

    if not MaxStack then
        MaxStack = 1
    end

    local OpenStack = nil

    for _, ThisItem : ItemData in InventoryData.Items do
        if ThisItem.ItemId == ItemData.ItemId and ThisItem.Quantity < MaxStack then
            if OpenStack and OpenStack.Quantity < ThisItem.Quantity then
                continue
            end

            OpenStack = ThisItem
        end
    end

    if OpenStack then
        OpenStack.Quantity += 1
    else
        ItemData = table.clone(ItemData)
        ItemData.Quantity = 1
        table.insert(InventoryData.Items, ItemData)
    end

    return InventoryData
end

function Inventory.RemoveItemFromInventory(InventoryData : InventoryData, ItemId : string) : InventoryData
    local OpenStack = nil

    for _, ThisItem : ItemData in InventoryData.Items do
        if ThisItem.ItemId == ItemId then
            if OpenStack and OpenStack.Quantity < ThisItem.Quantity then
                continue
            end

            OpenStack = ThisItem
        end
    end

	if not OpenStack then
		warn("OpenStack is missing")
		return InventoryData
	end

    if OpenStack.Quantity > 1 then
        OpenStack.Quantity -= 1
    else
        table.remove(InventoryData.Items, table.find(InventoryData.Items, OpenStack))
    end

    return InventoryData
end

function Inventory.DoesOwnItem(InventoryData : InventoryData, ItemId : string) : boolean
    for _, ThisItem : ItemData in InventoryData.Items do
        if ThisItem.ItemId == ItemId then
            return true
        end
    end

    return false
end

function Inventory.GetBlankInventoryData() : InventoryData
    local InventoryData : InventoryData = {
        Items = {},
    }

    return InventoryData
end

function Inventory.SerializeInventory(InventoryData : InventoryData) : string
    return HttpService:JSONEncode(InventoryData)
end

function Inventory.UnserializeInventory(SerializedData : string) : InventoryData
    return HttpService:JSONDecode(SerializedData)
end

return Inventory