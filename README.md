## skynet-calculator

这是一个并行计算框架, powerd by [skynet](https://github.com/cloudwu/skynet)

1. 该框架只是 skynet 功能的扩展, 将不定期同步原skynet仓库更新。
2. 该框架将更改以往的 skynet 开发体验, 极大提高生产效率. 
	游戏的状态和逻辑全部由框架托管, 相当于一个黑箱, 你只需要对其发出 action, 比如 ("login", {pid = "PID_123"})
eg:
```lua
	local calc = skynet.newservice("calculator", 4)
	local p = skynet.call(calc, "lua", "login", {pid = "PID_123", ip = "127.0.0.1"})
```

3. 在你定义 action handle 的时候, 你需要声明它的读写锁, 参见 game/lobby.lua
	读写锁一般根据你要读写 game的状态路径定义。读写锁冲突的 action 无法同时执行。

		特别的锁:
		"*": 表示锁住整个game
		"": 空串表示无锁 (危险！只建议在读取时序不敏感的数据时使用, 比如后台获取游戏在线人数)
eg:
```lua

	-- 运行中 #pid 会被 params.pid 替换
	-- 运行中 #roomid 会被 params.roomid 替换
	-- 该读写锁, 将会把该玩家, 及所在的房间锁住，
	lock("lobby.players.#pid, game.rooms.#roomid")(function()
		function game:game_action(params)
			-- pass
		end
	end)
```

4. 警告: 由于是多个线程同时读写一个 game luavm, 可能会出现严重的程序错误
	(已知 lua gc 会引起崩溃, 所以需要自己定义一个 action (use "*" rwlock) 去原子的执行gc)


## Test

```
./skynet examples/config
```

## 进阶
这是一个根据本框架写的 [mmorpg-demo](https://github.com/HYbutterfly/skynet-calc-mmorpg) 供参考
