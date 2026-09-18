-- Author: iGottic

--[=[
	@class Symbol

	Blank userdata that can be converted into a string.
]=]

local Symbol = {}

-- Types

-- `typeof(newproxy())` is just `any`, so we don't do it.
export type Symbol = {
	AsString: (self: Symbol) -> (string)
}

--[=[
	Creates a blank userdata that can be converted into a string.

	@param Name string -- The string representing the symbol
	@return Symbol
]=]

function Symbol.new(Name : string): (Symbol)
	local self = newproxy(true)

	getmetatable(self).__tostring = function()
		return Name
	end

	return self
end

--[=[
	Creates a blank symbol.

	@return Symbol
]=]

function Symbol.newNameless(): (Symbol)
	local self = newproxy(true)

	return self
end

--[=[
	Equivalent to `tostring`, gets the string name from a Symbol.

	@param ThisSymbol Symbol -- The symbol you're checking
	@return Symbol
]=]

function Symbol.AsString(ThisSymbol : Symbol)
	return tostring(ThisSymbol)
end

return Symbol