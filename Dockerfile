FROM docker.io/freeipa/freeipa-server:fedora-34

COPY init-data /usr/local/sbin/init

# Enable debug
# COPY gssproxy.conf /data-template/etc/gssproxy/gssproxy.conf

VOLUME /data

ENTRYPOINT ["/usr/local/sbin/init"]
