--[=[
    @class Child

    Finds children of an instance by path. This is useful for finding deeply nested children without having to write a long chain of `:FindFirstChild()` or `:WaitForChild()` calls.
]=]

local Child = {}

--[=[
    @param root Instance -- The root instance to start searching from.
    @param path {string} -- The path to the child, as an array of strings.
    @return Instance? -- The child instance, or nil if it doesn't exist.

    Seeks a child or descendant from a path, returning nil if it doesn't exist.
]=]

function Child.FromPathOptional(root: Instance, path: { string }): Instance?
	local Object = root

	for _, name in path do
		Object = Object:FindFirstChild(name)

		if not Object then
			return nil
		end
	end

	return Object
end

--[=[
    @param root Instance -- The root instance to start searching from.
    @param path {string} -- The path to the child, as an array of strings.
    @param timeoutAfter number? -- The time in seconds to wait before giving up. Defaults to infinite.
    @return Instance? -- The child instance, or nil if it doesn't exist.

    Seeks a child or descendant from a path, waiting for it to exist if it doesn't. Returns nil if the timeout is reached.
]=]

function Child.FromPathAsync(root: Instance, path: { string }, timeoutAfter: number?): Instance?
	local Object = root
	local Start = os.clock()

	for _, name in path do
		local Discovery = if timeoutAfter
			then Object:WaitForChild(name, timeoutAfter - (os.clock() - Start))
			else Object:WaitForChild(name)

		if not Discovery then
			return nil
		end

		Object = Discovery
	end

	return Object
end

return Child
