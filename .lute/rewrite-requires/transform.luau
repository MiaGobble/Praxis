const syntax = require("@std/syntax")
const printer = require("@std/syntax/printer")
const query = require("@std/syntax/query")
const utils = require("@std/syntax/utils")

const transform = {}

function transform.stringRequires(source: string, replace: (syntax.AstExprConstantString) -> (string?)): (boolean, string)
	const ok, parseResult: string | syntax.ParseResult = pcall(syntax.parse, source)
	if not ok then
		return false, parseResult :: string
	end

	local _: typeof(assert(type(parseResult) ~= "string"))
	const replacements = query.findAllFromRoot(parseResult, utils.isRequireCall)
		:filter(function(call: syntax.AstExprCall): (boolean)
			const firstArg = call.arguments[1]
			return firstArg and utils.isExprConstantString(firstArg.node) ~= nil
		end)
		:map(function(call: syntax.AstExprCall): (syntax.AstNode)
			return call.arguments[1].node
		end)
		:replace(replace)

	const transformedSource = printer.printFile(parseResult, replacements)
	return true, transformedSource
end

return transform