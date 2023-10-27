#define LUA_LIB

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

#include "skynet.h"
#include "skynet_server.h"
#include "skynet_mq.h"

#include "lua-seri.h"


static int
lstart(lua_State *L) {

	const char *luamain = luaL_checkstring(L, 1);
	lua_Integer nworker = luaL_checkinteger(L, 2);

	lua_State *W = luaL_newstate();

	luaL_openlibs(W);
	if (luaL_dostring(W, luamain)) {
		return luaL_error(L, "%s", lua_tostring(W, -1));
	}

	lua_newtable(L);     // {handle, ...}
	lua_newtable(W);  	 // {thread -> ctx}
	struct skynet_context *ctx;
	lua_State *thread;
	for (int i = 0; i < nworker; ++i) {
		lua_pushinteger(L, i+1);

		thread = lua_newthread(W);
		ctx = skynet_context_new("calcworker", (const char *)thread);
		lua_pushlightuserdata(W, ctx);
		lua_settable(W, -3); 

		lua_pushinteger(L, skynet_context_handle(ctx));
		lua_settable(L, -3); 
	}
	lua_setfield(W, LUA_REGISTRYINDEX, "calcworker_context");
	return 1;
}

static int
lsend(lua_State *L) {
	uint32_t source = luaL_checkinteger(L, 1);
	uint32_t handle = luaL_checkinteger(L, 2);
	void *data = lua_touserdata(L, 3);
	uint32_t sz = luaL_checkinteger(L, 4);

	static struct skynet_message smsg;
	smsg.source = source;
	smsg.session = 0;
	smsg.data = data;
	smsg.sz = sz | ((size_t)PTYPE_TEXT << MESSAGE_TYPE_SHIFT);
	skynet_context_push(handle, &smsg);
	return 0;
}


struct skynet_context *
query_context(lua_State *L) {
	struct skynet_context * ctx = NULL;
	lua_getfield(L, LUA_REGISTRYINDEX, "calcworker_context");
	if (lua_isnil(L, -1)) {
		lua_pop(L, 1);
		return NULL;
	}
	lua_pushthread(L);
	lua_gettable(L, -2);
	ctx = lua_touserdata(L, -1);
	lua_pop(L, 2);
	return ctx;
}


static int
lerror(lua_State *L) {
	struct skynet_context * ctx = query_context(L);
	int n = lua_gettop(L);
	if (n <= 1) {
		lua_settop(L, 1);
		const char * s = luaL_tolstring(L, 1, NULL);
		skynet_error(ctx, "%s", s);
		return 0;
	}
	luaL_Buffer b;
	luaL_buffinit(L, &b);
	int i;
	for (i=1; i<=n; i++) {
		luaL_tolstring(L, i, NULL);
		luaL_addvalue(&b);
		if (i<n) {
			luaL_addchar(&b, ' ');
		}
	}
	luaL_pushresult(&b);
	skynet_error(ctx, "%s", lua_tostring(L, -1));
	return 0;
}


LUAMOD_API int
luaopen_skynet_calc(lua_State *L) {
	luaL_Reg l[] = {
		// for calculator
		{ "start", lstart },
		{ "send", lsend },

		// for calcworker
		{ "pack", luaseri_pack },
		{ "unpack", luaseri_unpack },
		{ "error", lerror },
		{ NULL, NULL },
	};
	luaL_checkversion(L);
	luaL_newlib(L, l);

	return 1;
}