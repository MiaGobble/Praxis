--[=[
    @class Select

    Used to select singular values from a list of arguments.
]=]

local Select = {}

--[=[
    @param index number -- The index of the value to select
    @param ... any -- The values to select from
    @return any? -- The selected value

    Selects the value at the given index.

    ```lua
    if Select.Only(2, false, true) then
        -- This will run
    end
    ```
]=]

function Select.Only<T>(index : number, ... : T?) : T?
    local Args = {...}

    return Args[index]
end

--[=[
    @param ... any -- The values to select from
    @return any? -- The first selected value

    Selects the first value from the given arguments.

    ```lua
    local MyString = "Hello World"
    print(Select.First(MyString:gsub("Hello", "World"))) -- "World World"
    ```
]=]

function Select.First<T>(... : T?) : T?
    local Args = {...}

    return Args[1]
end

--[=[
    @param ... any -- The values to select from
    @return any? -- The last selected value
    
    Selects the last value from the given arguments.
    
    ```lua
    print(Select.Last(1, 2, 3)) -- 3
    ```
]=]

function Select.Last<T>(... : T?) : T?
    local Args = {...}
    return Args[#Args]
end

--[=[
    @param ... any -- The values to select from
    @return any? -- The random selected value
    
    Selects a random value from the given arguments.
    
    ```lua
    print(Select.Random(1, 2, 3)) -- 1, 2, or 3
    ```
]=]

function Select.Random<T>(... : T?) : T?
    local Args = {...}

    return Args[math.random(1, #Args)]
end

return Select