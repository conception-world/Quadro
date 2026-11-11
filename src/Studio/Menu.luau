--!strict
local Menu = {}

export type Item = { id: string?, text: string?, separator: boolean? }

local serial = 0

function Menu.show(plugin: Plugin, items: { Item }): string?
	serial += 1
	local prefix = "Quadro_Menu" .. serial
	local created, menu = pcall(function()
		return plugin:CreatePluginMenu(prefix, "Quadro")
	end)
	if not created or not menu then
		warn("[Quadro] menu unavailable: " .. tostring(menu))
		return nil
	end
	local picked: string? = nil
	local idByAction: { [any]: string } = {}
	for _, item in items do
		if item.separator then
			menu:AddSeparator()
		else
			local id = item.id :: string
			local action = menu:AddNewAction(prefix .. "_" .. id, item.text :: string, "")
			idByAction[action] = id
			action.Triggered:Connect(function()
				picked = id
			end)
		end
	end
	local shown, chosen = pcall(function()
		return menu:ShowAsync()
	end)
	if not shown then
		warn("[Quadro] menu: " .. tostring(chosen))
	elseif chosen and idByAction[chosen] then
		picked = idByAction[chosen]
	end
	menu:Destroy()
	return picked
end

return Menu
