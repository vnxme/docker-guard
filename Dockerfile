FROM xddxdd/bird-lg-go:latest AS frontend
FROM xddxdd/bird-lgproxy-go:latest AS proxy
FROM alpine:3.24

RUN apk add --no-cache bird curl supervisor traceroute tzdata && mkdir -p /etc/bird && mv /etc/bird.conf /etc/bird/sample.conf

COPY --from=frontend /frontend /usr/local/bin/frontend
COPY --from=proxy /proxy /usr/local/bin/proxy

COPY supervisord.conf /etc/supervisord.conf
COPY bird/ /etc/bird/
RUN chmod 755 /etc/bird/*.sh; ls -la /etc/bird/

ENTRYPOINT ["/etc/bird/env.sh"]
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisord.conf"]

ENV BIRD_ASN=65000 BIRD_IP=1.2.3.4

EXPOSE 80 179

HEALTHCHECK --interval=5m --timeout=10s --start-period=30s --retries=3 CMD /usr/sbin/birdc -r show status >/dev/null || exit 1
