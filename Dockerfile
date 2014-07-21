# Clone from the RHEL 6
FROM rhel6

MAINTAINER Jan Pazdziora

# Install FreeIPA server
RUN yum install -y ipa-server bind bind-dyndb-ldap perl && yum clean all

ADD ipa-server-configure-first /usr/sbin/ipa-server-configure-first

RUN chmod -v +x /usr/sbin/ipa-server-configure-first

EXPOSE 53/udp 80 443 389 636 88 464 88/udp 464/udp 123/udp

ENTRYPOINT /usr/sbin/ipa-server-configure-first
