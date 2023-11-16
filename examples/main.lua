local skynet = require "skynet"

local function dump(t, prefix)
	for k,v in pairs(t) do
		skynet.error(prefix.."."..k.." = "..tostring(v))
	end
end

skynet.start(function()
	skynet.error("Server[Calculator] start")
	if not skynet.getenv "daemon" then
		local console = skynet.newservice("console")
	end

	local calc = skynet.newservice("calculator", "worker.lua", 4)
	local p = skynet.call(calc, "lua", "login", {pid = "PID_123", ip = "127.0.0.1"})
	dump(p, "player")
end)
