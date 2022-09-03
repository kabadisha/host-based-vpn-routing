# host-based-vpn-routing
Scripts for host-based vpn routing on Asus routers.

## Introduction
I'm a user of and a huge fan of the Merlin firmware for Asus routers. It rocks. I moved from DD-WRT a few years ago and haven't looked back, much simpler and just as powerful.

One of the new features recently is the VPN Director. This lets you more easily set policy rules for what traffic should route via your VPN and even has a 'kill switch' which prevents that traffic from leaking out via your normal WAN connection if the VPN dies, which is great. However, it has a few limitations:

### Merlin's built in 'kill switch' has limitations
1. The 'kill switch' only applies to rules where you have specified a local IP. If you leave that blank to create a rule that applies to all local IPs trying to reach a specific destination IP, when the VPN is disabled, these packets will flow over the WAN. Damn.
2. You can only specify a destination IP or range, not a hostname. This sucks because it would be nice to have a policy rule to send all traffic to netflix.com (for example) via the VPN, but have all other traffic flow out directly over the WAN as normal.
	> :information_source: This limitation makes sense because the sub-systems that handle this kind of routing use IP addresses not hostnames. Additionally, IPs change so you'd have to somehow keep doing DNS lookups and updating the rules. Annoying though. I wonder if there is a workaround?...

### The solution

I've created a set of custom scripts that solves both problems by converting a list of hostnames to route via VPN into VPN Director policy rules as well as corresponding iptables rules to block traffic to those hosts routing via the WAN.

### Limitations
Some domains (like netflix.com) use DNS based load-balancing and so return different IPs each time you do a lookup.
This means that nslookup always gets different IPs and so the script will always think that IPs have changed.
It also means that clients will often be provided an IP that is not the one the script got and so that traffic would slip past the checks and escape over the WAN :-(

I've tried to find a workaround for this, but sadly, I don't think there is one. Providers like Netflix use huge IP ranges that change often. We don't have a reliable way to get all of them at any time.
As such, I think it's better to only use this script to direct specific traffic to smaller providers over the VPN, rather than send all traffic over the VPN and then add WAN exceptions.
Basically, don't add hosts (like netflix.com) that have this issue.

I've also changed the cron job to update the rules run only once every 12 hours to reduce writes to JFFS.

#### Prerequisites
1. You should have already successfully configured your VPN and set the 'Redirect Internet traffic through tunnel' setting to 'VPN Director (policy rules)' mode.
2. You should be familiar with using user scripts and be familiar enough with scripting to be able to make sense of my script below. Don't just copy/paste and hope you can trust me not to break your router.

#### Installation
The first script is the `vpn-director-hosts-setup.sh` script. This will run when the router boots, sets everything up and:

1. Create a couple of ipsets. One for live use, one to build the set in and then swap it in to live.
2. Creates a new custom iptables chain called `VPN_KILLSWITCH` that we can put our rules in.
3. Adds a rule in that chain to block any traffic going to IPs in the live ipset that was trying to leave via the WAN (eth0).
4. Add rule to return to the calling chain (the FORWARD chain)
5. Adds the `VPN_KILLSWITCH` chain to the start of the built in FORWARD chain.
6. Executes the `vpn-director-hosts-update.sh` script (below) in order to generate the rules for the hosts we want to route.
7. Adds that same script to the crontab so that it runs every 10 minutes. This is so that we can keep on top of IP address changes.

Add this script as `/jffs/scripts/vpn-director-hosts-setup.sh` and make it executable.

Add these two lines to `/jffs/scripts/firewall-start`:
```bash
# Setup VPN Director Hosts funcationality
/jffs/scripts/vpn-director-hosts-setup.sh
```
The `vpn-director-hosts-setup.sh` script is the meat of the operation. It has the list of hosts at the top which you can edit to include the hostnames you want to route to over the VPN and **ONLY** over the VPN.

You can read the code and the comments to see exactly how it does this, but in a nutshell:
1. It fetches the currently live list of rules and filters out the auto-generated rules from the last run to get a list of all the rules manually created through the router's UI in order to preserve them.
2. It then iterates over the list of hostnames, using nslookup to resolve the IPs for each and awk to do some filtering of the nslookup output.
3. For each IP, it:
	1. Generates a rule in the VPN Director format and adds it to a temporary VPN Director rules file and adds that IP to a list of those that should be included in the 'kill switch' ipset.
	2. Diffs the newly created temporary VPN Director rules file with the existing one to see if any changes to IPs actually happened since the script last ran. This is done to avoid writing to the JFFS parition over and over, causing wear on the flash.
	3. If there were changes then:
		1. The new VPN Director rules file is written.
		2. The ipset for the 'kill switch' is updated.
		3. The VPN routing is restarted to apply the changed.

Add this script as `/jffs/scripts/vpn-director-hosts-setup.sh` and make it executable, then edit the list of hostnames near the top. Take care to respect the single quotes that wrap the whole list.

Reboot your router and you should be good to go!

#### Testing
To test, leave **whatismyipaddress.com|OVPN1** in your hostname list. If you visit that site when your VPN is up, you should see your external IP is that of your VPN provider. If you turn off the VPN client and try again, the page should fail to load.

You can manually run `/jffs/scripts/vpn-director-hosts-setup.sh` and see if it is spitting out any errors.

You can run `ipset list vpn-killswitch-ipset-live` to see the list of IPs the script has added to the 'kill switch'.

Enjoy!
