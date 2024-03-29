#!/bin/bash

if [ -f /run/.run-flag ]; then
    echo -e "System is already configured. Starting...\n"
    echo -e "You can find your credentials in /etc/ipsec.secrets\n"
    /usr/sbin/ipsec start --nofork
fi
touch /run/.run-flag
read -p "Enter your external IP address: " external_ip
read -p "Do you want to generate CA and server certificates automatically? (Y/N): " generate_certs
if [[ $generate_certs == [yY] || $generate_certs == [yY][eE][sS] ]]
then
    if ! command -v pki &> /dev/null
    then
        echo -e "pki executable is not found. Please install 'strongswan-pki' first.\n"
        exit
    fi
    read -p "Enter CN (common name) of the CA certificate: " CA_CN
    read -p "Enter your domain name for the server certificate: " domain_name
    echo -e "Generating certificates...\n"

    mkdir -p ./pki/{cacerts,certs,private}
    chmod 700 ./pki
    pki --gen --type rsa --size 4096 --outform pem > ./pki/private/ca-key.pem

    pki --self --ca --lifetime 3650 --in ./pki/private/ca-key.pem \
    --type rsa --dn "CN=$CA_CN" --outform pem > ./pki/cacerts/ca-cert.pem

    pki --gen --type rsa --size 4096 --outform pem > ./pki/private/server-key.pem

    pki --pub --in ./pki/private/server-key.pem --type rsa \
    | pki --issue --lifetime 1825 \
        --cacert ./pki/cacerts/ca-cert.pem \
        --cakey ./pki/private/ca-key.pem \
        --dn "CN=$domain_name" --san @$external_ip --san $domain_name \
        --flag serverAuth --flag ikeIntermediate --outform pem \
    >  ./pki/certs/server-cert.pem

    echo -e "Certificates generated. Grab your 'ca-cert.pem' file in the current directory.\n\n"

fi

read -p "Enter your username (for VPN connection): " username
read -p "Enter your password (for VPN connection): " password
echo -e "Generating ipsec configs..."

mkdir ./ipsec
chmod 700 ./ipsec

echo "config setup
    charondebug="ike 1, knl 1, cfg 0"
    uniqueids=no

conn ikev2-vpn
    auto=add
    compress=no
    type=tunnel
    keyexchange=ikev2
    fragmentation=yes
    forceencaps=yes
    dpdaction=clear
    dpddelay=300s
    rekey=no
    left=%any
    leftid=$domain_name
    leftcert=server-cert.pem
    leftsendcert=always
    leftsubnet=0.0.0.0/0
    right=%any
    rightid=%any
    rightauth=eap-mschapv2
    rightsourceip=10.10.10.0/24
    rightdns=8.8.8.8,8.8.4.4
    rightsendcert=never
    eap_identity=%identity
    ike=chacha20poly1305-sha512-curve25519-prfsha512,aes256gcm16-sha384-prfsha384-ecp384,aes256-sha1-modp1024,aes128-sha1-modp1024,3des-sha1-modp1024!
    esp=chacha20poly1305-sha512,aes256gcm16-ecp384,aes256-sha256,aes256-sha1,3des-sha1!" > ./ipsec/ipsec.conf

echo -e ": RSA "server-key.pem"
$username : EAP \"$password\"" > ./ipsec/ipsec.secrets

cp -r ./pki/* /etc/ipsec.d/
cp ./ipsec/* /etc/

mkdir /cacert 2>/dev/null
cp ./pki/cacerts/ca-cert.pem /cacert/
echo -e "ipsec configs generated.\n"
NET_IFACE=$(route 2>/dev/null | grep -m 1 '^default' | grep -o '[^ ]*$')

sysctl -e -q -w net.ipv4.ip_forward=1 2>/dev/null
sysctl -e -q -w net/ipv4/conf/all/accept_redirects=0 2> /dev/null
sysctl -e -q -w net/ipv4/conf/all/send_redirects=0 2> /dev/null
sysctl -e -q -w net/ipv4/ip_no_pmtu_disc=1 2> /dev/null

# iptables -t nat -A POSTROUTING -s 10.10.10.0/24 -o "$NET_IFACE" --match policy --pol ipsec --dir out -j ACCEPT
# iptables -t nat -A POSTROUTING -s 10.10.10.0/24 -o "$NET_IFACE" -j MASQUERADE
# iptables -t mangle -A FORWARD --match policy --pol ipsec --dir in -s 10.10.10.0/24 -o "$NET_IFACE" -p tcp -m tcp --tcp-flags SYN,RST SYN -m tcpmss --mss 1361:1536 -j TCPMSS --set-mss 1360
# iptables -t filter -A FORWARD --match policy --pol ipsec --dir in --proto esp -s 10.10.10.0/24 -j ACCEPT
# iptables -t filter -A FORWARD --match policy --pol ipsec --dir out --proto esp -d 10.10.10.0/24 -j ACCEPT

nft flush ruleset

nft add table ip nat
nft add chain ip nat postrouting {type nat hook postrouting priority 100 \;}
nft add rule ip nat postrouting oif "$NET_IFACE" ipsec out ip saddr 10.10.10.0/24 accept
nft add rule ip nat postrouting ip saddr 10.10.10.0/24 oif "$NET_IFACE" masquerade

nft add table ip mangle
nft add chain ip mangle forward {type filter hook forward priority \ -150 \;}
nft add rule ip mangle forward oif "$NET_IFACE" ipsec in ip saddr 10.10.10.0/24 tcp flags \& \(syn\|rst\) \=\= syn tcp option maxseg size 1361-1536 tcp option maxseg size set 1360

nft add table ip filter
nft add chain ip filter forward {type filter hook forward priority 0 \;}
nft add rule ip filter forward ip protocol esp ip saddr 10.10.10.0/24 counter accept
nft add rule ip filter forward ip protocol esp ip daddr 10.10.10.0/24 counter accept

echo -e "nftables rules added. Starting up.\n\n"
/usr/sbin/ipsec start --nofork
