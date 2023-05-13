# strongswan-ikev2
Simple to deploy and use IKEv2 server.

Now using nftables.

To download and run use: `sudo docker run -it -p 500:500/udp -p 4500:4500/udp --cap-add=NET_ADMIN -v <directory for the CA cert>:/cacert/ altbrace/strongswan-ikev2:latest`
