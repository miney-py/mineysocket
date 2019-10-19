# mineysocket - A network api mod for minetest

The goal of this mod is to open minetest for other scripting languages.

For that this mod opens a UDP network port where it receives lua snippets to execute these inside the minetest.
That allows you to write a socket client in your favorite language to wrap api functions over network/internet.

The reference implementation is miney (not released yet).

## Requirements

* luasockets
* lua-cjson

You can build your own Windows Client with these build scripts: https://github.com/miney-py/minetest_buildscripts

Precompiled builds will be provided soon.

### Installation with Debian Buster

The latest minetest version is in the backports repository for buster, so it's very easy to install: https://wiki.minetest.net/Setting_up_a_server/Debian
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
    * enable_rollback_recording = true  # This allows you to cleanup your world

## Notes

Clients can only run code after authentication and if the user has "server" privilege (or if connected from 127.0.0.1).

This may change, but currently authenticated users can do anything in the minetest api, also change there own and other users privileges!

**You use this at your own risk!**

## Todo

- [ ] Authentication without sending cleartext password
- [ ] Implement limited user rights with a fixed set of available commands
- [x] ~~Disable authentication for 127.0.0.1 clients~~
- [ ] Catch json encode errors
- [ ] Receive packages with multiple chunks
- [x] ~~Callback functions~~
- [x] ~~clientlist cleanup (delete unavailable/disconnected clients)~~
- [x] ~~Send basic events like player_joined or chatmessage~~


## Protocol description

mineysocket is a simple JSON-based UDP-Protocol. Send a valid JSON-String with a tailing linebreak (`\n`) to the port 
and mineysocket responds a JSON string with a tailing linebreak.

### Authentication

```
>>> {"playername": "player", "password": "my_password"}\n
<<< {"result": ["auth_ok", "127.0.0.1:31928"], "id": "auth"}\n
``` 
Send playername and password and you get auth_ok with your clientid (store this for later).

On error you get a error object:
```
<<< {"error": "authentication error"}\n
```
Btw: All errors look like this, with different error descriptions.

### Run lua code

After authentication you are ready to send a command. An JSON object key is a command, in this example 
"lua" to run lua code.
```
>>> {"lua": "return 12 + 2, \"something\"", id="myrandomstring"}\n
<<< {"result": [14, "something"], id="myrandomstring"}\n
```
Lua code runs inside a function definition, so you need to return value to get a result send back to you. 
As you see, you can return multiple values. 
You can optional send an (random) id to identify your result, if you run multiple codes parallel.

More commands will be added later.

### Events

Mineysocket sends JSON objects on global events.

The server was gracefully stopped:
```
<<< {"event": ["shutdown"]}\n
```

A players health points changed:
```
<<< {"event": ["player_hpchanged", "<playername>", "<hp change>", {'type': '<reason>', 'from': '<player or engine>'}]}\n
```

A player died:
```
<<< {"event": ["player_died", "<playername>", "<reason>"]}\n
```

A player respawned:
```
<<< {"event": ["player_respawned", "<playername>"]}\n
```

A player joined:
```
<<< {"event": ["player_joined", "<playername>"]}\n
```

A player left:
```
<<< {"event": ["player_left", "<playername>"]}\n
```

An authentication failed:
```
<<< {"event": ["auth_failed", "<name>", "<ip>"]}\n
```

A player cheated with one of the following types:
* `moved_too_fast`
* `interacted_too_far`
* `interacted_while_dead`
* `finished_unknown_dig`
* `dug_unbreakable`
* `dug_too_fast`
```
<<< {"event": ["player_cheated", "<playername>", {"type": "<type>"}]}\n
```

A new chat message:
```
<<< {"event": ["chat_message", "<name>", "<message>"]}\n
```