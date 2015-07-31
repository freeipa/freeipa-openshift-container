# Clone from the Fedora 20 image
FROM fedora:20

MAINTAINER Jan Pazdziora

# Workaround 1248467
RUN mkdir -p /run/lock ; yum downgrade -y krb5-libs openssl-libs && yum clean all

# Install FreeIPA client
RUN yum install -y freeipa-client perl 'perl(Data::Dumper)' && yum clean all

ADD dbus.service /etc/systemd/system/dbus.service
RUN ln -sf dbus.service /etc/systemd/system/messagebus.service

ADD systemctl /usr/bin/systemctl
ADD ipa-client-configure-first /usr/sbin/ipa-client-configure-first

RUN chmod -v +x /usr/bin/systemctl /usr/sbin/ipa-client-configure-first

ENTRYPOINT /usr/sbin/ipa-client-configure-first
