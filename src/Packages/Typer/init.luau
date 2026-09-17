--[=[
	@class Typer

	Strict typechecking in runtime implementation for Roblox.
]=]

local Typer = {}

--[=[
	Wraps a function so that all parameters and return values are matched to the correct types.

	```lua
	local ExampleStaticFunction = Typer.Static(function(Foo : number, Bar : string)
		return `{Foo} and {Bar}`, {Foo = Foo, Bar = Bar}
	end).WithParameterTypes("number", "string").WithReturnTypes("string", "table").Asserted()

	local Value0, Value1 = ExampleStaticFunction(10, "Hello!") -- Does not error
	local Value2, Value3 = ExampleStaticFunction({}, true) -- Errors
	```

	@param CallbackFunction (any?) -> any? -- The wrapped function
	@return StaticFunction
]=]

function Typer.Static(CallbackFunction : (any?) -> any?)
	local self = {}
	local ParameterAssertion = nil
	local ReturnAssertion = nil
	
	function self.WithParameterTypes(...)
		ParameterAssertion = Typer.TupleAssertion(...)
		return self
	end
	
	function self.WithReturnTypes(...)
		ReturnAssertion = Typer.TupleAssertion(...)
		return self
	end
	
	function self.Asserted(): ((...any) -> (...any?))?
		if ParameterAssertion and ReturnAssertion then
			return function(...)
				local Args = {...}
				
				if ParameterAssertion then
					ParameterAssertion(unpack(Args))
				end
				
				local ReturnedValues = {CallbackFunction(...)}

				if ReturnAssertion then
					local Success, Output = pcall(function()
						(ReturnAssertion :: any)(unpack(ReturnedValues))
					end)

					if not Success then
						error(`An error occurred when expecting return Types from static function: {Output}`)
					end
				end
				
				return unpack(ReturnedValues)
			end
		end

		return nil
	end
	
	return self
end

--[=[
	Checks if a value is of a certain type, allowing multiple types

	```lua
	local MyValue = "Hello, world!"

	Typer.Cast(MyValue)("number", "string") -- No error
	Typer.Cast(MyValue)("table") -- Error
	```

	@param Value any -- The cast value
	@return (... : string) : any -- The casting method
]=]

function Typer.Cast<T>(Value : T) : (...string) -> T
	return function(... : string) : T
		if not table.find({...}, typeof(Value)) then
			error(`Expected casted Value to be a {table.concat({...}, ", or ")}, instead got a {typeof(Value)} type`)
		end
		
		return Value
	end
end

--[=[
	Checks if two values are of the same type, and returns a boolean based on whether they are the same value as well.

	```lua
	local Value0 = Typer.CastEq(1, 2) -- No error
	print(Value0) -- Prints "false"

	local Value1 = Typer.CastEq("Foo", "Foo") -- No error
	print(Value1) -- Prints "true"

	local Value2 = Typer.CastEq(1, "Foo") -- Error
	```

	@param Value0 -- The first value for comparison
	@param Value1 -- The second value for comparison
	@return boolean -- Whether the values are the same
]=]

function Typer.CastEq(Value0 : any, Value1 : any)
	if typeof(Value0) ~= typeof(Value1) then
		error(`Attempted to compare a {typeof(Value0)} to a {typeof(Value1)}`)
	end
	
	return Value0 == Value1
end

--[=[
	Throws an error if inputted types do not match inputted argments in order.

	```lua
	Typer.TupleAssertion("number", "boolean", "string")(1, true, "Alo") -- No error
	Typer.TupleAssertion("boolean", "table")(1, 2) -- Throws error
	```

	@param ... string -- The inputted types, in order
	@return (... any) -- The function used to check arguments
]=]

function Typer.TupleAssertion(... : string)
	local Types = {...}
	
	return function(... : any)
		local Args = {...}
		
		for Index, ThisType in Types do
			if typeof(Args[Index]) ~= ThisType then
				error(`Tuple #{Index} in function does not match type; expected a {ThisType}, got a {typeof(Args[Index])}.`)
			end
		end
	end
end

--[=[
	A wrapper for Typer.TupleAssertion, allowing callbacks for different outcomes.

	```lua
	Typer.Expect(1, 2, 3).ToBe("number", "number", "number").AndIfNot(function()
		print("Uh oh!")
	end).AndIfSo(function()
		print("Yay!")
	end) -- Prints "Yay!"

	Typer.Expect(true, false, true).ToBe("number", "number", "number").AndIfNot(function()
		print("Uh oh!")
	end).AndIfSo(function()
		print("Yay!")
	end) -- Prints "Uh oh!"
	```

	@param ... any -- The arguments to be checked
	@return ExpectInstance -- The table of methods to be called back, each returning itself 
]=]

function Typer.Expect(... : any)
	local self = {}
	
	local Args = {...}
	local Success, Output
	
	function self.ToBe(... : string)
		local Types = {...}
		
		Success, Output = pcall(function()
			Typer.TupleAssertion(unpack(Types))(unpack(Args))
		end)
		
		return self
	end
	
	function self.AndIfNot(Callback : (any?) -> nil)
		if not Success then
			Callback(Output)
		end
		
		return self
	end
	
	function self.AndIfSo(Callback : (any?) -> nil)
		if Success then
			Callback(Output)
		end
		
		return self
	end
	
	return self
end

--[=[
	Creates a proxy table that allows access to values stored in it, but does not allow edits to values already declared.
	It also can be called like a function with a command indicator. Commands are: DumpAll, DumpValue, PrintAll, PrintValue.

	```lua
	local Environment = Typer.Env()

	Environment.Foo = 5
	Environment.Bar = 10

	print(Environment.Foo) -- Prints "5"
	print(Environment.Bar) -- Prints "10"
	print(Environment.DoesntExist) -- Prints nil and throws warning

	Environment("DumpAll") -- Dumps all values, turning them to nil

	Environment.Foo = 5

	print(Environment.Foo) -- Prints "5"
	print(Environment.Bar) -- Prints nil and throws warning

	Environment.Foo = 10 -- Throws error since it already exists
	```

	@return Environment -- The created proxy table
]=]

function Typer.Env() : typeof(setmetatable({},{}))
	local self = {}
	
	return setmetatable({}, {
		__index = function(_, Index)
			if not self[Index] then
				warn(`Attemped to access an immutable Value named "{Index}" but it does not exist, returning nil`)
			end
			
			return self[Index]
		end,
		
		__newindex = function(_, Index, Value)
			if self[Index] then
				error("Attemped to modify an immutable Value")
			end
			
			self[Index] = Value
			
			if typeof(Value) == "Instance" then
				Value.AncestryChanged:Connect(function()
					if Value:FindFirstAncestor(game) == nil then
						self[Index] = nil
					end
				end)
			end
		end,
		
		__call = function(_, Command, ...)
			({
				DumpAll = function()
					self = {}
				end,
				
				DumpValue = function(Index)
					self[Index] = nil
				end,
				
				PrintAll = function()
					print(self)
				end,
				
				PrintValue = function(Index)
					print(self[Index])
				end,
			})[Command](...)
		end,
	})
end

return Typer