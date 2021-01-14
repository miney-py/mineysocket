FROM alpine:latest AS compile

LABEL version="1.0" maintainer="Robert Lieback <info@zetabyte.de>"

ENV MINETEST_VERSION 5.3.0
ENV MINETEST_GAME_VERSION stable-5

WORKDIR /usr/src/minetest

RUN apk add --no-cache git build-base irrlicht-dev cmake bzip2-dev libpng-dev \
		jpeg-dev libxxf86vm-dev mesa-dev sqlite-dev libogg-dev \
		libvorbis-dev openal-soft-dev curl-dev freetype-dev zlib-dev \
		gmp-dev jsoncpp-dev postgresql-dev leveldb-dev luajit-dev ca-certificates && \
	git clone --depth=1 --single-branch --branch ${MINETEST_VERSION} -c advice.detachedHead=false https://github.com/minetest/minetest.git . && \
	git clone --depth=1 -b ${MINETEST_GAME_VERSION} https://github.com/minetest/minetest_game.git ./games/minetest_game && \
	rm -fr ./games/minetest_game/.git

WORKDIR /usr/src/minetest
RUN cd build && \
	cmake .. \
		-DCMAKE_INSTALL_PREFIX=/usr/local \
		-DCMAKE_BUILD_TYPE=Release \
		-DBUILD_SERVER=TRUE \
		-DBUILD_UNITTESTS=FALSE \
		-DBUILD_CLIENT=FALSE \
		-DENABLE_LEVELDB=ON \
		-DVERSION_EXTRA=miney_docker && \
	make && \
	make install

FROM alpine:latest AS server

ENV MT_NAME Miney
ENV MT_DEFAULT_PASSWORD ""
ENV MT_SECURE__TRUSTED_MODS "mineysocket"
ENV MT_APPEND "mineysocket.host_ip = *;"

COPY --from=compile /usr/local/share/minetest /usr/local/share/minetest
COPY --from=compile /usr/local/bin/minetestserver /usr/local/bin/minetestserver
COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh

RUN apk add --no-cache sqlite-libs leveldb postgresql-libs curl gmp libstdc++ libgcc libpq luajit lua5.1-socket lua5.1-cjson bash && \
	adduser -D minetest --uid 30000 -h /var/lib/minetest && \
	mkdir -p /var/lib/minetest/.minetest/mods/mineysocket && \
	chown -R minetest:minetest /var/lib/minetest && \
	chmod +x /usr/local/bin/entrypoint.sh

COPY --from=compile --chown=minetest:minetest /usr/src/minetest/minetest.conf.example /var/lib/minetest/.minetest/minetest.conf
COPY --chown=minetest:minetest init.lua mod.conf settingtypes.txt README.md LICENSE /var/lib/minetest/.minetest/mods/mineysocket/
COPY --chown=minetest:minetest docker/worlds/ /var/lib/minetest/.minetest/worlds/

WORKDIR /var/lib/minetest

USER minetest:minetest

EXPOSE 30000/udp 30000/tcp 29999/tcp

VOLUME /var/lib/minetest/.minetest

ENTRYPOINT /usr/local/bin/entrypoint.sh
