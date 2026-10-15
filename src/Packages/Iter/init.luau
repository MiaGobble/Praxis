--!native
--!optimize 2

-- Author: glaphyre

local Module = {}

--[=[
	@class Iter
	
	Lazy iterator helpers for Luau.
]=]
local Iter = {}
Iter.__index = Iter

-- Iterator Types

--[=[
	@type NextFunction<T> () -> T?
	@within Iter
]=]
export type NextFunction<T> = () -> T?

--[=[
	@type SizeHintFunction () -> (number, number?)
	@within Iter
]=]
export type SizeHintFunction = () -> (number, number?)

--[=[
	@within Iter

	@interface IterProps<T>
	.Next NextFunction -- Advances the Iterator and returns the next value; Returns `nil` when iteration is finished.
	.SizeHint SizeHintFunction -- Returns the bounds on the remaining length of the Iterator.
]=]
export type IterProps<T> = {
	Next: NextFunction<T>,
	SizeHint: SizeHintFunction?,
}
export type Iter<T = unknown> = typeof(Module.new(...))

--[=[
	@type Iterable<K, V> {[K]: V}
	@within Iter
]=]
export type Iterable<K, V> = { [K]: V }

--[=[
	@interface Pair<A, B>
	.First A
	.Second B

	@within Iter
]=]
export type Pair<A, B> = { First: A, Second: B }

function Iter.__call<T>(self: Iter<T>): T?
	return self.Next()
end

function Iter.__iter<T>(self: Iter<T>): NextFunction<T>
	return self.Next
end

local function GetSize(iterable: { [unknown]: unknown }): number
	local Index = 0
	for _, _ in iterable do
		Index += 1
	end
	return Index
end

-- Iterator Constructors

--[=[
	Creates a new Iterator, given the `next` and `sizeHint` methods.

	@within Iter
	@tag Constructors

	@function new
	@param next () -> T?
	@param sizeHint () -> (number, number?)
	@return Iter<T>
]=]
function Module.new<T>(next: NextFunction<T>, sizeHint: SizeHintFunction)
	local self = setmetatable({
		Next = next,
		SizeHint = sizeHint,
	}, Iter)
	return self
end

--[=[
	Creates and returns an Iterator of the keys of the given iterable.

	@within Iter
	@tag Constructors

	@function fromKeys
	@param iterable { [K]: V }
	@return Iter<K>
]=]
function Module.fromKeys<K, V>(iterable: { [K]: V }): Iter<K>
	local Size = GetSize(iterable)
	local Key: K?, _: V?

	return Module.new(function(): K?
		Key, _ = next(iterable, Key)
		Size -= 1
		return Key
	end, function(): (number, number?)
		return Size, Size
	end)
end

--[=[
	Creates and returns an Iterator of the values of the given iterable.

	@within Iter
	@tag Constructors

	@function fromValues
	@param iterable { [K]: V }
	@return Iter<V>
]=]
function Module.fromValues<K, V>(iterable: { [K]: V }): Iter<V>
	local Size = GetSize(iterable)
	local Key: K?, Value: V?

	return Module.new(function(): V?
		Key, Value = next(iterable, Key)
		Size -= 1
		return Value
	end, function(): (number, number?)
		return Size, Size
	end)
end

--[=[
	Creates and returns an empty Iterator.

	@within Iter
	@tag Constructors

	@function empty
	@return Iter
]=]
function Module.empty(): Iter
	return Module.new(function()
		return nil
	end, function(): (number, number?)
		return 0, 0
	end)
end

--[=[
	Creates a sequential Iterator, starting at `start` and incrementing by `step`.
	
	The first value returned will always be `start + step` and not `start`.

	Its bounds are defined by `(start, inf]`

	@within Iter
	@tag Constructors

	@function iota
	@param start number
	@param step number
	@return Iter<number>
]=]
function Module.iota(start: number, step: number): Iter<number>
	return Module.new(function(): number
		start += step
		return start
	end)
end

-- Iterator methods

--[=[
	Takes a function and creates an Iterator which calls that function on each element.
	
	If you have an Iterator that gives you elements of some type `A`, and you want an Iterator of some other type `B`,
	you can use `Map()`, passing a function that takes an `A` and returns a `B`.

	```lua
	local A = { 1, 2, 3 }

	local Iterator = Iter.fromValues(A):Map(function(val: number): number
		return val * 2
	end)

	assert(Iterator.Next() == 2)
	assert(Iterator.Next() == 4)
	assert(Iterator.Next() == 6)
	assert(Iterator.Next() == nil)
	```

	@within Iter
	@tag Adapters

	@function Map
	@param self Iter<A>
	@param f (A) -> B
	@return Iter<B>
]=]
function Iter.Map<A, B>(self: Iter<A>, f: (A) -> B): Iter<B>
	return Module.new(function(): B?
		local Item = self.Next()
		if Item == nil then
			return nil
		end
		return f(Item)
	end, self.SizeHint)
end

--[=[
	Creates an Iterator which uses a function to determine if an element should be yielded.

	Given an element the function must return `true` or `false`. The returned Iterator will yield only the elements for which the
	function returns `true`.

	```lua
	local A = { -1, 0, 1, 2 }

	local Iterator = Iter.fromValues(A):Filter(function(val: number): boolean
		return val > 0
	end)

	assert(Iterator.Next() == 1)
	assert(Iterator.Next() == 2)
	assert(Iterator.Next() == nil)
	```

	@within Iter
	@tag Adapters

	@function Filter
	@param self Iter<T>
	@param predicate (T) -> boolean
	@return Iter<T>
]=]
function Iter.Filter<T>(self: Iter<T>, predicate: (T) -> boolean): Iter<T>
	return Module.new(function(): T?
		for item: T in self do
			if predicate(item) then
				return item
			end
		end
		return nil
	end, function(): (number, number?)
		local Min, Max = 0, nil
		if self.SizeHint then
			_, Max = self.SizeHint()
		end
		return Min, Max
	end)
end

--[=[
	Creates an Iterator that yields the first `n` elements, or fewer if the underlying Iterator ends sooner.

	`Take(n)` yields elements until n elements are yielded or the end of the Iterator is reached (whichever happens first). The returned Iterator is a prefix of length `n`
	if the original Iterator contains at least `n` elements, otherwise it contains all of the (fewer than `n`) elements of the original Iterator.

	```lua
	local A = { 1, 2, 3 }
	local Iterator = Iter.fromValues(A):Take(2)

	assert(Iterator.Next() == 1)
	assert(Iterator.Next() == 2)
	assert(Iterator.Next() == nil)
	```

	`Take()` is often used with an infinite Iterator, to make it finite:
	```lua
	local Iterator = Iter.iota(0, 1):Take(3)

	assert(Iterator.Next() == 1)
	assert(Iterator.Next() == 2)
	assert(Iterator.Next() == 3)
	assert(Iterator.Next() == nil)
	```

	@within Iter
	@tag Adapters

	@function Take
	@param self Iter<T>
	@param count number
	@return Iter<T>
]=]
function Iter.Take<T>(self: Iter<T>, count: number): Iter<T>
	return Module.new(function(): T?
		if count <= 0 then
			return nil
		end
		count -= 1
		return self.Next()
	end, function(): (number, number?)
		return count, count
	end)
end

--[=[
	"Zips up" two iterators into a single Iterator of pairs.

	`Zip()` returns a new Iterator that will iterate over two other iterators, returning a `Pair` where the first element comes from the first Iterator, and the second
	element comes from the second Iterator.

	In other words, it zips two iterators together, into a single one.

	If either Iterator returns `nil`, next from the zipped Iterator will return `nil`. If the zipped Iterator has no more elements to return then each further attempt to
	advance it will first try to advance the first Iterator at most one time and if it still yielded an item try to advance the second Iterator at most one time.

	```lua
	local A = Iter.fromValues({ 1, 2, 3 })
	local B = Iter.fromValues({ 4, 5, 6 })

	local Zipped = A:Zip(B)

	-- This will *not* work in actual Luau code, but you get the idea.
	assert(Zipped.Next() == { First = 1, Second = 4 })
	assert(Zipped.Next() == { First = 2, Second = 5 })
	assert(Zipped.Next() == { First = 3, Second = 6 })
	assert(Zipped.Next() == nil)
	```

	@within Iter
	@tag Adapters

	@function Zip
	@param self Iter<A>
	@param other Iter<B>
	@return Iter<Pair<A, B>>
]=]
function Iter.Zip<A, B>(self: Iter<A>, other: Iter<B>): Iter<Pair<A, B>>
	return Module.new(function(): Pair<A, B>?
		local First = self.Next()
		local Second = other.Next()

		if First == nil or Second == nil then
			return nil
		end
		return { First = First, Second = Second }
	end, function(): (number, number?)
		local Min, Max = 0, nil
		if self.SizeHint and other.SizeHint then
			local Min1, Max1 = self.SizeHint()
			local Min2, Max2 = other.SizeHint()
			Min = math.min(Min1, Min2)
			Max = math.min(Max1 or Min1, Max2 or Min2)
		elseif self.SizeHint then
			Min, Max = self.SizeHint()
		elseif other.SizeHint then
			Min, Max = other.SizeHint()
		end
		return Min, Max
	end)
end

--[=[
	Creates an Iterator which gives the current iteration count as well as the next value.

	The Iterator returned yields pairs `(i, val)`, where `i` is the current index of iteration and `val` is the value returned by the Iterator.

	```lua
	local MyTable = { "A", "B", "C" }

	local Enumerated = Iter.fromValues(MyTable):Enumerate()

	-- This will *not* work in actual Luau code, but you get the idea.
	assert(Enumerated.Next() == { First = 1, Second = "A" })
	assert(Enumerated.Next() == { First = 2, Second = "B" })
	assert(Enumerated.Next() == { First = 3, Second = "C" })
	assert(Enumerated.Next() == nil)
	```

	@within Iter
	@tag Adapters

	@function Enumerate
	@param self Iter<T>
	@return Iter<Pair<number, T>>
]=]
function Iter.Enumerate<T>(self: Iter<T>): Iter<Pair<number, T>>
	return Module.iota(0, 1):Zip(self)
end

-- Iterator Consumers

--[=[
	Folds every element into an accumulator by applying an operation, returning the final result.

	`Fold()` takes two arguments: an initial value, and a function with two arguments: an `accumulator`, and an element. The function returns the value that the
	accumulator should have for the next iteration.

	The initial value is the value the accumulator will have on the first call.

	After applying this function to every element of the Iterator, `Fold()` returns the accumulator.

	Folding is useful whenever you have a collection of something, and want to produce a single value from it.

	```lua
	local A = { 1, 2, 3 }

	local Sum = Iter.fromValues(A):Fold(0, function(acc: number, x: number)
		return acc + x
	end)

	assert(Sum == 6)
	```

	@within Iter
	@tag Consumers

	@function Fold
	@param self Iter<T>
	@param initial T
	@param folder (A, T) -> A
	@return A
]=]
function Iter.Fold<T, A>(self: Iter<T>, initial: T, folder: (A, T) -> A): A
	local Accumulated = initial
	for item: T in self do
		Accumulated = folder(Accumulated, item)
	end
	return Accumulated
end

--[=[
	Reduces the elements to a single one, by repeatedly applying a reducing operation.

	If the Iterator is empty, returns `nil`; otherwise, returns the result of the reduction.

	The reducing function is a function with two arguments: an ‘accumulator’, and an element. For iterators with at least one element, this is the same as `Fold()` with
	the first element of the Iterator as the initial accumulator value, folding every subsequent element into it.

	```lua
	local Reduced = Iter.iota(0, 1):Take(10):Reduce(function(acc: number, e: number)
		return acc + e
	end)
	assert(Reduced == 45)

	-- Which is equivalent to doing it with `Fold`:
	local Folded = Iter.iota(0, 1):Take(10):Fold(0, function(acc: number, e: number)
		return acc + e
	end)
	assert(Reduced == Folded)
	```

	@within Iter
	@tag Consumers

	@function Reduce
	@param self Iter<T>
	@param reducer (T, T) -> T
	@return T?
]=]
function Iter.Reduce<T>(self: Iter<T>, reducer: (T, T) -> T): T?
	local Initial = self.Next()
	if Initial == nil then
		return
	end
	return self:Fold(Initial, reducer)
end

--[=[
	Calls a function on each element of an Iterator.
	
	```lua
	-- Prints all the values from the Iterator.
	local A = Iter.fromValues({ 1, 2, 3, 4, 5 }):ForEach(print)
	```

	@within Iter
	@tag Consumers

	@function ForEach
	@param self Iter<T>
	@param callback (T) -> ()
]=]
function Iter.ForEach<T>(self: Iter<T>, callback: (T) -> ()): ()
	for item: T in self do
		callback(item)
	end
end

--[=[
	Consumes the Iterator without yielding a result.

	@within Iter
	@tag Consumers

	@function Drain
	@param self Iter<T>
]=]
function Iter.Drain<T>(self: Iter<T>): ()
	for _ in self do
	end
end

--[=[
	Tests if any element of the Iterator matches a predicate.

	`Any()` takes a function that returns `true` or `false`. It applies this function to each element of the Iterator, and if any of them return `true`, then so does `Any()`.
	If they all return `false`, it returns `false`.

	`Any()` is short-circuiting; in other words, it will stop processing as soon as it finds a `true`, given that no matter what else happens, the result will also be `true`.

	An empty Iterator returns `false`.

	```lua
	local A = Iter.fromValues({ 1, 2, 3 })

	local function IsPositive(x: number): boolean
		return x > 0
	end
	local function IsNegative(x: number): boolean
		return x < 0
	end

	assert(A:Any(IsPositive))
	assert(not A:Any(IsNegative))
	```

	@within Iter
	@tag Consumers

	@function Any
	@param self Iter<T>
	@param predicate (T) -> boolean
	@return boolean
]=]
function Iter.Any<T>(self: Iter<T>, predicate: (T) -> boolean): boolean
	for item: T in self do
		if predicate(item) then
			return true
		end
	end
	return false
end

--[=[
	Tests if every element of the Iterator matches a predicate.

	`All()` takes a function that returns true or `false`. It applies this function to each element of the Iterator, and if they all return `true`, then so does `All()`.
	If any of them return `false`, it returns `false`.

	`All()` is short-circuiting; in other words, it will stop processing as soon as it finds a `false`, given that no matter what else happens, the result will also be `false`.

	An empty Iterator returns `true`.

	```lua
	local A = Iter.fromValues({ 1, 2, 3 })
	
	local function IsGreaterThanTwo(x: number)
		return x > 2
	end

	assert(not A:All(IsGreaterThanTwo))
	```

	@within Iter
	@tag Consumers

	@function All
	@param self Iter<T>
	@param predicate (T) -> boolean
	@return boolean
]=]
function Iter.All<T>(self: Iter<T>, predicate: (T) -> boolean): boolean
	for item: T in self do
		if not predicate(item) then
			return false
		end
	end
	return true
end

--[=[
	Searches for an element of an Iterator that satisfies a predicate.

	`Find()` takes a function that returns `true` or `false`. It applies this function to each element of the Iterator, and if any of them
	return `true`, then `Find()` returns the element. If they all return `false`, it returns `nil`.

	`Find()` is short-circuiting; in other words, it will stop processing as soon as the function returns `true`.

	```lua
	local A = Iter.fromValues({ 1, 2, 3, 4 })

	assert(A:Find(function(x) return x == 2 end) == 2)
	assert(A:Find(function(x) return x == 5 end) == nil)
	```

	@within Iter
	@tag Consumers

	@function Find
	@param self Iter<T>
	@param predicate (T) -> boolean
	@return T?
]=]
function Iter.Find<T>(self: Iter<T>, predicate: (T) -> boolean): T?
	for item: T in self do
		if predicate(item) then
			return item
		end
	end
	return nil
end

--[=[
	Searches for an element in an Iterator, returning its index.

	`Position()` takes a function that returns `true` or `false`. It applies this function to each element of the Iterator, and if one
	of them returns `true`, then `Position()` returns the index. If all of them return `false`, it returns `nil`.

	`Position()` is short-circuiting; in other words, it will stop processing as soon as it finds a `true`.

	@within Iter
	@tag Consumers

	@function Position
	@param self Iter<T>
	@param predicate (T) -> boolean
	@return number?
]=]
function Iter.Position<T>(self: Iter<T>, predicate: (T) -> boolean): number?
	local Index = 1
	for item: T in self do
		if predicate(item) then
			return Index
		end
		Index += 1
	end
	return nil
end

--[=[
	Consumes the Iterator, counting the number of iterations and returning it.

	```lua
	local A = Iter.fromValues({ 1, 2, 3 })
	assert(A:Count() == 3)

	local B = Iter.fromValues({ 1, 2, 3, 4, 5 })
	assert(B:Count() == 5)
	```

	@within Iter
	@tag Consumers

	@function Count
	@param self Iter<T>
	@return number
]=]
function Iter.Count<T>(self: Iter<T>): number
	local Count = 0
	for _ in self do
		Count += 1
	end
	return Count
end

--[=[
	
	Transforms an Iterator into a collection.

	In other words, this function `collects` all the elements of the Iterator, and returns them in a `table`.
	
	```lua
	local A = Iter.fromValues({ 1, 2, 3 })
	local Doubled = A:Map(function(x: number)
		return x * 2
	end):Collect()

	assert(Doubled[1] == 2)
	assert(Doubled[2] == 4)
	assert(Doubled[3] == 6)
	```

	@within Iter
	@tag Consumers

	@function Collect
	@param self Iter<T>
	@return { T }
]=]
function Iter.Collect<T>(self: Iter<T>): { T }
	local Size = 0
	if self.SizeHint then
		local Min, Max = self.SizeHint()
		Size = Max or Min
	end

	local Result = table.create(Size)
	for item: T in self do
		table.insert(Result, item)
	end
	return Result
end

--[=[
	Converts an Iterator of pairs into a pair of tables.

	`Unzip()` consumes an entire Iterator of pairs, producing two collections: one from the left elements of the pairs, and one from
	the right elements.

	This function is, in some sense, the opposite of `Zip()`.

	```lua
	local FirstIter = Iter.fromValues({ 1, 2, 3, 4 })
	local SecondIter = Iter.fromValues({ 5, 6, 7, 8 })
	
	-- { First = 1, Second = 5 }, { First = 2, Second = 6 } ...
	local Zipped = FirstIter:Zip(SecondIter)

	-- FirstIterValues = { 1, 2, 3, 4 }
	-- SecondIterValues = { 5, 6, 7, 8 }
	local FirstIterValues, SecondIterValues = Zipped:Unzip()
	```

	@within Iter
	@tag Consumers

	@function Unzip
	@param self Iter<Pair<A, B>>
	@return { A }
	@return { B }
]=]
function Iter.Unzip<A, B>(self: Iter<Pair<A, B>>): ({ A }, { B })
	local Size = 0
	if self.SizeHint then
		local Min, Max = self.SizeHint()
		Size = Max or Min
	end
	local First = table.create(Size)
	local Second = table.create(Size)

	for pair: Pair<A, B> in self do
		table.insert(First, pair.First)
		table.insert(Second, pair.Second)
	end
	return First, Second
end

return Module
