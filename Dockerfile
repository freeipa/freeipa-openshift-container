FROM docker.io/freeipa/freeipa-server:fedora-34

# COPY init-data /usr/local/sbin/init
RUN mkdir -p /usr/local/share/ipa-container
COPY init/ /usr/local/share/ipa-container
RUN rm -vf /usr/local/sbin/init \
    && ln -svf /usr/local/share/ipa-container/init.sh /usr/local/sbin/init

# Enable debug
# COPY gssproxy.conf /data-template/etc/gssproxy/gssproxy.conf

VOLUME /data

ENTRYPOINT ["/usr/local/sbin/init"]
