# Upgrading from v1

v2.0.0 changes where the Web Console key lives and rejects wildcard Gateway
listeners. The package migrates the v1 UCI layout automatically on the first
start after the upgrade.

## What the migration does

The init script runs `migrate_config` before reading `/etc/config/magpie`:

1. A legacy wildcard `gateway_addr` such as `0.0.0.0:3425`, `*:3425` or
   `[::]:3425` is rewritten to `127.0.0.1:<port>`.
2. A legacy UCI `web_key` is copied to `/etc/magpie/secrets/web.key`
   (`root:root`, mode `0600`) and removed from UCI, so browsers already signed
   in to the Web Console keep their session.
3. The removed `web_addr` option is deleted.
4. The migrated UCI configuration is committed before the service starts.

If the legacy key is missing, too short, or contains unsupported characters,
it is removed from UCI and a new 64-character key is generated in the secret
file. In that case users must sign in again.

## After upgrading

Check the service and the key file:

```sh
/etc/init.d/magpie status
ubus call magpie status '{}'
ls -l /etc/magpie/secrets/web.key
uci show magpie
```

Expected:

- `gateway_addr='127.0.0.1:3425'` unless it was already a specific address;
- no `web_key` or `web_addr` in UCI;
- `web.key` is `-rw------- root root`;
- `logread` does not contain `?k=` after a restart;
- LuCI shows `luci-app-magpie` version `2.0.0`.

## If remote Gateway clients need LAN/VPN access

The migration deliberately falls back to loopback. Re-enable remote access only
with an explicit address and firewall design:

```sh
uci set magpie.main.gateway_addr='192.168.1.1:3425'
uci commit magpie
/etc/init.d/magpie restart
```

Use a specific router LAN/VPN address, restrict the port to trusted source
networks, and create Gateway API keys in the Magpie Web Console. Wildcard,
hostname and unbracketed IPv6 listeners are rejected.

## Web Console access after the upgrade

The Web Console is loopback-only. On the administrator workstation:

```sh
ssh -L 3430:127.0.0.1:3430 root@<router-lan-ip>
```

In a second terminal, read the root-only key:

```sh
ssh root@<router-lan-ip> 'cat /etc/magpie/secrets/web.key'
```

Then open `http://127.0.0.1:3430/` and enter the key in Magpie's sign-in prompt.
Do not put the key in a saved URL or share it.

## If you need to roll back

A v1 package reads `web_key` and `web_addr` from UCI, but the migration removed
them. Before rolling back, back up the secret file and restore the old UCI
options, or expect to reconfigure the Web Console key and listen address. Use a
new key for a rollback rather than reusing a key that was exposed in logs.
