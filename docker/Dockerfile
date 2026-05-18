# KoDashboard standalone server.
#
# Runs the existing api.lua / dataloader.lua / web/ assets from the plugin
# outside of KOReader, against a mounted koreader data directory.
#
# Notes:
# - LuaJIT is required because lua-ljsqlite3 uses LuaJIT FFI.
# - lua-ljsqlite3 and its `xsys` dep are vendored under docker/vendor/ so
#   the build does not need to fetch them from the network.
# - All other Lua deps come from Debian apt packages — no luarocks calls.

FROM debian:bookworm-slim

RUN set -eu; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        luajit \
        lua-socket \
        lua-filesystem \
        lua-dkjson \
        libsqlite3-0 \
        ca-certificates \
        tini \
    ; \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Plugin code (api / dataloader) and frontend assets. _meta.lua is KOReader
# plugin metadata that pulls in `gettext`; not needed here.
COPY api.lua dataloader.lua /app/
COPY web/ /app/web/

# Docker-only stubs, vendored Lua deps, and server entry point.
COPY docker/stubs/  /app/stubs/
COPY docker/vendor/ /app/vendor/
COPY docker/server.lua /app/server.lua

# Look up modules in: app code, stubs, vendored deps, then the apt-installed
# /usr/share/lua/5.1/ tree (which holds socket / lfs / dkjson).
ENV LUA_PATH="/app/?.lua;/app/?/init.lua;/app/stubs/?.lua;/app/stubs/?/init.lua;/app/vendor/?.lua;/app/vendor/?/init.lua;/usr/share/lua/5.1/?.lua;/usr/share/lua/5.1/?/init.lua;;" \
    LUA_CPATH="/usr/lib/x86_64-linux-gnu/lua/5.1/?.so;/usr/lib/lua/5.1/?.so;;" \
    PORT=8686 \
    HOST=0.0.0.0 \
    WEB_DIR=/app/web \
    KO_DATA_DIR=/data/koreader \
    KO_SETTINGS_DIR=/data/koreader/settings

EXPOSE 8686

ENTRYPOINT ["/usr/bin/tini", "--", "luajit", "/app/server.lua"]
