FROM nginx:1.27-alpine

COPY docker/nginx.conf /etc/nginx/conf.d/default.conf

# Content is bind-mounted from ./www at runtime (live edit + mp3).
# Keep a minimal placeholder so the image starts without the volume.
RUN mkdir -p /usr/share/nginx/html && \
    printf '%s\n' '<!DOCTYPE html><title>Goum</title><p>Mount ./www</p>' \
      > /usr/share/nginx/html/index.html

EXPOSE 80
