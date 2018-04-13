#!/bin/bash


if [ "$USER" != "root" ]; then
  echo "Run as root"
  exit;
fi


echo
echo "=== Requesting configuration data ==="
echo


read -p "C (Country) US: " C
C=${C:-'US'}

read -p "O (Organization) VPN Server: " O
O=${O:-'VPN Server'}

read -p "CN (Common name) VPN Server Root CA: " CN
CN=${CN:-'VPN Server Root CA'}

read -p "Domain (example: vpn.example.com): " DOMAIN
DOMAIN=${DOMAIN:-'vpn.example.com'}


function package_exists(){
  string=`dpkg-query -W -f='${Status}' $1 2>/dev/null`
  if [[ $string == "install ok installed" ]]; then
    echo "ok"
  else
    echo "no"
  fi
}


echo
echo "=== Check and install soft ==="
echo

if [[ "$( package_exists uuid-runtime )" == "no" ]]; then
  echo "Install uuid-runtime"
  sudo apt-get install -y uuid-runtime
fi


if [[ "$( package_exists sudo )" == "no" ]]; then
  echo "Install sudo"
  sudo apt-get install -y sudo
fi


if [[ "$( package_exists strongswan )" == "no" ]]; then
  echo "Install strongswan"
  sudo apt-get install -y strongswan
fi

if [[ "$( package_exists libcharon-extra-plugins )" == "no" ]]; then
  echo "Install libcharon-extra-plugins"
  sudo apt-get install -y libcharon-extra-plugins
fi

if [[ "$( package_exists moreutils )" == "no" ]]; then
  echo "Install moreutils"
  sudo apt-get install -y moreutils
fi

if [[ "$( package_exists iptables-persistent )" == "no" ]]; then
  echo "Install iptables-persistent"
  sudo apt-get install -y iptables-persistent
fi

echo
echo "=== Create Certificates ==="
echo


mkdir vpn-certs

cd vpn-certs


ipsec pki --gen --type rsa --size 4096 --outform pem > server-root-key.pem

chmod 600 server-root-key.pem

ipsec pki --self --ca --lifetime 3650 \
--in server-root-key.pem \
--type rsa --dn "C=$C, O=$O, CN=$CN" \
--outform pem > server-root-ca.pem

ipsec pki --gen --type rsa --size 4096 --outform pem > vpn-server-key.pem


ipsec pki --pub --in vpn-server-key.pem \
--type rsa | ipsec pki --issue --lifetime 1825 \
--cacert server-root-ca.pem \
--cakey server-root-key.pem \
--dn "C=$C, O=$O, CN=$DOMAIN" \
--san $DOMAIN \
--flag serverAuth --flag ikeIntermediate \
--outform pem > vpn-server-cert.pem


sudo cp vpn-server-cert.pem /etc/ipsec.d/certs/vpn-server-cert.pem
sudo cp vpn-server-key.pem /etc/ipsec.d/private/vpn-server-key.pem

sudo chown root /etc/ipsec.d/private/vpn-server-key.pem
sudo chgrp root /etc/ipsec.d/private/vpn-server-key.pem
sudo chmod 600 /etc/ipsec.d/private/vpn-server-key.pem


echo
echo "=== Copy config ==="
echo


echo "config setup
  charondebug=\"ike 1, knl 1, cfg 0\"
  uniqueids=no
conn ikev2-vpn
  auto=add
  compress=no
  type=tunnel
  keyexchange=ikev2
  fragmentation=yes
  forceencaps=yes
  ike=aes256-sha1-modp1024,3des-sha1-modp1024!
  esp=aes256-sha1,3des-sha1!
  dpdaction=clear
  dpddelay=300s
  rekey=no
  left=%any
  leftid=$DOMAIN
  leftcert=/etc/ipsec.d/certs/vpn-server-cert.pem
  leftsendcert=always
  leftsubnet=0.0.0.0/0
  right=%any
  rightid=%any
  rightauth=eap-mschapv2
  rightsourceip=10.10.10.0/24
  rightdns=8.8.8.8,8.8.4.4
  rightsendcert=never
  eap_identity=%identity
" > /etc/ipsec.conf

echo "$DOMAIN : RSA "/etc/ipsec.d/private/vpn-server-key.pem"
testuser %any% : EAP \"yoursecretpass321\"
testuser2 %any% : EAP \"yoursecretpass123\"
testuser3 %any% : EAP \"yoursecretpass987\"
" > /etc/ipsec.secrets

echo
echo "=== ipsec restart ==="
echo


ipsec restart

echo
echo "=== Setup iptables rules ==="
echo


sudo iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 22 -j ACCEPT

sudo iptables -A INPUT -i lo -j ACCEPT

sudo iptables -A INPUT -p udp --dport  500 -j ACCEPT
sudo iptables -A INPUT -p udp --dport 4500 -j ACCEPT

sudo iptables -A FORWARD --match policy --pol ipsec --dir in  --proto esp -s 10.10.10.10/24 -j ACCEPT
sudo iptables -A FORWARD --match policy --pol ipsec --dir out --proto esp -d 10.10.10.10/24 -j ACCEPT

sudo iptables -t nat -A POSTROUTING -s 10.10.10.10/24 -o eth0 -m policy --pol ipsec --dir out -j ACCEPT
sudo iptables -t nat -A POSTROUTING -s 10.10.10.10/24 -o eth0 -j MASQUERADE

sudo iptables -t mangle -A FORWARD --match policy --pol ipsec --dir in -s 10.10.10.10/24 -o eth0 -p tcp -m tcp --tcp-flags SYN,RST SYN -m tcpmss --mss 1361:1536 -j TCPMSS --set-mss 1360

echo
echo "=== Save iptables rules ==="
echo


sudo netfilter-persistent save
sudo netfilter-persistent reload


echo
echo "=== Edit sysctl ==="
echo


echo "
net.ipv4.ip_forward=1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.ip_no_pmtu_disc = 1
" >> /etc/sysctl.conf

sysctl -p

echo
echo "=== ipsec restart ==="
echo


ipsec restart


echo
echo "=== Make .mobileconfig for MacOS/iOS ==="
echo


BASE64=`cat server-root-ca.pem | base64`

echo "<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>PayloadDisplayName</key>
    <string>$O</string>
    <key>PayloadIdentifier</key>
    <string>$DOMAIN</string>
    <key>PayloadUUID</key>
    <string>$(uuidgen)</string>
    <key>PayloadType</key>
    <string>Configuration</string>
    <key>PayloadVersion</key>
    <integer>1</integer>
    <key>PayloadContent</key>
    <array>
        <dict>
            <key>PayloadIdentifier</key>
            <string>$DOMAIN</string>
            <key>PayloadUUID</key>
            <string>$(uuidgen)</string>
            <key>PayloadType</key>
            <string>com.apple.security.root</string>
            <key>PayloadVersion</key>
            <integer>1</integer>
            <key>PayloadContent</key>
            <data>
            $BASE64
            </data>
        </dict>
    </array>
</dict>
</plist>
" > vpn-unsigned.mobileconfig

openssl smime \
-sign \
-signer vpn-server-cert.pem \
-inkey vpn-server-key.pem \
-certfile vpn-server-cert.pem \
-nodetach \
-outform der \
-in vpn-unsigned.mobileconfig \
-out vpn-signed.mobileconfig

echo
echo "Use : vpn-signed.mobileconfig"
echo
