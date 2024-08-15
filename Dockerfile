FROM alpine:3.20 AS builder

# 安装编译所需的依赖
RUN apk add --no-cache build-base linux-headers automake autoconf pcre2-dev openssl-dev gd-dev geoip-dev cmake luajit-dev bash

# 复制源码到 Docker 镜像
COPY ../modules/nginx /tmp/nginx
COPY ../modules/ngx_brotli /tmp/ngx_brotli
COPY ../modules/ngx_devel_kit /tmp/ngx_devel_kit
COPY ../modules/lua-nginx-module /tmp/lua-nginx-module
COPY ../modules/stream-lua-nginx-module /tmp/stream-lua-nginx-module
COPY ../modules/lua-resty-core /tmp/lua-resty-core
COPY ../modules/lua-resty-lrucache /tmp/lua-resty-lrucache

# 编译ngx_brotli
WORKDIR /tmp/ngx_brotli/deps/brotli
RUN mkdir out
WORKDIR /tmp/ngx_brotli/deps/brotli/out
RUN cmake -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF \
    -DCMAKE_C_FLAGS="-Ofast -flto -funroll-loops -ffunction-sections -fdata-sections -Wl,--gc-sections" \
    -DCMAKE_CXX_FLAGS="-Ofast -flto -funroll-loops -ffunction-sections -fdata-sections -Wl,--gc-sections" \
    -DCMAKE_INSTALL_PREFIX=./installed ..
RUN cmake --build . --config Release --target brotlienc

ENV LUAJIT_LIB=/usr/lib
ENV LUAJIT_INC=/usr/include/luajit-2.1

# 编译 Nginx
WORKDIR /tmp/nginx
RUN ./auto/configure \
    --with-http_ssl_module \
    --with-http_v2_module \
    --with-http_v3_module \
    --with-http_realip_module \
    --with-http_addition_module \
    --with-http_image_filter_module \
    --with-http_geoip_module \
    --with-http_sub_module \
    --with-http_dav_module \
    --with-http_gunzip_module \
    --with-http_gzip_static_module \
    --with-http_auth_request_module \
    --with-http_slice_module \
    --with-http_stub_status_module \
    --with-mail \
    --with-mail_ssl_module \
    --with-stream \
    --with-stream_ssl_module \
    --with-stream_realip_module \
    --with-stream_geoip_module \
    --with-stream_ssl_preread_module \
    --add-module=/tmp/ngx_brotli \
    --add-module=/tmp/ngx_devel_kit \
    --add-module=/tmp/lua-nginx-module \
    --add-module=/tmp/stream-lua-nginx-module \
    --with-cc-opt='-O3'
RUN make -j$(nproc) && make install

# 编译 lua-resty-core
WORKDIR /tmp/lua-resty-core
RUN make install LUA_LIB_DIR=/usr/local/nginx/lualib

# 编译 lua-resty-lrucache
WORKDIR /tmp/lua-resty-lrucache
RUN make install LUA_LIB_DIR=/usr/local/nginx/lualib

# 调整配置文件
RUN sed -i '/default_type  application\/octet-stream;/a\\n    lua_package_path "/usr/local/nginx/lualib/?.lua;;";' "/usr/local/nginx/conf/nginx.conf"

# 创建最终的镜像
FROM alpine:3.20

# 设置必要的运行时依赖
RUN apk add --no-cache pcre2 gd geoip luajit

# 从 builder 镜像复制编译好的 Nginx 到最终镜像
COPY --from=builder /usr/local/nginx /usr/local/nginx

# 设置 PATH，这样我们就可以直接运行 nginx 命令
ENV PATH="/usr/local/nginx/sbin:${PATH}"

# 暴露端口
EXPOSE 80 443

# 当容器启动时运行 Nginx
CMD ["nginx", "-g", "daemon off;"]
