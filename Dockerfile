FROM ubuntu:20.04

RUN apt-get update && apt-get install -y \
    strongswan \
    strongswan-pki \
    libcharon-extra-plugins \
    libcharon-extauth-plugins 

ADD run.sh ./run.sh

RUN ./run.sh

VOLUME /etc/ipsec.d/
VOLUME /etc/ipsec/

EXPOSE 500/udp 4500/udp

ENTRYPOINT /usr/sbin/ipsec start --nofork
