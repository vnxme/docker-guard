#!/bin/sh

# Resources:
# https://bgp.he.net
# https://bgp.tools

PROV="ipverse"
URL_AS="https://github.com/ipverse/as-ip-blocks/releases/download/latest/as-ip-blocks.tar.gz"
URL_GEO="https://github.com/ipverse/geo-ip-blocks/releases/download/latest/geo-ip-blocks.tar.gz"

AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36"

DIR_CONF="/etc/bird/static.conf.d"
DIR_PROV="/etc/bird/${PROV}"

FILE_AS="${DIR_PROV}/as-ip-blocks.tar.gz"
FILE_GEO="${DIR_PROV}/geo-ip-blocks.tar.gz"

FILE_AS_MAP="/etc/bird/as.mapping.txt"
FILE_ISO_MAP="/etc/bird/iso.mapping.txt"

if [ ! -d "${DIR_CONF}" ]; then
	echo "Error: Directory ${DIR_CONF} doesn't exist. Exiting."
	exit 1
else
	rm "${DIR_CONF}"/*.${PROV}.conf 2>/dev/null
fi

if [ ! -d "${DIR_PROV}" ]; then
	mkdir -p "${DIR_PROV}"
fi

if [ ! -s "${FILE_AS_MAP}" ]; then
	echo "Error: File ${FILE_AS_MAP} doesn't exist. Exiting."
	exit 1
fi

if [ ! -s "${FILE_ISO_MAP}" ]; then
	echo "Error: File ${FILE_ISO_MAP} doesn't exist. Exiting."
	exit 1
fi

if [ ! -s "${FILE_AS}" ] || [ "$(($(date +%s)-$(date -r "${FILE_AS}" +%s)))" -gt 86400 ]; then
	if ! curl --fail --silent --location --user-agent "${AGENT}" --output "${FILE_AS}" "${URL_AS}"; then
		echo "Error: File ${FILE_AS} is missing or obsolete and can't be downloaded. Exiting."
		exit 1
	else
		FILE_EXTRACT="${DIR_PROV}/as.list.txt"
		truncate -s 0 "${FILE_EXTRACT}"

		while IFS= read -r LINE || [ -n "${LINE}" ]; do
			IFS=" " read -r ID GROUP NUMBERS <<-EOF
			${LINE}
			EOF

			if [ -n "${ID}" ] && [ -n "${GROUP}" ] && [ -n "${NUMBERS}" ]; then
				for NUMBER in $(echo "${NUMBERS}" | tr "," "\n"); do
					echo "as/${NUMBER}/ipv4-aggregated.txt" >> "${FILE_EXTRACT}"
					echo "as/${NUMBER}/ipv6-aggregated.txt" >> "${FILE_EXTRACT}"
				done
			fi
		done < "${FILE_AS_MAP}"

		tar -xzf "${FILE_AS}" -C "${DIR_PROV}" -T "${FILE_EXTRACT}"
	fi
fi

if [ ! -s "${FILE_GEO}" ] || [ "$(($(date +%s)-$(date -r "${FILE_GEO}" +%s)))" -gt 86400 ]; then
	if ! curl --fail --silent --location --user-agent "${AGENT}" --output "${FILE_GEO}" "${URL_GEO}"; then
		echo "Error: File ${FILE_GEO} is missing or obsolete and can't be downloaded. Exiting."
		exit 1
	else
		FILE_EXTRACT="${DIR_PROV}/geo.list.txt"
		truncate -s 0 "${FILE_EXTRACT}"

		while IFS= read -r LINE || [ -n "${LINE}" ]; do
			IFS=" " read -r ID GROUP CODES <<-EOF
			${LINE}
			EOF

			if [ -n "${ID}" ] && [ -n "${GROUP}" ] && [ -n "${CODES}" ]; then
				for CODE in $(echo "${CODES}" | tr "," "\n"); do
					CODE_LC="$(echo "${CODE}" | tr '[:upper:]' '[:lower:]')"
					echo "country/${CODE_LC}/${CODE_LC}-ipv4.txt" >> "${FILE_EXTRACT}"
					echo "country/${CODE_LC}/${CODE_LC}-ipv6.txt" >> "${FILE_EXTRACT}"
				done
			fi
		done < "${FILE_ISO_MAP}"

		tar -xzf "${FILE_GEO}" -C "${DIR_PROV}" -T "${FILE_EXTRACT}"
	fi
fi

while IFS= read -r LINE || [ -n "${LINE}" ]; do
	IFS=" " read -r ID GROUP NUMBERS <<-EOF
	${LINE}
	EOF

	if [ -n "${ID}" ] && [ -n "${GROUP}" ] && [ -n "${NUMBERS}" ]; then
		GROUP_LC="$(echo "${GROUP}" | tr '[:upper:]' '[:lower:]')"

		FILE_IPV4="${DIR_CONF}/${GROUP_LC}.ipv4.${PROV}.conf"
		FILE_IPV6="${DIR_CONF}/${GROUP_LC}.ipv6.${PROV}.conf"
		truncate -s 0 "${FILE_IPV4}"
		truncate -s 0 "${FILE_IPV6}"

		for NUMBER in $(echo "${NUMBERS}" | tr "," "\n"); do
			echo "# AS${NUMBER}" | tee -a "${FILE_IPV4}" "${FILE_IPV6}" > /dev/null

			FILE_TAB="${DIR_PROV}/as/${NUMBER}/ipv4-aggregated.txt"
			if [ -s "${FILE_TAB}" ]; then
				grep -E "^[^#]" "${FILE_TAB}" | awk '{printf "route %s unreachable;\n", $1}' >> "${FILE_IPV4}"
			fi

			FILE_TAB="${DIR_PROV}/as/${NUMBER}/ipv6-aggregated.txt"
			if [ -s "${FILE_TAB}" ]; then
				grep -E "^[^#]" "${FILE_TAB}" | awk '{printf "route %s unreachable;\n", $1}' >> "${FILE_IPV6}"
			fi
		done

		FILE_PROTO="${DIR_CONF}/${GROUP_LC}.proto.${PROV}.conf"
		cat <<-EOF > "${FILE_PROTO}"
		protocol static s4_${GROUP_LC} {
			description "${GROUP} AS ${NUMBERS} IPv4";
			ipv4 {
				table mixed4;
				import filter {
					bgp_community.add((group_main, tag_ip4));
					bgp_community.add((group_main, tag_asn));
					bgp_community.add((group_main, ${ID}));
					accept;
				};
				export none;
			};
			include "${DIR_CONF}/${GROUP_LC}.ipv4.${PROV}.conf";
		}

		protocol static s6_${GROUP_LC} {
			description "${GROUP} AS ${NUMBERS} IPv6";
			ipv6 {
				table mixed6;
				import filter {
					bgp_community.add((group_main, tag_ip6));
					bgp_community.add((group_main, tag_asn));
					bgp_community.add((group_main, ${ID}));
					accept;
				};
				export none;
			};
			include "${DIR_CONF}/${GROUP_LC}.ipv6.${PROV}.conf";
		}
		EOF
	fi
done < "${FILE_AS_MAP}"

while IFS= read -r LINE || [ -n "${LINE}" ]; do
	IFS=" " read -r ID GROUP CODES <<-EOF
	${LINE}
	EOF

	if [ -n "${ID}" ] && [ -n "${GROUP}" ] && [ -n "${CODES}" ]; then
		GROUP_LC="$(echo "${GROUP}" | tr '[:upper:]' '[:lower:]')"

		FILE_IPV4="${DIR_CONF}/${GROUP_LC}.ipv4.${PROV}.conf"
		FILE_IPV6="${DIR_CONF}/${GROUP_LC}.ipv6.${PROV}.conf"
		truncate -s 0 "${FILE_IPV4}"
		truncate -s 0 "${FILE_IPV6}"

		for CODE in $(echo "${CODES}" | tr "," "\n"); do
			CODE_LC="$(echo "${CODE}" | tr '[:upper:]' '[:lower:]')"

			FILE_TAB="${DIR_PROV}/country/${CODE_LC}/${CODE_LC}-ipv4.txt"
			if [ -s "${FILE_TAB}" ]; then
				grep -E "^[^#]" "${FILE_TAB}" | awk '{printf "route %s unreachable;\n", $1}' >> "${FILE_IPV4}"
			fi

			FILE_TAB="${DIR_PROV}/country/${CODE_LC}/${CODE_LC}-ipv6.txt"
			if [ -s "${FILE_TAB}" ]; then
				grep -E "^[^#]" "${FILE_TAB}" | awk '{printf "route %s unreachable;\n", $1}' >> "${FILE_IPV6}"
			fi
		done

		FILE_PROTO="${DIR_CONF}/${GROUP_LC}.proto.${PROV}.conf"
		cat <<-EOF > "${FILE_PROTO}"
		protocol static s4_${GROUP_LC} {
			description "${GROUP} ${CODES} IPv4";
			ipv4 {
				table mixed4;
				import filter {
					bgp_community.add((group_main, tag_ip4));
					bgp_community.add((group_main, tag_geo));
					bgp_community.add((group_geo, ${ID}));
					accept;
				};
				export none;
			};
			include "${DIR_CONF}/${GROUP_LC}.ipv4.${PROV}.conf";
		}

		protocol static s6_${GROUP_LC} {
			description "${GROUP} ${CODES} IPv6";
			ipv6 {
				table mixed6;
				import filter {
					bgp_community.add((group_main, tag_ip6));
					bgp_community.add((group_main, tag_geo));
					bgp_community.add((group_geo, ${ID}));
					accept;
				};
				export none;
			};
			include "${DIR_CONF}/${GROUP_LC}.ipv6.${PROV}.conf";
		}
		EOF
	fi
done < "${FILE_ISO_MAP}"

exit 0