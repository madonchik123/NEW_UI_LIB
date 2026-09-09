return function(require)
	local Text = {}

	local acronyms = {
		ESP = true,
		UI = true,
		NPC = true,
		FPS = true,
		AFK = true,
		ID = true,
		RGB = true,
		HSV = true,
		API = true,
		VIP = true,
		HP = true,
		XP = true,
		DPS = true,
		FOV = true,
		CPU = true,
		GPU = true,
		RAM = true,
		HTTP = true,
		HTTPS = true,
		URL = true,
		UUID = true,
		PVP = true,
		PVE = true,
	}

	function Text.display(value)
		local text = tostring(value or "")
		if text:find("%l") or text:find("@", 1, true) or text:find("://", 1, true) or text:match("^#%x+$") then
			return text
		end
		local normalized = text:gsub("[%w_][%w_']*", function(word)
			if acronyms[word] or word:find("%d") or word:find("_", 1, true) then
				return word
			end
			return word:sub(1, 1) .. word:sub(2):lower()
		end)
		return normalized
	end

	return Text
end
