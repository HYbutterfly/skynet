package.cpath = "luaclib/?.so;"..package.cpath
local calc = require "skynet.calc"

local game = require "game".game


local function exec(session, cmd, ...)
	local f = assert(game[cmd], string.format("Undefined action %s", tostring(cmd)))
	if session == 0 then
		f(game, ...)
	else
    	return calc.pack(f(game, ...))
    end
end


function handle(session, data, sz)
    return exec(session, calc.unpack(data, sz))
end

collectgarbage("stop")