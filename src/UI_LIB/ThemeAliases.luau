local aliases = {
	Black = "Background",
	Main = "Accent",
	Header = "Sidebar",
	Bottom = "Sidebar",
	Line = "Border",
	Scroll = "TextMuted",
	TabBg = "Surface",
	TabBgActive = "SurfaceActive",
	TextDim = "TextSecondary",
	TextStrong = "Text",
	Section = "Surface",
	Panel = "Sidebar",
	Control = "SurfaceActive",
	ControlAlt = "Surface",
	ControlHover = "SurfaceHover",
	AccentSurface = "SurfaceActive",
	TitleStroke = "Border",
	Shadow = "Background",
	BackgroundTransparency = "WindowTransparency",
	HeaderTransparency = "PanelTransparency",
	BottomTransparency = "PanelTransparency",
	SectionTransparency = "PanelTransparency",
	ControlTransparency = "PanelTransparency",
	AccentTransparency = "PanelTransparency",
}
local ThemeAliases = {}
function ThemeAliases.token(token)
	return aliases[token] or token
end
function ThemeAliases.patch(values)
	local result = {}
	for token, value in pairs(values) do
		result[ThemeAliases.token(token)] = value
	end
	return result
end
return ThemeAliases
