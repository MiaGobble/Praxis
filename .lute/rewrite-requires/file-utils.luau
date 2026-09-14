const fs = require("@std/fs")
const path = require("@std/path")
const colorOutput = require("./color-output")

const CREATE_DIR_OPTIONS: fs.CreateDirectoryOptions = {makeParents = true}

const fileUtils = {}

local dryRun = false
local continueOnFail = false
local verbose = false

--[[
	Sets dry-run mode.
]]
function fileUtils.setDryRun(value: boolean?): ()
	if value then
		colorOutput.info("Executing in dry-run mode, files won't be written.")
	end

	dryRun = value
end

--[[
	Sets continue on non-fatal failure.
]]
function fileUtils.setContinueOnFail(value: boolean?): ()
	continueOnFail = value
end

--[[
	Sets verbose output mode.
]]
function fileUtils.setVerbose(value: boolean?): ()
	verbose = value
end

--[[
	Returns a `boolean` indicating if the two paths point at the same location.
]]
const function comparePaths(a: path.Pathlike, b: path.Pathlike): (boolean)
	return path.format(path.resolve(a)) == path.format(path.resolve(b))
end

fileUtils.comparePaths = comparePaths

--[[
	Creates a directory at `dirPath` if it doesn't exist, and creating any missing parent directories as well.
]]
const function makeDir(dirPath: path.Pathlike): ()
	if dryRun then return end

	if fs.exists(dirPath) then
		if verbose then colorOutput.verbose(`Directory '{dirPath}' already exists`) end
	else
		if verbose then colorOutput.verbose(`Making directory '{dirPath}'`) end
		fs.createDirectory(dirPath, CREATE_DIR_OPTIONS)
	end
end

fileUtils.makeDir = makeDir

--[[
	Writes `contents` to the file at `filePath`, replacing any existing contents.

	Creates any missing directories and the file as well.
]]
const function writeFile(filePath: path.Pathlike, contents: string): ()
	if dryRun then return end

	if fs.exists(filePath) then
		if verbose then colorOutput.verbose(`File '{filePath}' exists, verifying it's a file.`) end
		if fs.type(filePath) ~= "file" then
			colorOutput.fail(`{filePath} is not a file`, continueOnFail)
			return
		end
	else
		if verbose then colorOutput.verbose(`File '{filePath}' doesn't exist, ensuring directory.`) end
		makeDir(path.dirname(filePath))
	end

	fs.writeStringToFile(filePath, contents)
end

fileUtils.writeFile = writeFile

--[[
	Computes the destination path for a file, mirroring its location relative to `srcRoot` but rooted at `destRoot` instead.

	Returns `nil` if `filePath` doesn't lie inside `srcRoot`, to prevent writes from escaping the intended output directory.
]]
const function relativeDestPath(filePath: path.Pathlike, srcRoot: path.Pathlike, destRoot: path.Pathlike): (path.Path?)
	const relative = path.relative(path.resolve(srcRoot), path.resolve(filePath))
	
	-- Prevent escapes from writing outside intended output directory
	if relative.parts[1] == ".." then
		colorOutput.fail(`'{filePath}' is not inside input root`, continueOnFail)
		return nil
	end

	return path.join(destRoot, relative)
end

fileUtils.relativeDestPath = relativeDestPath

const function copyFile(src: path.Pathlike, dest: path.Pathlike): ()
	if dryRun then return end

	const ok, err = pcall(fs.copy, src, dest)
	if not ok then colorOutput.fatal(`Failed to copy file from '{src}' to '{dest}':\n{err}`) end
end

--[[
	Copies the file or directory at `src` to `dest`, optionally copying recursively.
]]
const function copyPath(src: path.Pathlike, dest: path.Pathlike, recursive: boolean?): ()
	if not fs.exists(src) then
		colorOutput.fail(`Attempt to copy non-existent path '{src}'`, continueOnFail)
		return
	end

	-- Do nothing if dry running or if src and dest are the same (e.g. from transform-in-place).
	if dryRun or comparePaths(src, dest) then return end

	if fs.type(src) == "dir" then
		if verbose then colorOutput.verbose(`Copying directory '{src}'`) end
		makeDir(path.dirname(dest))
		
		const it = fs.walk(src, {recursive = recursive})
		local filePath = it()
		while filePath do
			if verbose then colorOutput.verbose(`    Copy {filePath}`) end

			const resolvedDest = relativeDestPath(filePath, src, dest)
			if resolvedDest then
				if fs.type(filePath) == "dir" then
					makeDir(path.dirname(resolvedDest))
				else
					copyFile(filePath, resolvedDest)
				end
			end

			filePath = it()
		end
	else
		if verbose then colorOutput.verbose(`Copying file '{src}'`) end
		copyFile(src, dest)
	end
end

fileUtils.copyPath = copyPath

const function sanitizeFindSearches(searches: {read path.Pathlike}): ({path.Pathlike})
	const sanitizedSearches: {path.Pathlike} = {}
	for i, search in searches do
		if path.isAbsolute(search) then
			colorOutput.warn(`[findFirstUp]: Search #{i} '{search}' is an absolute path, ignoring it.`)
			continue
		end

		table.insert(sanitizedSearches, search)
	end

	return sanitizedSearches
end

const function findFileInDir(dir: path.Pathlike, searches: {read path.Pathlike}): (path.Pathlike?)
	for _, search in searches do
		const filePath = path.join(dir, search)
		if fs.exists(filePath) then
			return filePath
		end
	end

	return nil
end

--[[
	Finds the first file or directory matching any relative path of the given `searches`, walking up from the given directory until one is found, and returns it.

	If `stop` is specified, the search will end when it is reached, otherwise ends when the drive root is reached.
]]
const function findFirstUp(dir: path.Pathlike, searches: {read path.Pathlike}, stop: path.Pathlike?): (path.Pathlike?)
	const sanitizedSearches = sanitizeFindSearches(searches)

	local walkingDir: path.Pathlike = dir
	while walkingDir do
		const found = findFileInDir(walkingDir, sanitizedSearches)
		if found then return found end

		const nextDir = path.join(walkingDir, "..")

		-- Stop if we've reached the drive root.
		if not fs.exists(nextDir) then break end
		
		-- Stop if we've reached the user-defined root.
		if stop and path.relative(stop, nextDir).parts[1] == ".." then break end

		walkingDir = nextDir
	end

	return nil
end

fileUtils.findFirstUp = findFirstUp

-- If glob matching is needed, Lute has a battery for it:
-- https://github.com/luau-lang/lute/blob/primary/batteries/glob.luau

const function findRecursive(dir: path.Pathlike, searches: {read path.Pathlike}): (path.Pathlike?)
	do
		const found = findFileInDir(dir, searches)
		if found then return found end
	end

	for _, entry in fs.listDirectory(dir) do
		if entry.type ~= "dir" then continue end

		const found = findRecursive(path.join(dir, entry.name), searches)
		if found then return found end
	end

	return nil
end

--[[
	Finds the first file or directory matching any relative path of the given `searches`, optionally searching recursively if `options.recursive` is set.
]]
const function findFirstDown(dir: path.Pathlike, searches: {read path.Pathlike}, options: {recursive: boolean?}?): (path.Pathlike?)
	const sanitizedSearches = sanitizeFindSearches(searches)

	if options and options.recursive then
		return findRecursive(dir, sanitizedSearches)
	else
		return findFileInDir(dir, sanitizedSearches)
	end
end

fileUtils.findFirstDown = findFirstDown

--[[
	Returns a boolean indicating if the given path is a Luau init script.

	`true` if the basename is `init.luau` or `init.lua`, `false` otherwise.
]]
const function isInitScript(scriptPath: path.Pathlike): (boolean)
	const baseName = path.basename(scriptPath)
	return baseName == "init.luau" or baseName == "init.lua"
end

fileUtils.isInitScript = isInitScript

--[[
	Returns the script's directory (its typical working directory), or nil if the given path isn't a script file.
]]
const function scriptDirectory(scriptPath: path.Pathlike): (path.Path?)
	const extName = path.extname(scriptPath)
	if extName ~= ".luau" and extName ~= ".lua" then
		return nil
	end

	const dirName = path.dirname(scriptPath)
	return path.normalize(
		if isInitScript(scriptPath) then path.join(dirName, "..") else dirName
	)
end

fileUtils.scriptDirectory = scriptDirectory

return fileUtils