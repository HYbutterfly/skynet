local skynet = require "skynet"
require "skynet.manager" 
local calc = require "skynet.calc"
local game_rwlock = require "game".rwlock

local workerfile,  NWORKER = ...
NWORKER = NWORKER and math.tointeger(NWORKER) or 8


local CALC_SEND_SESSION = 0
local CALC_CALL_SESSION = 1


local LOCK_NOTHING = 0
local LOCK_ALL = 1

-- fifo queue
local function newqueue()
    local queue = {}
    local size = 0
    local head = 1
    local tail = 0

    local self = {}

    function self.get()
        if size > 0 then
            local value = queue[head]
            queue[head] = nil
            head = head + 1
            size = size - 1
            return value
        end
    end

    function self.put(value)
        tail = tail + 1
        size = size + 1
        queue[tail] = value
        return self
    end

    function self.size()
        return size
    end

    return self
end

local function preload_game_static_rwlock()
	local tmp = {}
	for k,v in pairs(game_rwlock) do
		if not v:find("#") then
			if v == '*' then 
				game_rwlock[k] = LOCK_ALL
			elseif  v == "" then
				game_rwlock[k] = LOCK_NOTHING
			else
				if tmp[v] then
					game_rwlock[k] = tmp[v]
				else
					game_rwlock[k] = v:split(',')
					for i,v in ipairs(game_rwlock[k]) do
						game_rwlock[k][i] = v:trim()
					end
					tmp[v] = game_rwlock[k]
				end
			end
		end
	end
	tmp = nil
end

local function gen_dynamic_rwlock(lock_str, params)
	lock_str = lock_str:gsub("#(%w+)", function (key)
		if params and params[key] then
			return tostring(params[key])
		end
	end)
    local lock = lock_str:split(",")
    for i, l in ipairs(lock) do
        lock[i] = l:trim()
    end

    -- remove `nil` param lock
    for i=#lock,1,-1 do
    	if lock[i]:find('#') then
        	table.remove(lock, i)
        end
    end

    return lock
end

local function short_string(s, s2)
	if #s < #s2 then
		return s, s2
	else
		return s2, s
	end
end

local function check_competition(rwlock, rwlock2)
	if rwlock == LOCK_NOTHING or rwlock2 == LOCK_NOTHING then
		return false
	end
	if rwlock == LOCK_ALL or rwlock2 == LOCK_ALL then
		return true
	end
    for _, lock in ipairs(rwlock) do
    	for _,lock2 in ipairs(rwlock2) do
    		local s, l = short_string(lock, lock2)
    		if l:find(s) == 1 then
    			return true
    		end
    	end
    end
    return false
end

local function gen_rwlock(name, params)
	local lock = game_rwlock[name]
	if type(lock) == "string" then
		return gen_dynamic_rwlock(lock, params)
	else
		return lock
	end
end

---------------------------------------------------------------------
-- manager 

local manager = {
	myaddr = skynet.self(),
	nworker = 0,
	workers = {},
	workerindex = {},

	slots = {},
	nextone = {empty = true},
	queue = newqueue()
}

function manager:init(workermain, nworker)
	assert(nworker >= 2)
	self.nworker = nworker
	self.workers = calc.start(workermain, nworker)
	for i,w in ipairs(self.workers) do
		self.workerindex[w] = i
		self.slots[i] = {
			working = false,
			conflict = false,
			response = nil,
			lock = nil
		}
	end
end

function manager:check_slots(rwlock)
	local conflict = false
	for i,s in ipairs(self.slots) do
		if s.working and check_competition(s.lock, rwlock) then
			s.conflict = true
			conflict = true
		end
	end
	return conflict
end

function manager:find_conflict()
	for i,s in ipairs(self.slots) do
		if s.working and s.conflict then
			return true
		end
	end
	return false
end

function manager:_push(action, response, rwlock)
    if self.nextone.empty then
        local conflict = self:check_slots(rwlock)
        local idx = self:find_a_empty_solt()
        if not conflict and idx then
            self:insert2solt(idx, action, response, rwlock)
        else
            self.nextone.empty = false
            self.nextone.action = action
            self.nextone.response = response
            self.nextone.rwlock = rwlock
        end
    else
    	self.queue.put { action = action, response = response, rwlock = rwlock }
    end
end

function manager:nextone_join_solt(idx)
	self:_push(self.nextone.action, self.nextone.response, self.nextone.rwlock)
	self.nextone.empty = true
	
	while self.queue.size() > 0 do
		local item = self.queue.get()
		self:_push(item.action, item.response, item.rwlock)
		if not self.nextone.empty then
			break
		end
	end	
end

function manager:insert2solt(idx, action, response, rwlock)
	local s = self.slots[idx]
	s.working = true
	s.response = response
	s.lock = rwlock
	calc.send(self.myaddr, self.workers[idx], response and CALC_CALL_SESSION or CALC_SEND_SESSION, action.msg, action.sz)
end

function manager:on_worker_done(worker, msg, sz)
	local idx = self.workerindex[worker]
	local s = self.slots[idx]
	s.working = false
	s.conflict = false
	if s.response then
		s.response(true, msg, sz)
	end

	if not self.nextone.empty and not self:find_conflict() then
		self:nextone_join_solt(idx)
	end
end

function manager:push(action, response)
	self:_push(action, response, gen_rwlock(action.name, action.params))
end

function manager:find_a_empty_solt()
	for i,s in ipairs(self.slots) do
		if s.working == false then
			return i
		end
	end
end

---------------------------------------------------------------------
-- service 

skynet.init(function ()
	preload_game_static_rwlock()
	manager:init(workerfile, NWORKER)
end)

local function proxy(...) return ... end

skynet.register_protocol {
	name = "text",
	id = skynet.PTYPE_TEXT,
	unpack = proxy,
	dispatch = function (session, source, msg, sz)
		manager:on_worker_done(source, msg, sz)
	end
}

skynet.register_protocol {
	name = "system",
	id = skynet.PTYPE_SYSTEM,
	unpack = proxy,
}

-- don't free lua/text message
local forward_map = {
	[skynet.PTYPE_LUA] = skynet.PTYPE_SYSTEM,
	[skynet.PTYPE_TEXT] = skynet.PTYPE_TEXT
}

local function newaction(msg, sz, name, params)
	return { msg = msg, sz = sz, name = name, params = params }
end

skynet.forward_type(forward_map ,function()
	skynet.dispatch("system", function (session, source, msg, sz)
		if session == 0 then
			manager:push(newaction(msg, sz, skynet.unpack(msg, sz)))
		else
			manager:push(newaction(msg, sz, skynet.unpack(msg, sz)), skynet.response(proxy))
		end
	end)
	skynet.register "CALCULATOR"
end)
