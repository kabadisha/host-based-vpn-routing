# host-based-vpn-routing
Scripts for host-based vpn routing on Asus routers.

## Introduction
I'm a user of and a huge fan of the Merlin firmware for Asus routers. It rocks. I moved from DD-WRT a few years ago and haven't looked back, much simpler and just as powerful.

One of the new features recently is the VPN Director. This lets you more easily set policy rules for what traffic should route via your VPN and even has a 'kill switch' which prevents that traffic from leaking out via your normal WAN connection if the VPN dies, which is great. However, it has a few limitations:

### Kill switch limitations
1. The 'kill switch' only applies to rules where you have specified a local IP. If you leave that blank to create a rule that applies to all local IPs trying to reach a specific destination IP, when the VPN is disabled, these packets will flow over the WAN. Damn.
2. You can only specify a destination IP or range, not a hostname. This sucks because it would be nice to have a policy rule to send all traffic to netflix.com (for example) via the VPN, but have all other traffic flow out directly over the WAN as normal.
> :information_source: This limitation makes sense because the sub-systems that handle this kind of routing use IP addresses not hostnames. Additionally, IPs change so you'd have to somehow keep doing DNS lookups and updating the rules. Annoying though. I wonder if there is a workaround?...

### The solution

I've created a custom script that solves both problems by converting a list of hostnames to route via VPN into VPN Director policy rules as well as corresponding iptables rules to block traffic to those hosts routing via the WAN.

#### Prerequisites
1. You should have already successfully configured your VPN and set the 'Redirect Internet traffic through tunnel' setting to 'VPN Director (policy rules)' mode.
2. You should be familiar with using user scripts and be familiar enough with scripting to be able to make sense of my script below. Don't just copy/paste and hope you can trust me not to break your router.

#### Installation
The first script is the `firewall-start` script. This will run when the router boots, sets everything up and:

1. Creates a new custom iptables chain that we can put our rules in.
2. Adds that chain to the start of the built in FORWARD chain.
3. Executes the vpn_director_host_rules.sh script (below) in order to generate the rules for the hosts we want to route.
4. Adds that same script to the crontab so that it runs every 10 minutes. This is so that we can keep on top of IP address changes.

Add this script as `/jffs/scripts/firewall-start` and make it executable.

The `vpn_director_host_rules.sh` script is the meat of the operation. It has the list of hosts at the top which you can edit to include the hostnames you want to route to over the VPN and **ONLY** over the VPN.

You can read the code and the comments to see exactly how it does this, but in a nutshell:

1. It fetches the currently live list of rules and filters out the auto-generated rules from the last run to get a list of all the manually created rules in order to preserve them.
2. It then iterates over the list of hostnames, using nslookup to resolve the IPs for each and awk to do some filtering of the nslookup output.
3. For each IP, it:
	1. Generates a rule in the VPN Director format and adds it to a temporary VPN Director rules file.
	2. Generates a corresponding iptables rule that rejects any packets trying to leave for that IP over the WAN (this is the 'kill switch'). It adds each rule to the begining of the custom FORWARD iptables chain that we created earlier, pushing all the existing rules (from the last run) down the chain.
	3. Next it trims the old rules that have been pushed down the chain. This feels a bit of a 'clunky' way to do it, but this was the best way I could come up with without creating a small window where the rules were not in effect at each run. Flushing the table and then re-building it would be easier, but would have that side-effect.
	4. Diffs the newly created temporary VPN Director rules file with the existing one and replaces it only if there are any changes. This is done to avoid writing to the JFFS parition over and over, causing wear on the flash.

Add this script as `/jffs/scripts/vpn_director_host_rules.sh` and make it executable, then edit the list of hostnames near the top. Take care to respect the single quotes that wrap the whole list.

Reboot your router and you should be good to go!

#### Testing
To test, leave **whatismyipaddress.com** in your hostname list. If you visit that site when your VPN is up, you should see your external IP is that of your VPN provider. If you turn off the VPN client and try again, the page should fail to load.

You can manually run `/jffs/scripts/vpn_director_host_rules.sh` and see if it is spitting out any errors.

You can run `iptables -S CUSTOM_FORWARD` to see the list of iptables rules that the script has generated.

Enjoy!
