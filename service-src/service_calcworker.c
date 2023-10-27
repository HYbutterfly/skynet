#include <stdio.h>
#include <string.h>

#include <lua.h>

#include "skynet.h"
#include "skynet_server.h"
#include "skynet_mq.h"


struct calcworker {
	lua_State * L;
};


struct calcworker *
calcworker_create(void) {
	struct calcworker * inst = skynet_malloc(sizeof(*inst));
	inst->L = NULL;
	return inst;
}

void
calcworker_release(struct calcworker * inst) {
	skynet_free(inst);
}

static int
calcworker_cb(struct skynet_context * context, void *ud, int type, int session, uint32_t source, const void * msg, size_t sz) {
	static struct skynet_message smsg;
	struct calcworker * inst = ud;

	switch (type) {
	case PTYPE_TEXT:
		lua_getglobal(inst->L, "handle");
		lua_pushlightuserdata(inst->L, (void*)msg);
		lua_pushinteger(inst->L, sz);
		lua_call(inst->L, 2, 2);

	    void *data = lua_touserdata(inst->L, -2); 
	    size_t size = lua_tointeger(inst->L, -1);
	    lua_pop(inst->L, 2);
	    
		smsg.source = skynet_context_handle(context);
		smsg.session = 0;
		smsg.data = data;
		smsg.sz = size | ((size_t)PTYPE_TEXT << MESSAGE_TYPE_SHIFT);
		skynet_context_push(source, &smsg);
		break;
	}
	return 0;
}

int
calcworker_init(struct calcworker * inst, struct skynet_context *ctx, const char * parm) {
	lua_State *L = (lua_State *)parm;
	inst->L = L;
	skynet_callback(ctx, inst, calcworker_cb);
	return 0;
}
