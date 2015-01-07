# Clone from the RHEL 6
FROM rhel6

MAINTAINER Jan Pazdziora

# Install FreeIPA client
RUN yum install -y ipa-client perl && yum clean all

ADD ipa-client-configure-first /usr/sbin/ipa-client-configure-first

RUN chmod -v +x /usr/sbin/ipa-client-configure-first

ENTRYPOINT /usr/sbin/ipa-client-configure-first
