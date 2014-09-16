# Clone from the RHEL 6
FROM rhel6

MAINTAINER Jan Pazdziora

# Install FreeIPA server
RUN yum install -y ipa-server bind bind-dyndb-ldap perl && yum clean all

# We start dbus directly as dbus user, to avoid dropping capabilities
# which does not work in unprivileged container.
RUN sed -i 's/daemon --check/daemon --user "dbus -g root" --check/' /etc/init.d/messagebus

ADD ipa-server-configure-first /usr/sbin/ipa-server-configure-first

RUN chmod -v +x /usr/sbin/ipa-server-configure-first

EXPOSE 53/udp 53 80 443 389 636 88 464 88/udp 464/udp 123/udp 7389 9443 9444 9445

ENTRYPOINT /usr/sbin/ipa-server-configure-first
