# Easy-VPN-IKEv2
Auto start vpn IKEv2 debian/ubuntu

Change, delete or add new users easily and don't forget change standart password `yoursecretpass321`

echo "$DOMAIN : RSA "/etc/ipsec.d/private/vpn-server-key.pem"
testuser %any% : EAP \"yoursecretpass321\"
testuser2 %any% : EAP \"yoursecretpass123\"
testuser3 %any% : EAP \"yoursecretpass987\"
" > /etc/ipsec.secrets
