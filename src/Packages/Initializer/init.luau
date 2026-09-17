--[=[
    Safely initializes modules, either ordered or unordered.

    @class Initializer
]=]

local Initializer = {}

-- Constants
local INITIALIZED_TAG_INDEX = "__HAS_INITIALIZED"

Initializer.Config = {
    InitializeFunctionName = "Init",
    ShowLoadDebug = true,

    ThrownWarnings = {
        NoInitFunction = true,
        NotAModule = true,
        ErrorThrown = true,
        NotATableModule = true,
        AlreadyInitialized = true,
        NoOrderDefined = true,
    }
}

-- We could use keyof<typeof(Initializer.Config.ThrownWarnings)> if old solver compatibility is not a requirement
type WarningType = "NoInitFunction" | "NotAModule" | "ErrorThrown" | "NotATableModule" | "AlreadyInitialized" | "NoOrderDefined"

local function ThrowWarning(WarningType : WarningType, WarningMessage : string)
    if not Initializer.Config.ThrownWarnings[WarningType] then
        return
    end

    warn(`[WARNING_{WarningType}]: {WarningMessage}{"\n"}{debug.traceback()}`)
end

local function OrderChildren(Children : {Instance}, Order : {string})
    table.sort(Children, function(a : Instance, b : Instance)
        local IndexA = table.find(Order, a.Name)
        local IndexB = table.find(Order, b.Name)

        if not IndexA then
            return false
        elseif not IndexB then
            return true
        end

        return IndexA < IndexB
    end)

    return Children
end

--[=[
    Initializes a module, preventing re-initalization and thrown errors.

    ```lua
    local Module = path.to.module -- Don't require it!

    Initializer.InitModuleAsync(Module)
    ```

    @param Object Instance -- The module being initialized
]=]

function Initializer.InitModuleAsync(Object : ModuleScript)
    if not Object:IsA("ModuleScript") then
        ThrowWarning("NotAModule", `Attempt to initialize non-module ({Object:GetFullName()})`)
        return
    end

    local DidRequire, Module = pcall(function()
        return require(Object) :: any
    end)

    if not DidRequire then
        ThrowWarning("ErrorThrown", `Attempt to load module {Object:GetFullName()}, but error was thrown during require: {Module}`)
        return
    end

    if typeof(Module) ~= "table" then
        ThrowWarning("NotATableModule", `Attempt to load module {Object:GetFullName()}, but it did not return a table`)
        return
    end

    if not Module[Initializer.Config.InitializeFunctionName] then
        ThrowWarning("NoInitFunction", `Attempt to init module {Object:GetFullName()}, but it does not have function name "{Initializer.Config.InitializeFunctionName}"`)
        return
    end

    if Module[INITIALIZED_TAG_INDEX] then
        ThrowWarning("AlreadyInitialized", `Attempt to init module {Object:GetFullName()}, but it was already initialized`)
        return
    end

    local DidInitialize, Issue = pcall(Module[Initializer.Config.InitializeFunctionName])

    if not DidInitialize then
        ThrowWarning("ErrorThrown", `Attempt to init module {Object:GetFullName()}, but error was thrown during init call: {Issue}`)
        return
    end

    Module[INITIALIZED_TAG_INDEX] = true

    if Initializer.Config.ShowLoadDebug then
        print(`[INITIALIZER DEBUG] Initialized module {Object:GetFullName()}`)
    end
end

--[=[
    Initializes children modules in a bin, unordered.

    ```lua
    local Folder = path.to.folder

    Initializer.InitFolderAsync(Folder)
    ```

    @param Folder Instance -- The bin of modules being initialized
]=]

function Initializer.InitFolderAsync(Folder : Instance)
    for _, Child: ModuleScript in Folder:GetChildren() do
        Initializer.InitModuleAsync(Child)
    end
end

--[=[
    Initializes children modules in a bin, ordered based on an inputted array of module names.

    ```lua
    local Folder = path.to.folder
    local Order = {"FirstModule", "SecondModule", "ThirdModule"}

    Initializer.InitOrderedFolderAsync(Folder, Order)
    ```

    @param Folder Instance -- The bin of modules being initialized
    @param Order {string} -- The load order
]=]

function Initializer.InitOrderedFolderAsync(Folder : Instance, Order : {string})
    if not Order or #Order == 0 then
        ThrowWarning("NoOrderDefined", `No order defined when loading folder {Folder:GetFullName()}`)
        return
    end

    local OrderedChildren = OrderChildren(Folder:GetChildren(), Order)

    for _, Child: ModuleScript in OrderedChildren do
        Initializer.InitModuleAsync(Child)
    end
end

return Initializer