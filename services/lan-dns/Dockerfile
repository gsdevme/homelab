FROM debian:buster-slim

RUN apt-get update \
    && apt-get install -y dnsmasq procps dnsutils --no-install-recommends

COPY dnsmasq.conf /etc/dnsmasq.conf

EXPOSE 53/UDP

CMD ["dnsmasq", "-k", "--log-facility=/dev/stdout"]
