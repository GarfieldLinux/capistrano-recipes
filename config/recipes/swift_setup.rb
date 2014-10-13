#for role:
# => swift-nginx

require_relative '../loadinfo/loadinfo_staging'

zone          =  0 
serverip      =  "0.0.0.0"
nginxip       = Servers['servers']['staging']['swift-nginx'][0]['ip']
proxyport     = SwiftInfo['proxyport']
memcacheport  = SwiftInfo['memcacheport']
accountport   = SwiftInfo['accountport']
containerport = SwiftInfo['containerport']
objectport    = SwiftInfo['objectport']

swift_hosts   = Servers["servers"]["staging"]["swift"]

smemcachedlist = " "
swift_hosts.each { |host|
    smemcachedlist = smemcachedlist + "#{host["ip"]}" +":"+memcacheport +","
}

#ring config file
ringString = "#!/bin/bash \\n cd /etc/swift \\n sudo chown -R swift:swift /etc/swift \\n" +
             "sudo rm -f *.builder *.ring.gz backups/*.builder backups/*.ring.gz \\n" +
             "sudo swift-ring-builder object.builder create 10 3 1 \\n" +
             "sudo swift-ring-builder container.builder create 10 3 1 \\n" +
             "sudo swift-ring-builder account.builder create 10 3 1 \\n  "
swift_hosts.each { |host|
zone=zone+1
ringString = ringString +"sudo swift-ring-builder object.builder add z#{zone}-#{host["ip"]}:6000/sdb1 100 \\n" +
                         "sudo swift-ring-builder container.builder add z#{zone}-#{host["ip"]}:6001/sdb1 100 \\n" +
                         "sudo swift-ring-builder account.builder add z#{zone}-#{host["ip"]}:6002/sdb1 100 \\n  "
}
ringString =ringString + "sudo swift-ring-builder object.builder \\n" +
"sudo swift-ring-builder container.builder  \\n" +
"sudo swift-ring-builder account.builder \\n" +
"sudo swift-ring-builder object.builder  rebalance \\n " +
"sudo swift-ring-builder container.builder  rebalance \\n" +
"sudo swift-ring-builder account.builder rebalance \\n"



namespace :swift do
    desc "install swift&proxy"
    task :setup do
        on roles(:storage) do
            if "#{deploy_to}".include? "fresh"
                memcachedlist = smemcachedlist.chop
                execute "sudo service memcached stop"
                execute "sudo service rsync stop"
                execute "sudo swift-init all stop"

				execute "sudo apt-get -y update"
				execute "sudo apt-get -y install curl gcc memcached rsync sqlite3 " +
						"xfsprogs git-core libffi-dev python-setuptools python-coverage " +
						"python-dev python-nose python-simplejson python-xattr " +
						"python-eventlet python-greenlet python-pastedeploy  " +
						"python-netifaces python-pip python-dnspython python-mock " +
						"swift python-swiftclient openssh-server swift-account " +
						"swift-container swift-object swift-object-expirer "
				execute "sudo mkdir -p /etc/swift"
				execute "sudo chown -R swift:swift /etc/swift/"
				execute "sudo  echo -e '[swift-hash] \\n \\n" +
						"swift_hash_path_prefix = `od -t x8 -N 8 -A n </dev/random` \\n" +
						"swift_hash_path_suffix = `od -t x8 -N 8 -A n </dev/random`\\n ' " +
						"> ~/swift.conf "
				execute "sudo cp ~/swift.conf /etc/swift/"
				execute "sudo mkdir -p /var/run/swift"
				execute "sudo chown swift:swift /var/run/swift"
				execute "sudo mkdir -p /var/cache/swift /srv/node/"
				execute "sudo chown swift:swift /var/cache/swift"
				execute "sudo chown swift:swift /srv/node"
        
				execute "sudo bash -c \"echo -e 'uid = swift\\n" +
						"gid = swift\\n" +
						"log file = /var/log/rsyncd.log\\n" +
						"pid file = /var/run/rsyncd.pid\\n" +
						"address = #{serverip}\\n\\n" +
						"[account] \\n" +
						"max connections = 25\\n" +
						"path = /srv/node/ \\n" +
						"read only = false \\n" +
						"lock file = /var/lock/account.lock\\n\\n" +
						"[container] \\n" +
						"max connections = 25\\n" +
						"path = /srv/node/ \\n" +
						"read only = false \\n" +
						"lock file = /var/lock/container.lock \\n\\n " +
						"[object]\\n" +
						"max connections = 25\\n" +
						"path = /srv/node/\\n" +
						"read only = false\\n" +
						"lock file = /var/lock/object.lock \\n\\n'" +
						"> /etc/rsyncd.conf\" "
				# or sudo perl -pi -e 's/address = 0.0.0.0/
				# address = #{serverip}/' /etc/rsyncd.conf 
				execute "sudo perl -pi -e 's/RSYNC_ENABLE=false/RSYNC_ENABLE=true/' /etc/default/rsync"
				execute "sudo service rsync start" 
				execute "sudo bash -c \"  echo -e '[DEFAULT]\\n" +
						"bind_ip = #{serverip} \\n" +
						"bind_port = #{accountport} \\n" +
						"workers = 2 \\n" +
						"[pipeline:main] \\n" +
						"pipeline = account-server \\n" +
						"[app:account-server] \\n" +
						"use = egg:swift#account \\n" +
						"[account-replicator] \\n" +
						"[account-auditor] \\n" +
						"[account-reaper]\\n'" +
						"> /etc/swift/account-server.conf \" "
				#or sudo perl -pi -e 's/bind_ip = 0.0.0.0/
				#   bind_ip = #{serverip}/'  /etc/swift/account-server.conf
				#   sudo perl -pi -e 's/bind_port = 10000/
				#   bind_port = #{accountport}/'  /etc/swift/account-server.conf
				execute "sudo bash -c \" echo -e '[DEFAULT]\\n" +
						"bind_ip = #{serverip} \\n" +
						"bind_port = #{containerport} \\n" +
						"workers = 2 \\n" +
						"[pipeline:main] \\n" +
						"pipeline = container-server \\n" +
						"[app:container-server] \\n" +
						"use = egg:swift#container \\n" +
						"[container-replicator] \\n" +
						"[container-updater] \\n" +
						"[container-auditor] \\n" +
						"[container-sync] \\n'" +
						"> /etc/swift/container-server.conf   \" "
				#or sudo perl -pi -e 's/bind_ip = 0.0.0.0/
				#   bind_ip = #{serverip}/' /etc/swift/container-server.conf 
				#   sudo perl -pi -e 's/bind_port = 10000/
				#   bind_port = #{containerport}/' /etc/swift/container-server.conf
				execute "sudo bash -c \" echo -e '[DEFAULT] \\n" +
						"bind_ip = #{serverip} \\n" +
						"bind_port = #{objectport} \\n" +
						"workers = 2 \\n" +
						"[pipeline:main] \\n" +
						"pipeline = object-server \\n" +
						"[app:object-server] \\n" +
						"use = egg:swift#object \\n" +
						"[object-replicator] \\n" +
						"[object-updater] \\n" +
						"[object-auditor] \\n'" +
						"> /etc/swift/object-server.conf   \" " 
				#or sudo perl -pi -e 's/bind_ip = 0.0.0.0/
				#   bind_ip = #{serverip}/' /etc/swift/object-server.conf 
				#   sudo perl -pi -e 's/bind_port = 10000/
				#   bind_port = #{objectport}/'  /etc/swift/object-server.conf 
				execute "sudo bash -c \" echo -e '[DEFAULT] \\n" +
						"[object-expirer] \\n" +
						"interval = 300 \\n" +
						"[pipeline:main] \\n" +
						"pipeline = catch_errors cache proxy-server \\n" +
						"[app:proxy-server] \\n" +
						"use = egg:swift#proxy \\n" +
						"[filter:cache] \\n" +
						"use = egg:swift#memcache \\n" +
						"memcache_servers = #{memcachedlist} \\n" +
						"[filter:catch_errors] \\n" +
						"use = egg:swift#catch_errors \\n'" +
						"> /etc/swift/object-expirer.conf  \" "
				#or sudo perl -pi -e 's/memcache_servers = 0.0.0.0/
				#   memcache_servers = #{memcahediplist}/' /etc/swift/object-expirer.conf
				execute "sudo apt-get -y install swift python-swiftclient openssh-server " +
						"rsync  swift-proxy memcached swift-account swift-container swift-object xfsprogs "
				execute "sudo perl -pi -e \"s/-l 127.0.0.1/-l #{serverip}/\" /etc/memcached.conf"
				execute "sudo perl -pi -e \"s/-p 11211/-p #{memcacheport}/\" /etc/memcached.conf"
				execute "sudo bash -c \" echo -e '[DEFAULT]\\n" +
						"bind_ip =  #{serverip} \\n" +
						"bind_port = #{proxyport} \\n" +
						"workers = 1 \\n" +
						"user = swift \\n" +
						"log_facility = LOG_LOCAL1 \\n" +
						"eventlet_debug = true \\n\\n" +
						"[pipeline:main] \\n" +
						"pipeline = catch_errors gatekeeper healthcheck " +
						"proxy-logging cache bulk tempurl slo dlo ratelimit crossdomain " +
						"tempauth staticweb container-quotas account-quotas " +
						"proxy-logging proxy-server \\n" +
						"[filter:catch_errors] \\n" +
						"use = egg:swift#catch_errors \\n" +
						"[filter:healthcheck] \\n" +
						"use = egg:swift#healthcheck \\n" +
						"[filter:proxy-logging] \\n" +
						"use = egg:swift#proxy_logging \\n" +
						"[filter:bulk] \\n" +
						"use = egg:swift#bulk \\n" +
						"[filter:ratelimit] \\n" +
						"use = egg:swift#ratelimit \\n" +
						"[filter:crossdomain] \\n" +
						"use = egg:swift#crossdomain \\n" +
						"[filter:dlo] \\n" +
						"use = egg:swift#dlo\\n" +
						"[filter:slo] \\n" +
						"use = egg:swift#slo \\n" +
						"[filter:tempurl] \\n" +
						"use = egg:swift#tempurl\\n" +
						"[filter:tempauth] \\n" +
						"use = egg:swift#tempauth \\n" +
						"user_admin_admin = admin .admin .reseller_admin \\n" +
						"user_newhire_newhire = newhirepwd .admin http://#{nginxip}/v1/AUTH_system \\n" +
						"user_heying_heying = ca\\$hc0w    .admin http://#{nginxip}/v1/AUTH_system \\n" +
						"user_test2_tester2 = testing2 .admin \\n" +
						"user_test_tester3 = testing3 \\n" +
						"#set the token_life time   default 86400\\n" + 
						"#token_life = 0\\n" +
						"[filter:staticweb] \\n" +
						"use = egg:swift#staticweb \\n" +
						"[filter:account-quotas] \\n" +
						"use = egg:swift#account_quotas \\n" +
						"[filter:container-quotas] \\n" +
						"use = egg:swift#container_quotas \\n" +
						"[filter:cache] \\n" +
						"use = egg:swift#memcache \\n" +
						"[filter:gatekeeper] \\n" +
						"use = egg:swift#gatekeeper \\n" +
						"[app:proxy-server] \\n" +
						"use = egg:swift#proxy \\n" +
						"allow_account_management = true \\n" +
						"account_autocreate = true \\n" +
						"[filter:cache] \\n" +
						"use = egg:swift#memcache \\n" +
						"memcache_servers = #{memcachedlist} " +
						"' > /etc/swift/proxy-server.conf  \" "
				#or sudo perl -pi -e 's/bind_ip =  0.0.0.0/
				#   bind_ip =  serverip/' /etc/swift/proxy-server.conf
				#   sudo perl -pi -e 's/user_test_tester = testing .admin 
				#   http://0.0.0.0/v1/AUTH_system/user_newhire_newhire = vmware_newhire .admin 
				#   http://nginxip/v1/AUTH_system/' /etc/swift/proxy-server.conf
				#   sudo perl -pi -e 's/memcache_servers = 0.0.0.0/
				#   memcache_servers = memcacheiplist/' /etc/swift/proxy-server.conf
				#
				#config ring file for every proxy node 
				execute "echo -e '#{ringString}' > /home/devops/ring.sh"
				execute "sudo chmod +x /home/devops/ring.sh"
				execute "/home/devops/ring.sh"
				execute "sudo chown -R swift:swift /etc/swift"
				execute "sudo service memcached start"
				execute "sudo service rsync start"
				execute "sudo swift-init all start"
			end
		end
	end
end
