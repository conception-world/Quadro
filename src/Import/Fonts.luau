--!strict
local Fonts = {}

local FAMILIES: { [string]: string } = {
	["Montserrat"] = "Montserrat",
	["Gotham"] = "GothamSSm",
	["Gotham SSm"] = "GothamSSm",
	["Fredoka One"] = "FredokaOne",
	["Fredoka"] = "FredokaOne",
	["Luckiest Guy"] = "LuckiestGuy",
	["Source Sans Pro"] = "SourceSansPro",
	["Source Sans 3"] = "SourceSansPro",
	["Builder Sans"] = "BuilderSans",
	["Inter"] = "Inter",
	["Roboto"] = "Roboto",
	["Titillium Web"] = "TitilliumWeb",
	["Merriweather"] = "Merriweather",
	["Comic Neue"] = "ComicNeueAngular",
	["Grenze Gotisch"] = "GrenzeGotisch",
}

local WEIGHTS = { "Thin", "ExtraLight", "Light", "Regular", "Medium", "SemiBold", "Bold", "ExtraBold", "Heavy" }

function Fonts.resolve(family: string, weight: number, italic: boolean): { family: string, weight: string, style: string, known: boolean }
	local mapped = FAMILIES[family]
	local safe = if type(weight) == "number" and weight == weight then weight else 400
	local index = math.clamp(math.floor(safe / 100 + 0.5), 1, 9)
	return {
		family = "rbxasset://fonts/families/" .. (mapped or "GothamSSm") .. ".json",
		weight = WEIGHTS[index],
		style = if italic then "Italic" else "Normal",
		known = mapped ~= nil,
	}
end

return Fonts
