ARG PARENT_IMG=quay.io/freeipa/freeipa-server:fedora-35

# Ignore the rule because we are providing a customized parent image
# that is passed as a build argument
# hadolint ignore=DL3006
FROM ${PARENT_IMG}

# Just copy the ocp4 include shell file and parse the include list to 
# add it at the end
# COPY ./init/ocp4.inc.sh /usr/local/share/ipa-container/ocp4.inc.sh
# RUN sed -i 's/^#.\+includes:end/source \"\$\{INIT_DIR\}\/ocp4\.inc\.sh\"\n&./g' /usr/local/share/ipa-container/includes.inc.sh
RUN ( [ ! -e "/usr/local/share/ipa-container" ] \
      || rm -rf "/usr/local/share/ipa-container" ) \
    && ( [ ! -e /usr/local/sbin/init ] \
         || rm -f /usr/local/sbin/init ) \
    && ln -svf /usr/local/share/ipa-container/init.sh /usr/local/sbin/init
COPY ./init /usr/local/share/ipa-container
COPY ./tmpfiles.conf /usr/lib/tmpfiles.d/00-ipa-container.conf

# Completely replace systemd-tmpfiles.  This is needed until FreeIPA
# itself provides a way to select the tmpfiles implementation via
# the 'ipapython.paths' facility.
RUN mv /bin/systemd-tmpfiles /bin/systemd-tmpfiles.orig
COPY ./init/tmpfiles.py /bin/systemd-tmpfiles

ENTRYPOINT ["/usr/local/sbin/init"]

ARG QUAY_EXPIRATION=2w
ENV QUAY_EXPIRATION=$QUAY_EXPIRATION
LABEL quay.expires-after=$QUAY_EXPIRATION
