#!/bin/sh

# Cause the script to exit if errors are encountered
set -e
set -u

# Edit this list of rules (just be careful with the single quote at the beginning and end of the list):
RULES='
whatismyipaddress.com|OVPN1
netflix.com|WAN'

# Create a new temp file with any manually created rules
# When we edit the rules via the GUI, the rules file gets put on one line
# The sed command splits it on '<' chars not preceded by whitespace in order to split by line.
# The grep then excludes all the auto-generated rules.
# We use '|| true' to force the command result to be 0 even if no rows were found by
# grep (because there were no manually created rules).
sed 's:\(.\)<:\1\n<:g' /jffs/openvpn/vpndirector_rulelist | grep -v 'DNS-AUTO-' > /tmp/vpndirector_rulelist || true
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

    # Add the IP to a list for later when we create the corresponding iptables rules
    IPS="${IPS} ${IP}"

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
  date >> /tmp/vpn_rules_update_audit.log
  cp /tmp/vpndirector_rulelist /jffs/openvpn/vpndirector_rulelist

  # Restart VPN routing in order to refresh rules:
  service restart_vpnrouting0

  # Use iptables to prevent connecting to the IPs via WAN (so no connection if VPN down)
  # We insert all the rules at the start of the chain, then delete the old rules later.
  # This is a bit cumbersome, but iptables doesn't give you a neat way to check if a rule already exists.
  echo 'Creating iptables rules...'
  for IP in ${IPS}; do
    iptables -I CUSTOM_FORWARD 1 -d $IP -o eth0 -j REJECT --reject-with icmp-net-unreachable
  done

  # Add rule to return to the calling chain
  echo 'Inserting new iptables RETURN rule at position '$(($RULE_COUNT+1))
  iptables -I CUSTOM_FORWARD $(($RULE_COUNT+1)) -j RETURN

  let RULE_TO_REMOVE=$RULE_COUNT+2

  # Now we trim any old rules from the end of the chain.
  # N.B. As the chain shrinks with each one you remove, we don't need to increment the index.
  REMOVED_RULE_COUNT=0
  while iptables -D CUSTOM_FORWARD $RULE_TO_REMOVE 2> /dev/null; do
    let REMOVED_RULE_COUNT=$REMOVED_RULE_COUNT+1
  done
  echo 'Removed '$REMOVED_RULE_COUNT' old rules'

  else
    echo 'No changes to VPN Director policies since last run.'
fi
