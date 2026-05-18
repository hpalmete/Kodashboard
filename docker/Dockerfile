# KoDashboard standalone server.
#
# Reuses the existing api.lua / dataloader.lua / web/ assets from the plugin
# and runs them outside KOReader against a mounted KOReader data directory.

FROM alpine:3.20

# - luajit: lua-ljsqlite3 uses LuaJIT FFI (not stock Lua 5.1).
# - luasocket / luafilesystem / dkjson: runtime deps of api.lua/dataloader.lua.
# - lua-ljsqlite3 + its xsys dep: vendored at the path the plugin requires
#   ("lua-ljsqlite3/init") since the luarocks-published "ljsqlite3" lives at
#   a different module path.
RUN set -eu; \
    apk add --no-cache \
        luajit \
        sqlite-libs \
        ca-certificates \
        tini \
        curl \
        luarocks5.1 \
        build-base \
        sqlite-dev \
        luajit-dev \
    ; \
    luarocks-5.1 install luasocket; \
    luarocks-5.1 install luafilesystem; \
    luarocks-5.1 install dkjson; \
    LUA_SHARE=/usr/local/share/lua/5.1; \
    mkdir -p "$LUA_SHARE/lua-ljsqlite3" "$LUA_SHARE/xsys/_dep"; \
    curl -fsSL https://github.com/stepelu/lua-ljsqlite3/archive/refs/heads/master.tar.gz \
        | tar -xz -C /tmp/; \
    cp /tmp/lua-ljsqlite3-master/init.lua    "$LUA_SHARE/lua-ljsqlite3/init.lua"; \
    cp /tmp/lua-ljsqlite3-master/__init.lua  "$LUA_SHARE/lua-ljsqlite3/__init.lua"; \
    cp /tmp/lua-ljsqlite3-master/__meta.lua  "$LUA_SHARE/lua-ljsqlite3/__meta.lua"; \
    curl -fsSL https://github.com/stepelu/lua-xsys/archive/refs/heads/master.tar.gz \
        | tar -xz -C /tmp/; \
    cp /tmp/lua-xsys-master/init.lua   "$LUA_SHARE/xsys/init.lua"; \
    cp /tmp/lua-xsys-master/__meta.lua "$LUA_SHARE/xsys/__meta.lua"; \
    cp -r /tmp/lua-xsys-master/_dep/.  "$LUA_SHARE/xsys/_dep/"; \
    apk del build-base sqlite-dev luajit-dev curl luarocks5.1; \
    rm -rf /root/.cache /tmp/* /var/cache/apk/*

WORKDIR /app

# Plugin code (api / dataloader) and frontend assets. `_meta.lua` is
# KOReader plugin metadata that pulls in `gettext` and isn't needed here.
COPY api.lua dataloader.lua /app/
COPY web/ /app/web/

# Docker-only stubs + server entry point.
COPY docker/stubs/ /app/stubs/
COPY docker/server.lua /app/server.lua

ENV LUA_PATH="/app/?.lua;/app/?/init.lua;/app/stubs/?.lua;/app/stubs/?/init.lua;/usr/local/share/lua/5.1/?.lua;/usr/local/share/lua/5.1/?/init.lua;;" \
    LUA_CPATH="/usr/local/lib/lua/5.1/?.so;/usr/lib/lua/5.1/?.so;;" \
    PORT=8686 \
    HOST=0.0.0.0 \
    WEB_DIR=/app/web \
    KO_DATA_DIR=/data/koreader \
    KO_SETTINGS_DIR=/data/koreader/settings

EXPOSE 8686

ENTRYPOINT ["/sbin/tini", "--", "luajit", "/app/server.lua"]
