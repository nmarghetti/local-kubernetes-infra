FROM nginx

ARG APP_NAME="Unkown"
ARG APP_VERSION="Unkown"

ENV APP_NAME=$APP_NAME
ENV APP_VERSION=$APP_VERSION
ENV NGINX_PORT=8080

COPY html /usr/share/nginx/html
COPY entrypoint.sh /docker-entrypoint.d/
RUN export APP_NAME=$APP_NAME \
  && export APP_VERSION=$APP_VERSION \
  && envsubst </usr/share/nginx/html/index.html > /usr/share/nginx/html/index.html.tmp \
  && mv /usr/share/nginx/html/index.html.tmp /usr/share/nginx/html/index.html \
  && sed -i -re 's/listen\s+80/listen 8080/' -e 's/listen\s+\[::]:80/listen [::]:8080/' /etc/nginx/conf.d/default.conf

