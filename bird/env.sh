#!/bin/sh

# Generates ${FILE_ENV} from environment variables, then runs the given command (supervisord by default).
# BIRD_ASN - local AS number (default: 65000)
# BIRD_IP - router ID in IPv4 address format (default: 1.2.3.4)

FILE_ENV="/etc/bird/env.conf"

BIRD_ASN="${BIRD_ASN:-65000}"
BIRD_IP="${BIRD_IP:-1.2.3.4}"

# 1 to 4294967295, no leading zeros
case "${BIRD_ASN}" in
	''|0*|*[!0-9]*)
		echo "Error: BIRD_ASN=${BIRD_ASN} is not a valid AS number. Exiting."
		exit 1
		;;
esac
if [ "${#BIRD_ASN}" -gt 10 ] || { [ "${#BIRD_ASN}" -eq 10 ] && [ "${BIRD_ASN}" \> "4294967295" ]; }; then
	echo "Error: BIRD_ASN=${BIRD_ASN} is not a valid AS number. Exiting."
	exit 1
fi

# Four dot-separated numbers 0 to 255
case "${BIRD_IP}" in
	*[!0-9.]*|*.*.*.*.*|.*|*.|*..*)
		echo "Error: BIRD_IP=${BIRD_IP} is not a valid router ID. Exiting."
		exit 1
		;;
esac
IFS="." read -r A B C D <<-EOF
${BIRD_IP}
EOF
for OCTET in "${A}" "${B}" "${C}" "${D}"; do
	if [ -z "${OCTET}" ] || [ "${#OCTET}" -gt 3 ] || [ "${OCTET}" -gt 255 ]; then
		echo "Error: BIRD_IP=${BIRD_IP} is not a valid router ID. Exiting."
		exit 1
	fi
done

cat <<-EOF > "${FILE_ENV}"
define asn_bird = ${BIRD_ASN};
define ip4_bird = ${BIRD_IP};
EOF

exec "$@"
