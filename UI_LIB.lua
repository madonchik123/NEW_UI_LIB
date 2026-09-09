local function getRequestFunction()
	if type(request) == "function" then
		return request
	end
	if type(http_request) == "function" then
		return http_request
	end
	if type(http) == "table" and type(http.request) == "function" then
		return http.request
	end
	if type(syn) == "table" and type(syn.request) == "function" then
		return syn.request
	end
	if type(fluxus) == "table" and type(fluxus.request) == "function" then
		return fluxus.request
	end
	return nil
end

local function normalizeResponse(response)
	if type(response) == "string" then
		return { StatusCode = 200, Body = response }
	end
	if type(response) ~= "table" then
		return nil
	end
	return {
		StatusCode = tonumber(response.StatusCode or response.Status or response.status_code or response.status) or 0,
		Body = response.Body or response.body or response.ResponseBody,
	}
end

local baseUrl = "https://raw.githubusercontent.com/madonchik123/NEW_UI_LIB/executor"
local allowed = {
	["Account"] = true,
	["Advanced"] = true,
	["Blur"] = true,
	["Compatibility"] = true,
	["Config"] = true,
	["Containers"] = true,
	["Controls"] = true,
	["Core"] = true,
	["GameCatalog"] = true,
	["Icons"] = true,
	["KeyGate"] = true,
	["KeySystem"] = true,
	["LegacyHost"] = true,
	["Motion"] = true,
	["Notifications"] = true,
	["Overview"] = true,
	["Personal"] = true,
	["PlayerESP"] = true,
	["Search"] = true,
	["Storage"] = true,
	["Theme"] = true,
	["ThemeAliases"] = true,
	["Tooltips"] = true,
	["UI_LIB"] = true,
	["UI_LIB_App"] = true,
	["Window"] = true,
}
local requestFunction = getRequestFunction()
local compile = loadstring
assert(type(requestFunction) == "function", "UI_LIB requires the executor request capability.")
assert(type(compile) == "function", "UI_LIB requires the executor loadstring capability.")
local environment = type(getgenv) == "function" and getgenv() or _G
local generation = (tonumber(environment.__UI_LIBLoadGeneration) or 0) + 1
environment.__UI_LIBLoadGeneration = generation
local cache, loading = {}, {}
local function moduleRequire(name)
	assert(allowed[name], "Unknown UI_LIB module: " .. tostring(name))
	if cache[name] ~= nil then
		return cache[name]
	end
	local pending = loading[name]
	if pending then
		assert(pending.Thread ~= coroutine.running(), "Circular UI_LIB module dependency: " .. name)
		while not pending.Done do
			task.wait()
		end
		if pending.Error then
			error(pending.Error, 2)
		end
		return cache[name]
	end
	pending = { Thread = coroutine.running(), Done = false }
	loading[name] = pending
	local ok, result = pcall(function()
		local response =
			normalizeResponse(requestFunction({ Url = baseUrl .. "/modules/" .. name .. ".lua", Method = "GET" }))
		local status = type(response) == "table" and tonumber(response.StatusCode)
		assert(status and status >= 200 and status < 300, "Unable to download UI_LIB module: " .. name)
		assert(
			type(response.Body) == "string" and #response.Body > 0 and #response.Body <= 4194304,
			"Invalid UI_LIB module response: " .. name
		)
		local chunk = compile(response.Body)
		assert(type(chunk) == "function", "Unable to compile UI_LIB module: " .. name)
		local factory = chunk()
		assert(type(factory) == "function", "Invalid UI_LIB module factory: " .. name)
		local value = factory(moduleRequire)
		assert(value ~= nil, "UI_LIB module returned nil: " .. name)
		return value
	end)
	if ok then
		cache[name] = result
	else
		pending.Error = tostring(result)
	end
	pending.Done = true
	loading[name] = nil
	if not ok then
		error(pending.Error, 2)
	end
	return result
end
local Library = moduleRequire("UI_LIB")
assert(environment.__UI_LIBLoadGeneration == generation, "UI_LIB loading was superseded.")
local previous = environment.__UI_LIBLibrary
if previous and previous.Destroy then
	previous:Destroy()
end
assert(environment.__UI_LIBLoadGeneration == generation, "UI_LIB loading was superseded.")
environment.__UI_LIBLibrary = Library
return Library
