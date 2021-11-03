#! /bin/bash

### This script sets up the ubuntu server for keycloak ###
### It uses nginx for ssl offloading of the keycloak traffic ###
### 
###
### 1. Initial setup - package installations
### 2. Install keycloak as a docker container
### 3. Generating the certificates for NGINX configuration
### 4. NGINX Configuration file
### 5. Setting up NGINX
###

# Initial Setup


sudo apt-get -y update
sudo apt-get install apt-transport-https ca-certificates curl software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
sudo apt-get -y update
sudo apt-get -y install docker-ce
sudo systemctl start docker
sudo systemctl enable docker
sudo groupadd docker
#sudo curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
#sudo chmod +x /usr/local/bin/docker-compose
wget -q --show-progress --https-only --timestamping \
  https://storage.googleapis.com/kubernetes-the-hard-way/cfssl/1.4.1/linux/cfssl \
  https://storage.googleapis.com/kubernetes-the-hard-way/cfssl/1.4.1/linux/cfssljson

chmod +x cfssl cfssljson
sudo mv cfssl cfssljson /usr/local/bin/

sudo apt-get -y install nginx

# Install keycloak as a docker container
sudo docker run -d -p 8080:8080 -e KEYCLOAK_USER=admin -e KEYCLOAK_PASSWORD=pass -e PROXY_ADDRESS_FORWARDING=true jboss/keycloak


echo $(pwd)

echo "Generating the  certificates for nginx configuration"


# Generating the certificates for NGINX configuration

{

cat > ca-config.json <<EOF
{
  "signing": {
    "default": {
      "expiry": "8760h"
    },
    "profiles": {
      "keycloak": {
        "usages": ["signing", "key encipherment", "server auth", "client auth"],
        "expiry": "8760h"
      }
    }
  }
}
EOF

cat > ca-csr.json <<EOF
{
  "CN": "keycloak",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "US",
      "L": "SF",
      "O": "Keycloak",
      "OU": "CA",
      "ST": "CA"
    }
  ]
}
EOF

cfssl gencert -initca ca-csr.json | cfssljson -bare ca

}


# Server certificate

{ 

cat > admin-csr.json <<EOF
{
  "CN": "admin",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "US",
      "L": "SF",
      "O": "cudase",
      "OU": "JWT demo",
      "ST": "CA"
    }
  ]
}
EOF

cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -hostname=keycloak.cudanet.com \
  -profile=keycloak \
  admin-csr.json | cfssljson -bare admin

}
ls -l

echo "moving admin certificates"
sudo cp admin-key.pem /etc/nginx/cert.key
sudo cp admin.pem /etc/nginx/cert.crt 

ls -l
# NGINX Configuration
{
cat > nginxconfig.conf << EOF
server {
    
    listen 80;
    listen 443 default ssl;
    server_name keycloak.cudanet.com;

    ssl_certificate           /etc/nginx/cert.crt;
    ssl_certificate_key       /etc/nginx/cert.key;

    ssl_session_cache  builtin:1000  shared:SSL:10m;
    ssl_protocols  TLSv1 TLSv1.1 TLSv1.2;
    ssl_ciphers HIGH:!aNULL:!eNULL:!EXPORT:!CAMELLIA:!DES:!MD5:!PSK:!RC4;
    ssl_prefer_server_ciphers on;

    access_log            /var/log/nginx/jenkins.access.log;

    location / {
      proxy_set_header        Host \$host;
      proxy_set_header        X-Real-IP \$remote_addr;
      proxy_set_header        X-Forwarded-For \$remote_addr;
      proxy_set_header        X-Forwarded-Proto \$scheme;

      # Fix the “It appears that your reverse proxy set up is broken" error.
      proxy_pass          http://localhost:8080;
      proxy_read_timeout  90;

      proxy_redirect      http://localhost:8080 https://keycloak.cudanet.com;
      
    }
  }
EOF
}
sudo cp nginxconfig.conf nginxconfig.conf.bak
sudo mv nginxconfig.conf /etc/nginx/sites-enabled/default
sudo systemctl enable nginx
sudo systemctl stop nginx
sudo systemctl start nginx