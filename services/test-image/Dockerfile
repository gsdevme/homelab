FROM php:7.4-fpm

RUN mkdir -p /app/public

COPY ./index.php /app/public/index.php

WORKDIR /app/
USER www-data
