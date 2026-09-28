# docker-guard

A Docker image of **BGP Guard**: a [BIRD](https://bird.network.cz/) route server that publishes the IP prefixes of popular services and countries over BGP, tagged with communities. Your router peers with it, picks the groups it needs by community, and routes that traffic however you like, for example through a VPN tunnel.

- Prefixes of 30+ services (Google, Microsoft, Amazon, Cloudflare, Telegram, …) grouped by the AS numbers they announce from
- Prefixes of countries, selectable from the full ISO 3166-1 list
- Updated automatically every 24 hours from [ipverse](https://github.com/ipverse)
- A prefix that belongs to several groups is sent once, carrying the communities of all of them
- A web looking glass ([bird-lg-go](https://github.com/xddxdd/bird-lg-go)) to browse the routes

## Quick start

```sh
docker run -d --name guard --restart unless-stopped \
  -p 80:80 -p 179:179 \
  -e BIRD_ASN=65000 -e BIRD_IP=203.0.113.10 \
  vnxme/guard
```

The image is also published as `ghcr.io/vnxme/guard`. On start the container downloads the prefix lists and loads them into BIRD; until that finishes, peers receive no routes. Open `http://<host>/` to see the looking glass.

> [!WARNING]
> BGP sessions are accepted from **any** address and any AS number other than your own. Peers cannot inject routes (all imports are rejected), but anyone who reaches port 179 receives the full feed. Restrict access with a firewall if the feed should not be public.

## Environment variables

| Variable   | Default      | Description                        |
|------------|--------------|------------------------------------|
| `BIRD_ASN` | `65000`      | Local AS number                    |
| `BIRD_IP`  | `1.2.3.4`    | Router ID, in IPv4 address format  |

The container refuses to start if a value is not a valid AS number or router ID.

## Peering

The server waits for peers to connect (passive, multihop eBGP). An IPv4 session receives IPv4 routes, an IPv6 session receives IPv6 routes. The server's AS number must differ from yours.

Example for a BIRD client that only takes Google and Russia prefixes:

```
protocol bgp guard {
	local as 65100;
	neighbor 203.0.113.10 as 65000;
	multihop;
	ipv4 {
		import where (65000, 240) ~ bgp_community || (65001, 643) ~ bgp_community;
		export none;
	};
}
```

The routes' next hop is the server itself, so in practice your import filter should also point them at your tunnel or gateway.

## Communities

The values below assume the default `BIRD_ASN=65000`; replace `65000` with your AS number and `65001` with your AS number + 1.

| Community         | Meaning                                                                 |
|-------------------|-------------------------------------------------------------------------|
| `65000:4`         | IPv4 route                                                              |
| `65000:6`         | IPv6 route                                                              |
| `65000:10`        | Route comes from an AS group                                            |
| `65000:11`        | Route comes from a country                                              |
| `65000:<ID>`      | AS group, `<ID>` from [as.mapping.txt](bird/as.mapping.txt)             |
| `65001:<ISO>`     | Country, `<ISO>` is its ISO 3166-1 numeric code, e.g. `65001:643` Russia |
| `65000:100`       | Custom static route (see [Custom routes](#custom-routes))               |

### AS groups

| ID  | Group          | ID  | Group          | ID  | Group          |
|-----|----------------|-----|----------------|-----|----------------|
| 110 | Akamai         | 220 | Frantech       | 330 | OpenAI         |
| 120 | Amazon         | 230 | Gcore          | 340 | Oracle         |
| 130 | Cloudflare     | 240 | Google         | 350 | OVH            |
| 140 | Clouvider      | 250 | Hetzner        | 360 | Scalaxy        |
| 150 | Constant_Vultr | 260 | IBM_Cloud      | 370 | Scaleway       |
| 160 | Contabo        | 270 | Iomart         | 380 | Telegram       |
| 170 | Creanova       | 280 | M247           | 390 | Twitter        |
| 180 | Datacamp_CDN77 | 290 | Melbicom       | 400 | Youtube        |
| 190 | DigitalOcean   | 300 | Microsoft      | 410 | Zenlayer       |
| 200 | Facebook       | 310 | Mullvad        |     |                |
| 210 | Fastly         | 320 | Netflix        |     |                |

The Microsoft group includes its subsidiaries (GitHub, LinkedIn, Skype, Activision Blizzard, ZeniMax).

### Countries

Enabled by default: Belarus (112), Kazakhstan (398), Russia (643), Ukraine (804). All other countries are listed in [iso.mapping.txt](bird/iso.mapping.txt) and commented out.

## Customization

Configuration lives in `/etc/bird` inside the container; the defaults are in the [bird](bird/) directory of this repository. Replace any file by mounting your own version over it.

### Groups and countries

```sh
docker run … \
  -v ./as.mapping.txt:/etc/bird/as.mapping.txt:ro \
  -v ./iso.mapping.txt:/etc/bird/iso.mapping.txt:ro \
  vnxme/guard
```

Both files have one group per line, `ID Name items`:

```
# ID  Name      AS numbers (as.mapping.txt) or ISO alpha-2 codes (iso.mapping.txt)
240 Google 15169,36040,396982
643 Russia RU
# 392 Japan JP   <- disabled
```

- `#` starts a comment, either on its own line or after an entry.
- `Name` may only contain letters, digits and `_`, and must be unique across both files.
- IDs in `as.mapping.txt` must not be 4, 6, 10, 11 or 100, which are used by other communities.
- IDs in `iso.mapping.txt` are by convention the ISO 3166-1 numeric codes.

Changes are applied on the next update, or immediately after `docker restart guard`.

### Custom routes

Files named `*.ipv4.generic.conf` and `*.ipv6.generic.conf` in `/etc/bird/static.conf.d/` are loaded as extra routes tagged `65000:100`:

```
route 198.51.100.0/24 unreachable;
```

### Upstream BGP feeds

The files in [bgp.conf.d](bird/bgp.conf.d/) open sessions to [antifilter.download](https://antifilter.download), [antifilter.network](https://antifilter.network) and [Re-filter](https://github.com/1andrevich/Re-filter-lists). Their routes are kept in separate tables (`afd4`/`afd6`, `afn4`/`afn6`, `ref4`/`ref6`) that you can browse in the looking glass; they are not passed on to your peers. Mount an empty file over one to disable it, or add your own `*.conf` files there.

## How it works

The container runs [supervisord](http://supervisord.org/) with four programs:

| Program    | Role                                                                                  |
|------------|---------------------------------------------------------------------------------------|
| `bird`     | The BGP server                                                                        |
| `updater`  | Every 24 hours runs [ipverse.sh](bird/ipverse.sh), which downloads the prefix lists and generates BIRD config, then reloads BIRD; retries every 5 minutes on failure |
| `proxy`    | Looking glass backend, talks to BIRD (listens on `127.0.0.1:8000` only)               |
| `frontend` | Looking glass web interface on port 80                                                |

[bgptools.sh](bird/bgptools.sh) is an alternative generator that uses the [bgp.tools](https://bgp.tools) routing table instead of ipverse; it is included but not run by default.

All logs go to `docker logs`. The Docker health check reports whether BIRD is responding.

## Image tags

| Tag                     | Built from                                  |
|-------------------------|---------------------------------------------|
| `latest`                | The newest release                          |
| `1.2.3`, `1.2`, `1`     | Release `v1.2.3` (and the newest `1.2.x` / `1.x`) |
| `main`                  | The newest commit on `main`                 |
| `weekly`                | Weekly rebuild of `main` with updated base image and packages |
| `sha-<commit>`          | A specific commit                           |

Images are built for `linux/amd64`, `linux/arm64`, `linux/arm/v7` and `linux/386`.

## Building

```sh
docker build -t guard .
```
