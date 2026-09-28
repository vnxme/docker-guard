ARG ALPINE_VERSION=3.23

FROM --platform=${TARGETPLATFORM:-linux/amd64} xddxdd/bird-lg-go:latest AS frontend
FROM --platform=${TARGETPLATFORM:-linux/amd64} xddxdd/bird-lgproxy-go:latest AS proxy

FROM --platform=${TARGETPLATFORM:-linux/amd64} alpine:${ALPINE_VERSION}

RUN apk add --update --no-cache bird curl supervisor traceroute tzdata && mkdir -p /etc/bird && mv /etc/bird.conf /etc/bird/sample.conf

COPY --from=frontend /frontend /usr/local/bin/bird-lg-go
COPY --from=proxy /proxy /usr/local/bin/bird-lgproxy-go

COPY supervisord.conf /etc/supervisord.conf
COPY --parents ./**/*.conf ./*.txt ./*.sh /etc/bird/
RUN chmod 755 /etc/bird/*.sh; ls -la /etc/bird/

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisord.conf"]

HEALTHCHECK --interval=24h --timeout=15m --start-period=15s --retries=1 CMD date +"%Y-%m-%d %H:%M:%S"; /etc/bird/ipverse.sh && /usr/sbin/birdc configure || exit 1
