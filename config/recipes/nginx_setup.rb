#for role:
# => nginx
namespace :nginx do
    desc "install nginx"
    task :setup do
        on roles(:nginx) do
            sinatraweblist   = ""
            swiftserverlist  = ""
            proxyport        = SwiftInfo['proxyport']
            swift_nginx      = ""
            nginx            = ""
            if "#{deploy_to}".include? "production"
                root_path    = "production"
                sinatrawebp  = Servers['servers']['production']['sinatra']
                swift_hosts  = Servers["servers"]["production"]["swift"]
                swift_nginx  = Servers["servers"]["production"]["swift-nginx"][0]["ip"]
                nginx        = Servers["servers"]["production"]["nginx"][0]["ip"]
            elsif "#{deploy_to}".include? "staging"
                root_path    = "staging"
                sinatrawebp  = Servers['servers']['staging']['sinatra']
                swift_hosts  = Servers["servers"]["staging"]["swift"]
                swift_nginx  = Servers["servers"]["staging"]["swift-nginx"][0]["ip"]
                nginx        = Servers["servers"]["staging"]["nginx"][0]["ip"]
            else
                root_path = "webapp"
                execute "sudo apt-get -y install nginx"
                execute "sudo /etc/init.d/nginx stop"
            end

            sinatrawebp.each { |host|
                sinatraweblist = sinatraweblist+ "server " + "#{host["ip"]}" +":9292;\\n"
            }
            #swift_hosts.each { |host|
            #   swiftserverlist = swiftserverlist +"server "+ "#{host["ip"]}" +":#{proxyport};\\n"
            #}

            execute "echo -e ' #! /bin/bash \\n" +
            " DOMAIN=\"$1\" \\n" +
            "if [ -z \"$DOMAIN\" ]; then  \\n" +
            "echo \"Usage: $(basename $0) <domain>\"  \\n" +
            "exit 11  \\n" +
            "fi  \\n\\n" +
            "fail_if_error() { \\n" +
            "[ $1 != 0 ] && {  \\n" +
            "unset PASSPHRASE  \\n" +
            "exit 10  \\n" +
            "}  \\n" +
            "}  \\n" +
            "export PASSPHRASE=$(head -c 500 /dev/urandom | tr -dc a-z0-9A-Z | head -c 128; echo)  \\n" +
            "subj=\"  \\n" +
            "C=CN  \\n" +
            "ST=Shanghai  \\n" +
            "O=VMware  \\n" +
            "localityName=Shanghai  \\n" +
            "commonName=$DOMAIN  \\n" +
            "organizationalUnitName=IT  \\n" +
            "emailAddress=rogerluo410@gmail.com \"  \\n" +
            "echo \"Create ssl directory\" \\n" +
            "sudo mkdir -p /etc/nginx/ssl \\n" +
            "fail_if_error $? \\n" +
			"cd /etc/nginx/ssl \\n" +
			"fail_if_error $? \\n\\n" +
			"echo \"Generate the server private key\" \\n" +
			"openssl genrsa -des3 -out $DOMAIN.key -passout env:PASSPHRASE 2048 \\n" +
			"fail_if_error $? \\n\\n" +
			"echo \"Generate the CSR\" \\n" +
			"openssl req -new -subj \"$(echo -n \"$subj\" | tr \"\n\" \"/\" )\" -key $DOMAIN.key " +
            "-out $DOMAIN.csr -passin env:PASSPHRASE  \\n" +
			"fail_if_error $? \\n" +
			"sudo cp $DOMAIN.key $DOMAIN.key.org \\n" +
			"fail_if_error $? \\n\\n" +
			"echo \"Strip the password so we do not have to type it every time we restart Apache\" \\n" +
			"openssl rsa -in $DOMAIN.key.org -out $DOMAIN.key -passin env:PASSPHRASE \\n" +
			"fail_if_error $? \\n\\n" +
			"echo \"Generate the cert (good for 10 years)\" \\n" +
			"openssl x509 -req -days 3650 -in $DOMAIN.csr -signkey $DOMAIN.key -out $DOMAIN.crt \\n" +
			"fail_if_error $? \\n\\n" +
			"sudo rm server.key.org \\n" +
			"fail_if_error $? \\n" +
			"sudo rm server.csr \\n" +
			"fail_if_error $? \\n\\n" +
			"sudo chmod 0600 server.key \\n" +
			"fail_if_error $? \\n" +
			"sudo chmod 0600 server.crt \\n" +
			"fail_if_error $? \\n" +
            "return 0 \\n" +
			"\\n" +
            "' > ~/generate_ssl_cert.sh "
            execute "sudo chmod +x ~/generate_ssl_cert.sh" 
            execute "sudo ~/generate_ssl_cert.sh server"
            execute "sudo bash -c \"echo -e 'user www-data; \\n" +
            "worker_processes 4; \\n" +
            "pid /run/nginx.pid;\\n" +
            "events {\\n" +
            "worker_connections 768;\\n" +
            "}\\n" +
            "http {\\n" +
            "upstream webservers {\\n" + sinatraweblist +
            "}\\n" +
            #"upstream swiftservers{\\n" + swiftserverlist +
            #"}\\n" +
            "server {\\n" +
            "listen  443 default_server ssl; \\n" +
            "ssl on;" +
            "ssl_certificate   /etc/nginx/ssl/server.crt;" +
            "ssl_certificate_key /etc/nginx/ssl/server.key;" +
            "location =/ { \\n" +
            "root  /home/devops/#{root_path}/current/; \\n" +
            "index   index.html; \\n" +
            "} \\n" +
            "location ~ .*\\.(gif|jpg|jpeg|png|bmp|swf|js|html|htm|css)\$ { \\n" +
            "root  /home/devops/#{root_path}/current/; \\n" +
            "}\\n" +
            "server_name  webservers;\\n" +
            "location / {\\n" +
            "proxy_pass  http://webservers/;\\n" +
            "}\\n" +
            "location /auth/v1.0 {\\n" +
            "proxy_pass  http://\"#{swift_nginx}\";\\n" +
            "}\\n" +
            "location /v1 {\\n" +
            "proxy_pass  http://\"#{swift_nginx}\";\\n" +
            "}\\n" +
            #"location /auth {\\n" +
            #"proxy_pass http://swiftservers/;\\n"+
            #"}\\n" +
            "}\\n" +
            "server {\\n" +
            "listen 80;\\n" +
            "rewrite ^ https://\"#{nginx}\"$request_uri? permanent;\\n" +
            "}\\n" +
            "sendfile on;\\n" +
            "tcp_nopush on;\\n" +
            "tcp_nodelay on;\\n" +
            "keepalive_timeout 65;\\n" +
            "types_hash_max_size 2048;\\n" +
            "include /etc/nginx/mime.types;\\n" +
            "default_type application/octet-stream;\\n" +
            "access_log /var/log/nginx/access.log;\\n" +
            "error_log /var/log/nginx/error.log;\\n" +
            "gzip on;\\n" +
            "gzip_disable 'msie6';\\n" +
            "}\\n'  > /etc/nginx/nginx.conf \"  "

            if "#{deploy_to}".include? "production" or "#{deploy_to}".include? "staging"
                execute "sudo service nginx reload"
            else
                execute "sudo /etc/init.d/nginx start"
            end
        end
    end
end
