#!/bin/sh

# Cause the script to exit if errors are encountered
set -e
set -u

# Check if a modern version of ipset is installed. Abort if not.
if ! ipset -v 2>/dev/null | grep -qE 'v6|v7'; then
  logger -s -p user.info 'IPSet version on this router not supported. Requires v6 or above. Your version is:'$(ipset -v | sed -e 's/^/ /')
  echo; exit 1
fi

if [ ! -f /lib/modules/"$(uname -r)"/kernel/net/netfilter/ipset/ip_set_hash_ipmac.ko ]; then
  echo "[*] IPSet Extensions Not Supported - Please Update To Latest Firmware"
  echo; exit 1
fi

# We use iptables to prevent connecting to our set of IPs via WAN (so no connection if VPN down)

# Create a couple of ipsets. One for live use, one to build the set in and then swap it in to live.
# Swapping like this avoids any potential gap in protection as the set of IPs is built.
ipset create vpn-killswitch-ipset-live iphash
ipset create vpn-killswitch-ipset-swap iphash

# Create a custom chain
# We use a custom chain so that our rules don't get mixed up with any others.
# This makes updating them much safer.
iptables -N VPN_KILLSWITCH

# Block any traffic going to IPs in the live ipset that was trying to leave via the WAN (eth0)
iptables -A VPN_KILLSWITCH -m set --match-set vpn-killswitch-ipset-live dst -o eth0 -j REJECT --reject-with icmp-net-unreachable

# Add rule to return to the calling chain (the FORWARD chain)
iptables -A VPN_KILLSWITCH -j RETURN

# Add custom chain to the top of the FORWARD chain so the rules get executed early.
iptables -I FORWARD -j VPN_KILLSWITCH

# Setup custom rules
/jffs/scripts/vpn-director-hosts-update.sh

# Add crontab entry to refresh domain based rules every 12 hours
cru a vpn-director-hosts-update "0 */12 * * *" /jffs/scripts/vpn-director-hosts-update.sh
