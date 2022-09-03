#!/bin/sh

# Cause the script to exit if errors are encountered
set -e
set -u

# Edit this list of rules (just be careful with the single quote at the beginning and end of the list):
RULES='
whatismyipaddress.com|OVPN1
www.whatismyip-address.com|OVPN2
whatismyipaddress.com|OVPN1
netflix.com|WAN'

# Create a new temp file with any rules manually created using the router's UI.
# When we edit the rules via the GUI, the rules file gets put on one line
# The sed command splits it on '<' chars not preceded by whitespace in order to split by line.
# The grep then excludes all the auto-generated rules.
# We use '|| true' to force the command result to be 0 even if no rows were found by
# grep (because there were no manually created rules).
sed 's:\(.\)<:\1\n<:g' /jffs/openvpn/vpndirector_rulelist | grep -v 'DNS-AUTO-' > /tmp/vpndirector_rulelist || true

# Print out any manual rules that were found (useful for debugging when running the script manually).
cat /tmp/vpndirector_rulelist

IPS=""
INDEX=1
for RULE in ${RULES}; do
  # ${RULE%-*} deletes the shortest substring of $RULE that matches the pattern -* starting
  # from the end of the string. ${RULE#*-} does the same, but with the *- pattern and starting
  # from the beginning of the string.
  HOST=${RULE%\|*}
  INTERFACE=${RULE#*\|}

  # Run nslookup for each host to get it's IP addresses, discarding the first two lines
  # and filter for lines with 'Address' in them. N.B. there is often more than one.
  # Then ditch any lines with a ':' in them, since those will be IPv6 results.
  # Then sort the results so that we get some consitency when checking for changes later.
  for IP in $(nslookup $HOST | awk '(NR>2) && /^Address/ {print $3}' | awk '!/:/' | sort); do
    echo '<1>DNS-AUTO-'$HOST'>>'$IP'>'$INTERFACE

    # If the rule was not directing to WAN, then add the IP to a list for later
    # when we create the corresponding iptables rules to act as the 'kill switch'
    # We don't want to add rules directing traffic to WAN added to the 'kill switch'
    if [ "$INTERFACE" != "WAN" ]; then
      IPS="${IPS} ${IP}"
    fi

    # Add an entry to VPN Director rules temporary file:
    # Rule example:
    # #<1>WhatIsMyIP>>104.16.154.36>OVPN1
    echo '<1>DNS-AUTO-'$HOST'>>'$IP'>'$INTERFACE >> /tmp/vpndirector_rulelist

    let INDEX=$INDEX+1
  done
done

let RULE_COUNT=$INDEX-1

# Compare the new rule list with the old one and see if anything has changed.
# This saves on writes to jffs and reduces wear on the flash drive.
if ! diff /tmp/vpndirector_rulelist /jffs/openvpn/vpndirector_rulelist >/dev/null; then
  logger -s -p user.info 'New changes to VPN Director policies detected, writing to jffs...'

  # We first flush any previous IPs from the swap ipset
  ipset flush vpn-killswitch-ipset-swap

  echo 'Updating vpn-only-ipset-swap ipset...'
  for IP in ${IPS}; do
    # N.B. We don't just add using the hostname since the ipset command would
    # only add the first IP if more than one applies to a host. We want them all.
    # The -exist flag avoids us having to test if each IP already exists in the set.
    ipset add vpn-killswitch-ipset-swap $IP -exist
  done

  echo 'Swapping in the ipset to live. IPs are:'
  ipset list vpn-killswitch-ipset-swap
  ipset swap vpn-killswitch-ipset-swap vpn-killswitch-ipset-live

  # We flush the swap ipset to save a bit of memory now we've finished with it.
  ipset flush vpn-killswitch-ipset-swap

  echo 'Restarting VPN routing to apply new rules...'
  date >> /tmp/vpn_rules_update_audit.log
  cp /tmp/vpndirector_rulelist /jffs/openvpn/vpndirector_rulelist
  # Restart VPN routing in order to refresh rules:
  service restart_vpnrouting

else
  echo 'No changes to VPN Director policies since last run. Nothing to update.'
fi
