FROM ubuntu:20.04

RUN apt-get update && apt-get install -y \
    strongswan \
    strongswan-pki \
    libcharon-extra-plugins \
    libcharon-extauth-plugins 

COPY ./run.sh /opt/run.sh
RUN chmod 755 /opt/run.sh

VOLUME /etc/ipsec.d/
VOLUME /etc/ipsec/

EXPOSE 500/udp 4500/udp

CMD /opt/run.sh
