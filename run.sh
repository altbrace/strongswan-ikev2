#!/bin/bash

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
        --dn "CN=$external_ip" --san @$external_ip --san $external_ip \
        --flag serverAuth --flag ikeIntermediate --outform pem \
    >  ./pki/certs/server-cert.pem

    echo -e "Certificates generated in ./pki/\n"

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
    leftid=$external_ip
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

mkdir /cacert
cp ./pki/cacerts/ca-cert.pem /cacert/

/usr/sbin/ipsec start --nofork