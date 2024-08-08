type LexerState = {
	cursor: number,
	
	source: string,
	tokens: {LexerToken},
	
	[any]: any
}

type LexerToken = {
	Content: string,
	Types: {string},
	
	HasType: (self: LexerToken, type: string) -> boolean,
	AddType: (self: LexerToken, type: string) -> nil,
}

type TokenPattern = {
	Type: string,
	Pattern: string
}

type ThemeColor = {
	Type: string,
	Color: Color3,
	
	Italic: boolean?,
	Bold: boolean?
}

export type Theme = {ThemeColor}
export type LexerCallback = (char: "__LEXERSTATEINIT"|string, state: {}) -> {LexerToken}

local Token = {}
Token.__type = 'Token'
Token.__index = Token

local Lexer = {} ---@class Lexer
Lexer.Token = Token
Lexer.Presets = {
	JSON = function(char: string, state: LexerState)
		if char == '__LEXERSTATEINIT' then
			state.patterns = {
				{Type = 'string', Pattern = '"[^"]*"'},
				{Type = 'constructor', Pattern = '(%w+)%([^)]*%)'}, -- [vec3(1, 1, 1), rgb(255, 255, 255)]
				
				{Type = 'keyword', Pattern = 'true'},
				{Type = 'keyword', Pattern = 'false'},
				{Type = 'keyword', Pattern = 'null'},
				
				{Type = 'number', Pattern = '0b[01]+'}, -- [0b1010, 0b0111]
				{Type = 'number', Pattern = '0x%x+'}, -- [0xFF, 0x1AB]
				{Type = 'number', Pattern = '%d*%.%d+'}, -- [1.54, .03]
				{Type = 'number', Pattern = '%d+e%-?%d+'}, -- [1e4, 10e5]
				{Type = 'number', Pattern = '%d+'}, -- [132, 10032]
				
				{Type = 'parameter', Pattern = '%(([^)]+)%)'},
				
				{Type = 'assignment', Pattern = ':'},
				{Type = 'enum', Pattern = 'Enum%.%w+%.%w+'},
				{Type = 'operator', Pattern = '[{}%(%)%[%]]+'}
			} :: {TokenPattern}
			
			state.process = function(source: string, cursor: number)
				local tokens, newCursor = Lexer:GetTokensStep(source, cursor, state.patterns)
				
				for index, token in ipairs(tokens) do
					if token:HasType('assignment') then
						local lastToken = tokens[index - 1] or state.tokens[#state.tokens]
					
						if not lastToken or not lastToken:HasType('string') then
							continue
						end
						
						lastToken:AddType('index')
					elseif token:HasType('keyword') then
						if token.Content == 'null' then
							token:AddType('null')
						end
					end
				end
				
				return tokens, newCursor
			end
			
			return
		end
		
		local tokens, newCursor = state.process(state.source, state.cursor)
		
		state.cursor = newCursor
		
		return tokens
	end,
	Lua = function(char: string, state: LexerState)
		if char == '__LEXERSTATEINIT' then
			state.keywords = {
				["and"] = "keyword",
				["break"] = "keyword",
				["continue"] = "keyword",
				["do"] = "keyword",
				["else"] = "keyword",
				["elseif"] = "keyword",
				["end"] = "keyword",
				["export"] = "keyword",
				["false"] = "keyword",
				["for"] = "keyword",
				["function"] = "keyword",
				["if"] = "keyword",
				["in"] = "keyword",
				["local"] = "keyword",
				["nil"] = "keyword",
				["not"] = "keyword",
				["or"] = "keyword",
				["repeat"] = "keyword",
				["return"] = "keyword",
				["self"] = "keyword",
				["then"] = "keyword",
				["true"] = "keyword",
				["type"] = "keyword",
				["typeof"] = "keyword",
				["until"] = "keyword",
				["while"] = "keyword",
			}
			
			state.patterns = {
				{Type = 'string', Pattern = '"[^"]*"'},
				{Type = 'string', Pattern = "'[^']*'"}, -- string alt
				
				{Type = 'number', Pattern = '%d+e%-?%d+'}, -- [1e4, 10e-5]
				{Type = 'number', Pattern = '0x%x+'}, -- [0xFF, 0x1AB]
				
				{Type = 'method', Pattern = '([%a_][%w_]*)%([^%)]*%)?'},
				{Type = 'var', Pattern = '[%a_][%w_]*'},
				
				{Type = 'number', Pattern = '0b[01]+'}, -- [0b1010, 0b0111]
				{Type = 'number', Pattern = '%d*%.%d+'}, -- [1.54, .03]
				{Type = 'number', Pattern = '%d+'}, -- [132, 10032]
				
				{Type = 'operator', Pattern = '[%+%-%*/%^%%#%(%)%[%]{}=<>,.:;]+'},
			} :: {TokenPattern}
			
			state.process = function(source: string, cursor: number)
				return Lexer:GetTokensStep(source, cursor, state.patterns)
			end
			
			return
		end
		
		local tokens, newCursor = state.process(state.source, state.cursor)
		
		for _, token in ipairs(tokens) do
			if token:HasType('var') then
				if token.Content:match('^[%u_]+$') then
					token:AddType('constant')
				end
			end
			
			if state.keywords[token.Content] then
				token:AddType('keyword')
			end
		end
		
		state.cursor = newCursor
		
		return tokens
	end
}

function Lexer:GetTokensStep(source: string, cursor: number, patterns: {TokenPattern}): {LexerToken}
	table.insert(patterns, {Type = 'whitespace', Pattern = '^%s+'}) -- combine whitespaces into single tokens so they don't take up so much space
	table.insert(patterns, {Type = 'ind', Pattern = '^.'}) -- mainly so it doesnt just crash when theres no matching patterns
	
	local tokens = {}
	
	for _, tokenPattern in ipairs(patterns) do
		local text = string.match(source, tokenPattern.Pattern, cursor)
		
		if not text then
			continue
		end
		
		local start, finish = string.find(source, text, cursor, true)
		
		if not start or not finish then
			continue
		end
		
		local skippedContent = string.sub(source, cursor, start - 1)
		
		if skippedContent:len() > 0 then -- get potentially skipped tokens
			local subCursor = 0
			
			while subCursor <= #skippedContent do
				local skippedTokens, newCursor = Lexer:GetTokensStep(skippedContent, subCursor, patterns)
				
				subCursor = newCursor
				
				for _, token in ipairs(skippedTokens) do
					table.insert(tokens, token)
				end
			end
		end
		
		cursor = finish + 1 -- move cursor
		
		table.insert(tokens, Token.new(string.sub(source, start, finish), {tokenPattern.Type}))
		
		break
	end
	
	return tokens, cursor
end

function Lexer:Tokenize(source: string, lexerCallback: LexerCallback): {LexerToken}
	local state = {
		source = source,
		
		cursor = 1,
		tokens = {},
	}
	
	lexerCallback('__LEXERSTATEINIT', state)
	
	local size = source:len()
	
	while state.cursor <= size do
		local char = source:sub(state.cursor, state.cursor)
		local tokenData = lexerCallback(char, state)
		
		if tokenData then
			for _, token in ipairs(tokenData) do
				table.insert(state.tokens, token)
			end
		end
	end
	
	local combined = Lexer:CombineTokens(state.tokens)
	
	return combined
end

function Lexer:CombineTokens(tokens: {LexerToken})
	local combinedTokens = {}
	
	local cursor = 1
	
	while cursor <= #tokens do
		local baseToken = tokens[cursor]
		local content = baseToken.Content
		
		repeat
			local otherToken = tokens[cursor + 1]
			
			if baseToken == otherToken then
				content ..= otherToken.Content
			end
			
			cursor += 1
		until baseToken ~= otherToken
		
		table.insert(combinedTokens, Token.new(content, baseToken.Types))
	end
	
	return combinedTokens
end

-- reconstructing text

local function sanitizeText(text: string)
	local sanitized = text:gsub('[<>&"\']', {
		['<'] = '&lt;',
		['>'] = '&gt;',
		['&'] = '&amp;',
		['"'] = '&quot;',
		['\''] = '&apos;'
	})
	
	return sanitized
end

function Lexer:StringTokens(tokens: {LexerToken}, callback: (LexerToken) -> string)
	local output = ""
	
	for _, token in ipairs(tokens) do
		local str = token.Content
		
		if callback then
			str = callback(token) or str
		end
		
		output ..= str
	end
	
	return output
end

function Lexer:ColorTokens(tokens: {LexerToken}, theme: Theme)
	return Lexer:StringTokens(tokens, function(token)
		for _, colorData in ipairs(theme) do
			if not token:HasType(colorData.Type) then
				continue -- skip
			end
			
			local output = `<font color="#{colorData.Color:ToHex()}">{sanitizeText(token.Content)}</font>`
			
			if colorData.Bold then
				output = `<b>{output}</b>`
			end
			
			if colorData.Italic then
				output = `<i>{output}</i>`
			end
			
			return output
		end
		
		return sanitizeText(token.Content)
	end)
end

-- token stuff

function Token:__eq(other)
	if type(other) ~= "table" then
		return false
	end
	
	if other.__type ~= self.__type then
		return false
	end
	
	for _, tokenType in ipairs(self.Types) do
		if not other:HasType(tokenType) then
			return false
		end
	end
	
	for _, otherType in ipairs(other.Types) do
		if not self:HasType(otherType) then
			return false
		end
	end
	
	return true
end

function Token.new(content: string, types: {string})
	local newToken = setmetatable({
		Content = content,
		Types = types
	}, Token)
	
	return newToken
end

function Token:AddType(tokenType: string)
	if self:HasType(tokenType) then
		return
	end
	
	table.insert(self.Types, tokenType)
end

function Token:HasType(tokenType: string)
	return table.find(self.Types, tokenType) ~= nil
end

return Lexer