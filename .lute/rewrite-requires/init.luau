const fs = require("@std/fs")
const path = require("@std/path")
const process = require("@std/process")

const ansi = require("@self/ansi-format")
const transform = require("@self/transform")
const fileUtils = require("@self/file-utils")
const colorOutput = require("@self/color-output")

const DIR_WALK_RECURSIVE: fs.WalkOptions = {recursive = true}

const PATH_DIR_PATTERN = "[:%w_%.%-%s/\\]+"
const BASIC_ALIAS_PATTERN = "[%W_%.%-%S]+"

-- CLI --
const HELP_MESSAGE = `\z
	Usage: {ansi.colorForeground("lute [run] rewrite-requires [options...]", "Cyan")}\z
	\n\z
	\nOptions:\z
	\n    -h, --help                      Display this help message and exit.\z
	\n    -i, --input <path...>           The paths or files to process, separated with semicolon (;).\z
	\n    -o, --output <path>             The directory to output to.\z
	\n                                    If not specified, files are overwritten in place.\z
	\n    -a, --aliases <aliases...>      Aliases and the paths to resolve them to, in the form alias=path.\z
	\n                                    Separate aliases with semicolon (;).\z
	\n                                    {ansi.italic("Example: -a pkg=roblox_packages/")}\z
	\n    -r, --retarget <aliases...>     Enables require retargeting on the specified aliases, in the form alias=path.\z
	\n                                    Resolves target paths by relative location from the nearest matching file.\z
	\n                                    Supports both absolute (prefix path with 'abs:') and relative ('rel:') targets, defaulting to relative.\z
	\n                                    Separate aliases with semicolon (;).\z
	\n                                    {ansi.italic("Example: -r pkg=pesde.toml")}\z
	\n    -v, --verbose                   Verbose debug message output.\z
	\n    --continue                      Continue processing on non-fatal errors.\z
	\n    --dry-run                       Run the process without making changes to files.\z
	\n                                    Use with --verbose to review changes.\z
`

const function unhandled(a: never): ()
	print(ansi.colorForeground(`Unrecognized argument: {a}`, "Red"))
	process.exit(2)
end

type Aliases = { [string]: string? }
type Retargets = {
	[string]: {to: string, absolute: boolean}?
}

type CLIOptions = {
	help: true?,
	inputs: {string},
	output: string?,
	aliases: Aliases,
	retargets: Retargets,
	dryRun: true?,
	continueOnFail: true?,
	verbose: true?,
}

type CLIArguments =
	| "-h" | "--help"
	| "-i" | "--input"
	| "-o" | "--output"
	| "-a" | "--aliases"
	| "-r" | "--retarget"
	| "-v" | "--verbose"
	| "--dry-run"
	| "--continue"

const function parseArgs(args: {string}): (CLIOptions)
	const inputs: index<CLIOptions, "inputs"> = {}
	const aliases: index<CLIOptions, "aliases"> = {}
	const retargets: index<CLIOptions, "retargets"> = {}
	const opts: CLIOptions = {
		inputs = inputs,
		aliases = aliases,
		retargets = retargets,
	}

	const numArgs = #args
	local i = 2 -- start at 2, as index 1 is the script
	while i <= numArgs do
		const arg = args[i] :: CLIArguments
		if arg == "-h" or arg == "--help" then
			opts.help = true
		elseif arg == "-i" or arg == "--input" then
			i += 1

			for path in string.gmatch(args[i], `(%a?:?{PATH_DIR_PATTERN});?`) do
				table.insert(inputs, path)
			end
		elseif arg == "-o" or arg == "--output" then
			i += 1

			opts.output = args[i]
		elseif arg == "-a" or arg == "--aliases" then
			i += 1

			for alias, value in string.gmatch(args[i], `@?({BASIC_ALIAS_PATTERN})=(@?{PATH_DIR_PATTERN});?`) do
				aliases[alias] = value
			end
		elseif arg == "-r" or arg == "--retarget" then
			i += 1

			for alias, target in string.gmatch(args[i], `@?({BASIC_ALIAS_PATTERN})=({PATH_DIR_PATTERN});?`) do
				const modeStr = string.match(target, "^%a+:")
				const absMode: boolean? =
					if modeStr == "abs:" then true
					elseif modeStr == "rel:" then false
					else nil

				-- Remove the mode prefix from the target
				if modeStr and absMode ~= nil then
					target = string.sub(target, #modeStr + 1)
				end

				retargets[alias] = {
					to = target,
					absolute = absMode == true
				}
			end
		elseif arg == "-v" or arg == "--verbose" then
			opts.verbose = true
		elseif arg == "--dry-run" then
			opts.dryRun = true
		elseif arg == "--continue" then
			opts.continueOnFail = true
		else
			unhandled(arg)
		end

		i += 1
	end

	return opts
end

-- Arguments --
const opts = parseArgs(process.args)
const inputs = opts.inputs
const output = opts.output
const aliases = opts.aliases
const retargets = opts.retargets
const dryRun = opts.dryRun
const continueOnFail = opts.continueOnFail
const verbose = opts.verbose

if
	opts.help
	or not (inputs[1] or output or next(aliases) or next(retargets))
then
	print(HELP_MESSAGE)
	process.exit(0)
end

if not inputs[1] then
	colorOutput.fatal("Missing option: --input <path>", 2)
end

fileUtils.setDryRun(dryRun)
fileUtils.setContinueOnFail(continueOnFail)
--fileUtils.setVerbose(verbose)

-- Processing --
const startTime = os.clock()
local scriptCount, requireCount = 0, 0

-- Ensure output path is valid (must be a directory for multi-inputs), or create the output directory.
if output then
	print(`Specified output path: '{output}'`)

	if fs.exists(output) then
		if #inputs > 1 and fs.type(output) ~= "dir" then
			colorOutput.fatal(
				`Invalid option: --output '{output}'\z
				\n    Specified output must be a directory when processing multiple inputs.`
			)
		end
	else
		const ok, err = pcall(fileUtils.makeDir, output)
		if not ok then colorOutput.fatal(`Failed to create output directory '{output}':\n{err}`) end
	end
else
	print("No output path specified, writing in-rlace.")
end

-- Cache of found nearest retargets keyed by directory paths.
const packageRootCache: {[string]: path.Path?} = {}

const function resolvePackageRoot(initMode: boolean, fileDir: path.Pathlike, scriptDir: path.Pathlike, search: path.Pathlike): (path.Path?)
	const fileDirStr = path.format(fileDir)
	const cached = packageRootCache[fileDirStr]
	if cached then return cached end

	const searches = {search}

	-- Special case for init scripts, also search immediate children (@self requires).
	local found: path.Pathlike? = initMode
		and fileUtils.findFirstDown(scriptDir, searches)
		or fileUtils.findFirstUp(fileDir, searches)

	if not found then return nil end

	const relative = path.normalize(path.relative(fileDir, path.dirname(found)))
	packageRootCache[fileDirStr] = relative

	-- Cache every path that will also use this root
	local cachePath = fileDirStr
	for _, part in relative.parts do
		cachePath ..= "/" .. part
		packageRootCache[cachePath] = relative
	end

	return relative
end

--[[
	Separates the alias prefix from a require-by-string target from the rest of the target.
]]
const function separateAlias(target: string): (string?, string)
	const alias, rest = string.match(target, "^@([%w_%-]+)/(.+)$")
	if alias then
		return alias, rest :: string
	end

	-- No match, relative path and no alias.
	return nil, target
end

const function processFile(filePath: path.Pathlike, dest: path.Pathlike, aliases: Aliases, retargets: Retargets): ()
	do
		const fileExt = path.extname(filePath)

		-- Copy the directly if it's not a .lua(u) file.
		if fileExt ~= ".luau" and fileExt ~= ".lua" then
			fileUtils.copyPath(filePath, dest)
			return
		end
	end

	scriptCount += 1

	if verbose then colorOutput.verbose(`Transforming '{filePath}'`) end

	const openOk, file = pcall(fs.open, filePath, "r+")
	if not openOk then colorOutput.fatal(`Failed to open file '{filePath}':\n{file}`) end

	const readOk, source = pcall(fs.read, file)
	if not readOk then colorOutput.fatal(`Failed to read file '{filePath}':\n{source}`) end
	
	const baseName = path.basename(filePath)
	if not baseName then colorOutput.fatal(`Unexpectedly failed to get basename of '{filePath}'`) end

	const fileDir = path.dirname(filePath)
	const scriptDir = fileUtils.scriptDirectory(filePath) :: path.Path
	const initMode = fileUtils.isInitScript(filePath)

	const transformOk, transformedSource = transform.stringRequires(source, function(target): string?
		const targetText = target.token.text
		const alias, rest = separateAlias(targetText)
		
		-- Skip non-alias targets (nothing to transform)
		if not alias then return nil end
		
		const retarget = retargets[alias]
		const sub = aliases[alias]

		-- Resolve alias and rest to use
		local rAlias: string, rRest: string
		if not sub then
			-- Skip processing if there's no operation defined (no replacement nor retargeting)
			if not retarget then return nil end

			rAlias, rRest = alias, rest
		else
			const subAlias, subRest = separateAlias(sub)
			if subAlias then
				-- `@alias/` substitute
				rAlias, rRest = subAlias, subRest .. rest
			else
				-- Other prefixed or non-rrefixed pattern
				-- Use entire substitution as rRest
				rAlias, rRest = "", sub .. rest
			end
		end

		local replacement: path.Path
		if retarget then
			const to = retarget.to
			const absMode = retarget.absolute
			const redirPath = if absMode
				then path.relative(scriptDir, to)
				else resolvePackageRoot(initMode, fileDir, scriptDir, to)

			if redirPath then
				const parts = redirPath.parts
				const first = parts[1]

				if initMode and not first then -- Child
					replacement = path.normalize(path.join("@self", rRest))
				elseif (initMode or absMode) and first == ".." then
					-- Skip the first .. part
					table.insert(parts, rRest)
					replacement = path.normalize(path.join(table.unpack(parts, 2)))
				else
					replacement = path.normalize(path.join(rAlias, redirPath or "", rRest))
				end
			else
				colorOutput.warn(`Failed to retarget {targetText} to {to} (couldn't find file)`)
				replacement = path.normalize(path.join(rAlias, rRest))
			end
		else
			replacement = path.normalize(path.join(rAlias, rRest))
		end

		local replacementText = string.gsub(path.format(replacement), "\\", "/")

		-- Luau require targets must begin with a prefix, add it back in if it got normalized out,
		-- such as when the require is importing from a directory that is a sibling of the script.
		do
			const firstChar = string.sub(replacementText, 1, 1)
			if firstChar ~= "@" and firstChar ~= "." then
				replacementText = "./" .. replacementText
			end
		end

		-- Return nil to leave original completely untouched
		if replacementText == targetText then return nil end

		requireCount += 1
		if verbose then colorOutput.verbose(`    {ansi.underline(targetText)} → {ansi.underline(replacementText)}`) end

		return `"{replacementText}"`
	end)

	if not transformOk then
		colorOutput.fail(`Failed to transform file '{filePath}':\n{transformedSource}`, continueOnFail)
		return
	end

	-- Write in place if filePath and dest are the same, or create + write the file in output.
	if fileUtils.comparePaths(filePath, dest) then
		if not dryRun then
			const writeOk, err = pcall(fs.write, file, transformedSource)
			if not writeOk then colorOutput.fatal(`Failed to write file '{filePath}':\n{err}`) end
		end
	else
		fileUtils.writeFile(dest, transformedSource)
	end

	fs.close(file)
end

for _, inputPath in inputs do
	if not fs.exists(inputPath) then
		colorOutput.warn(`Input '{inputPath}' doesn't exist, skipping.`)
		continue
	end

	const destRoot = output or inputPath
	const fileType = fs.type(inputPath)
	if fileType == "file" then
		processFile(inputPath, destRoot, aliases, retargets)
	elseif fileType == "dir" then
		const it = fs.walk(inputPath, DIR_WALK_RECURSIVE)
		local filePath = it()
		while filePath do
			const dest = fileUtils.relativeDestPath(filePath, inputPath, destRoot)
			if not dest then
				colorOutput.fail(`Could not get relative destination path for '{filePath}'`, continueOnFail)
				continue
			end

			processFile(filePath, dest, aliases, retargets)
			filePath = it()
		end
	else
		colorOutput.warn(`Input '{inputPath}' isn't a file or directory, skipping. ({fileType})`)
		continue
	end
end

const endTime = os.clock()

print(`\z
	{ansi.colorForeground(`Completed in {(endTime - startTime) * 1000} ms.`, "Cyan")}\z
	\nProcessed {ansi.colorForeground(tostring(scriptCount), "Green")} script(s), \z
	Rewrote {ansi.colorForeground(tostring(requireCount), "Magenta")} require(s)\z
`)