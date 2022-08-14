FROM ubuntu:20.04
ARG CA_CN
ARG EXT_IP


RUN apt-get update && apt-get install -y \
    strongswan \
    strongswan-pki \
    libcharon-extra-plugins \
    libcharon-extauth-plugins 

RUN mkdir ~/pki && \
    mkdir ~/pki/cacerts && \
    mkdir ~/pki/certs && \
    mkdir ~/pki/private

RUN pki --gen --type rsa --size 4096 --outform pem > ~/pki/private/ca-key.pem

RUN pki --self --ca --lifetime 3650 --in ~/pki/private/ca-key.pem \
    --type rsa --dn "CN=${CA_CN}" --outform pem > ~/pki/cacerts/ca-cert.pem

RUN pki --gen --type rsa --size 4096 --outform pem > ~/pki/private/server-key.pem

RUN pki --pub --in ~/pki/private/server-key.pem --type rsa \
    | pki --issue --lifetime 1825 \
        --cacert ~/pki/cacerts/ca-cert.pem \
        --cakey ~/pki/private/ca-key.pem \
        --dn "CN=${EXT_IP}" --san @${EXT_IP} --san ${EXT_IP} \
        --flag serverAuth --flag ikeIntermediate --outform pem \
    >  ~/pki/certs/server-cert.pem

RUN mkdir /output
RUN cp -r ~/pki/* /etc/ipsec.d/
RUN cp ~/pki/cacerts/ca-cert.pem /output/ca-cert.pem

ADD ipsec.conf /etc/ipsec.conf
ADD ipsec.secrets /etc/ipsec.secrets

EXPOSE 500/udp 4500/udp

ENTRYPOINT /usr/sbin/ipsec start --nofork
