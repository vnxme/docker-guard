#!/bin/sh

# Resources:
# https://bgp.he.net
# https://bgp.tools

PROV="bgptools"
URL="https://bgp.tools/table.txt"

AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36"

DIR_CONF="/etc/bird/static.conf.d"
DIR_PROV="/etc/bird/${PROV}"

FILE_MAP="/etc/bird/as.mapping.txt"
FILE_TAB="${DIR_PROV}/table.txt"

if [ ! -d "${DIR_CONF}" ]; then
	echo "Error: Directory ${DIR_CONF} doesn't exist. Exiting."
	exit 1
else
	rm "${DIR_CONF}"/*.${PROV}.conf
fi

if [ ! -d "${DIR_PROV}" ]; then
	mkdir -p "${DIR_PROV}"
else
	rm "${DIR_PROV}"/*.table.txt
fi

if [ ! -f "${FILE_MAP}" ]; then
	echo "Error: File ${FILE_MAP} doesn't exist. Exiting."
	exit 1
fi


if [ ! -f "${FILE_TAB}" ] || [ "$(($(date +%s)-$(date -r "${FILE_TAB}" +%s)))" -gt 86400 ]; then
	if ! curl --fail --silent --location --user-agent "${AGENT}" --output "${FILE_TAB}" "${URL}"; then
		echo "Error: File ${FILE_TAB} is missing or obsolete and can't be downloaded. Exiting."
		exit 1
	fi
fi

while IFS= read -r LINE || [ -n "${LINE}" ]; do
	IFS=" " read -r ID GROUP NUMBERS <<-EOF
	${LINE}
	EOF

	if [ -n "${GROUP}" ] && [ -n "${NUMBERS}" ] && [ -n "${ID}" ]; then
		GROUP_LC=$(echo "${GROUP}" | tr '[:upper:]' '[:lower:]')

		FILE_GROUP="${DIR_PROV}/${GROUP_LC}.table.txt"
		truncate -s 0 "${FILE_GROUP}"

		grep -E " ($(echo "${NUMBERS}" | tr ',' '|'))\$" "${FILE_TAB}" > "${FILE_GROUP}"

		FILE_IPV4="${DIR_CONF}/${GROUP_LC}.ipv4.${PROV}.conf"
		FILE_IPV6="${DIR_CONF}/${GROUP_LC}.ipv6.${PROV}.conf"
		truncate -s 0 "${FILE_IPV4}"
		truncate -s 0 "${FILE_IPV6}"

		for NUMBER in $(echo "${NUMBERS}" | tr "," "\n"); do
			echo "# AS${NUMBER}" >> "${FILE_IPV4}"
			echo "# AS${NUMBER}" >> "${FILE_IPV6}"
			grep -E ".*\..* ${NUMBER}\$" "${FILE_GROUP}" | awk '{printf "route %s unreachable;\n", $1}' >> "${FILE_IPV4}"
			grep -E ".*:.* ${NUMBER}\$" "${FILE_GROUP}" | awk '{printf "route %s unreachable;\n", $1}' >> "${FILE_IPV6}"
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
done < "${FILE_MAP}"

exit 0
