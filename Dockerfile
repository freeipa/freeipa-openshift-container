ARG PARENT_IMG=docker.io/freeipa/freeipa-server:fedora-34
FROM ${PARENT_IMG}

# Just copy the ocp4 include shell file and parse the include list to 
# add it at the end
COPY ./init/ocp4.inc.sh /usr/local/share/ipa-container/ocp4.inc.sh
RUN sed -i 's/^#.\+includes:end/source \"\$\{INIT_DIR\}\/ocp4\.inc\.sh\"\n&./g' /usr/local/share/ipa-container/includes.inc.sh

# Prepare addons for data-template
# COPY ./data-template/lib/systemd/system /data-template/lib/systemd/system
# COPY ./volume-data-list /tmp/volume-data-list
# RUN rm -rf /lib/systemd/system \
#     && ln -svf /data/lib/systemd/system /lib/systemd/system \
#     && cat /tmp/volume-data-list >> /etc/volume-data-list

# COPY ./data-template/lib/systemd/system /data-template/lib/systemd/system
# RUN rm -rf /lib/systemd/system \
#     && ln -svf /data/lib/systemd/system /lib/systemd/system

# Enable debug
# COPY gssproxy.conf /data-template/etc/gssproxy/gssproxy.conf

ENTRYPOINT ["/usr/local/sbin/init"]
