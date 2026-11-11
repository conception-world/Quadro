--!strict
local Settings = require("../Studio/Settings")

export type Request = { Url: string, Method: string, Headers: { [string]: string } }
export type Response = { StatusCode: number, Body: string }
export type Transport = (request: Request) -> Response
export type Config = { token: string, port: number }
export type Result = { ok: true, data: any } | { ok: false, reason: string }

local Client = {}

local DENIED_MARKERS = { "not enabled", "permission", "not allowed", "trust" }

local function httpTransport(request: Request): Response
	local response = game:GetService("HttpService"):RequestAsync({
		Url = request.Url,
		Method = request.Method,
		Headers = request.Headers,
	})
	return { StatusCode = response.StatusCode, Body = response.Body }
end

local transport: Transport = httpTransport

function Client.setTransport(fn: Transport)
	transport = fn
end

function Client.reset()
	transport = httpTransport
end

function Client.reasonFor(message: string): string
	local lowered = string.lower(message)
	if string.find(lowered, "http", 1, true) or string.find(lowered, "request", 1, true) then
		for _, marker in DENIED_MARKERS do
			if string.find(lowered, marker, 1, true) then
				return "http_denied"
			end
		end
	end
	return "offline"
end

function Client.interpret(response: Response): Result
	if response.StatusCode == 401 then
		return { ok = false, reason = "unauthorized" }
	end
	if response.StatusCode < 200 or response.StatusCode >= 300 then
		return { ok = false, reason = "bad_response" }
	end
	local decoded, data = pcall(Settings.codec.decode, response.Body)
	if not decoded or type(data) ~= "table" then
		return { ok = false, reason = "bad_response" }
	end
	return { ok = true, data = data }
end

function Client.get(config: Config, path: string): Result
	local sent, response = pcall(transport, {
		Url = string.format("http://127.0.0.1:%d%s", config.port, path),
		Method = "GET",
		Headers = { ["X-Quadro-Token"] = config.token },
	})
	if not sent then
		return { ok = false, reason = Client.reasonFor(tostring(response)) }
	end
	return Client.interpret(response)
end

function Client.health(config: Config): Result
	return Client.get(config, "/health")
end

function Client.pushes(config: Config): Result
	return Client.get(config, "/pushes")
end

function Client.encode(text: string): string
	return game:GetService("HttpService"):UrlEncode(text)
end

function Client.push(config: Config, id: string): Result
	return Client.get(config, "/push/" .. Client.encode(id))
end

export type Push = { id: string, name: string, rootId: string, time: number, images: number, done: number, pending: number, failed: number }

function Client.parsePushes(data: any): { Push }
	local out: { Push } = {}
	for _, raw in data do
		if type(raw) == "table" and type(raw.id) == "string" and type(raw.name) == "string" then
			table.insert(out, {
				id = raw.id,
				name = raw.name,
				rootId = if type(raw.rootId) == "string" then raw.rootId else "",
				time = if type(raw.time) == "number" then raw.time else 0,
				images = if type(raw.images) == "number" then raw.images else 0,
				done = if type(raw.done) == "number" then raw.done else 0,
				pending = if type(raw.pending) == "number" then raw.pending else 0,
				failed = if type(raw.failed) == "number" then raw.failed else 0,
			})
		end
	end
	return out
end

function Client.clock(milliseconds: number): string
	return os.date("%H:%M", math.floor(milliseconds / 1000))
end

return Client
