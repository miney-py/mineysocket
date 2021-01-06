# mineysocket - A network api mod for minetest

The goal of this mod is to open minetest for other scripting languages.

For that this mod opens a TCP network port where it receives lua snippets to execute these inside the minetest.
That allows you to write a socket client in your favorite language to wrap api functions over network/internet.

## Requirements

* luasockets
* lua-cjson

### Installation with Windows

It's more complicated, because you can't just put some dlls in the right place. 
You have to recompile minetest together with luasocket and lua-cjson. 

Luckily there are some scripts to do that for you or you just download a precompiled minetest.

* Precompiled binary: https://github.com/miney-py/minetest_windows/releases
* Build script: https://github.com/miney-py/minetest_windows
* Or use the miney windows distribution: https://github.com/miney-py/miney_distribution

### Installation with Debian Buster

The latest minetest version is in the backport repository for buster, so it's very easy to install: https://wiki.minetest.net/Setting_up_a_server/Debian
```
apt install lua-socket lua-cjson
cd /var/games/minetest-server/.minetest/mods
git clone git@github.com:miney-py/mineysocket.git
```
* Edit /var/games/minetest-server/.minetest/worlds/\<your_world\>/world.mt and add:
```
load_mod_mineysocket = true
```
* Connect at least once with minetest to your server and login with a username + password, to get you registered
* Edit /etc/minetest/minetest.conf
  * name = \<your_playername\>  # This gives you all privileges on your server
  * secure.trusted_mods = mineysocket  # This is needed for luasocket and lua-cjson
  * Optional but recommended:
    * enable_rollback_recording = true  # This allows you to clean up your world

## Settings

Default is, that mineysocket listens on 127.0.0.1 on port 29999.

You can change this in the minetest menu (Settings -> All Settings -> Mods -> mineysocket) or in the minetest.conf.

```
mineysocket.host_ip = 127.0.0.1
```
The IP mineysocket is listening on. 
With "127.0.0.1" only you can connect, with "*" or "0.0.0.0" anyone in the network or internet can connect. 
 
WARNING: It could be dangerous to open this to everyone in the internet! Only change if you know what you are doing! If you don't know, let it at "127.0.0.1".
```
mineysocket.host_port = 29999
```
The TCP port mineysocket is listening. 

## Notes

Clients can only run code after authentication and if the user has "server" privilege (or if connected from 127.0.0.1).

This may change, but currently authenticated users can do anything in the minetest api, also change their own and other users privileges!

**You use this at your own risk!**

## Todo

- [ ] Authentication without sending cleartext password
- [ ] Implement limited user rights with a fixed set of available commands

## Protocol description

mineysocket is a simple JSON-based TCP protocol. Send a valid JSON-String with a tailing linebreak (`\r\n`) to the port 
and mineysocket responds a JSON string with a tailing linebreak.

### Ping

A simple alive check, and the only command implemented without json.

```
>>> ping\r\n
<<< pong\r\n
``` 

### Authentication

```
>>> {"playername": "player", "password": "my_password"}\r\n
<<< {"result": ["auth_ok", "127.0.0.1:31928"], "id": "auth"}\r\n
``` 
Send playername and password and you get auth_ok with your clientid.

On error you get a error object:
```
<<< {"error": "authentication error"}\r\n
```
Btw: All errors look like this, with different error descriptions.

Connections from 127.0.0.1 don't need to authenticate.

### Run lua code

After authentication, you are ready to send a command. An JSON object key is a command, in this example 
"lua" to run lua code.
```
>>> {"lua": "return 12 + 2, \"something\"", id="myrandomstring"}\r\n
<<< {"result": [14, "something"], id="myrandomstring"}\r\n
```
Lua code runs inside a function definition, so you need to return a value to get a result send back to you. 
As you see, you can return multiple values. 
Optional you can send a (random) id to identify your result, if you run multiple codes parallel.

More commands will be added later.

### Events

Mineysocket can send JSON objects on global events. 

To receive events, you need to register for this event. This example registers for `chat_message`:
```
>>> {"register_event": "chat_message"}\r\n
```

You can register for the following events.

##### The server was gracefully stopped
```
<<< {"event": ["shutdown"]}\r\n
```

#####  A player's health points changed
```
<<< {"event": ["player_hpchanged", "<playername>", "<hp change>", {'type': '<reason>', 'from': '<player or engine>'}]}\n
```

##### A player died
```
<<< {"event": ["player_died", "<playername>", "<reason>"]}\r\n
```

##### A player respawned
```
<<< {"event": ["player_respawned", "<playername>"]}\r\n
```

##### A player joined
```
<<< {"event": ["player_joined", "<playername>"]}\r\n
```

##### A player left
```
<<< {"event": ["player_left", "<playername>"]}\r\n
```

##### An authentication failed
```
<<< {"event": ["auth_failed", "<name>", "<ip>"]}\r\n
```

##### A player cheated

With one of the following types

* `moved_too_fast`
* `interacted_too_far`
* `interacted_while_dead`
* `finished_unknown_dig`
* `dug_unbreakable`
* `dug_too_fast`
```
<<< {"event": ["player_cheated", "<playername>", {"type": "<type>"}]}\r\n
```

##### A new chat message
```
<<< {"event": ["chat_message", "<name>", "<message>"]}\r\n
```