# SPDX-License-Identifier: MIT
# Ubuntu 24.04 arm64 root filesystem for the Pixel 2 (walleye).
# Built with `docker build`, then exported and packed into an ext4 image by
# scripts/build-rootfs.sh. The official ubuntu:24.04 image is ubuntu-base
# plus a few Docker tweaks, and already has user `ubuntu` (uid 1000, sudo).
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        systemd systemd-sysv systemd-timesyncd systemd-resolved udev dbus kmod \
        openssh-server sudo \
        iproute2 iputils-ping netbase ca-certificates curl \
        network-manager dnsmasq-base wpasupplicant iw rfkill wireless-regdb \
        avahi-daemon libnss-mdns \
        e2fsprogs nano less htop usbutils \
        unattended-upgrades \
        rmtfs tqftpserv qrtr-tools \
        libyaml-0-2 libevent-2.1-7t64 libevent-pthreads-2.1-7t64 libyuv0 libtiff6 libdw1t64 libunwind8 \
        gstreamer1.0-tools gstreamer1.0-plugins-base gstreamer1.0-plugins-good gstreamer1.0-plugins-ugly \
        v4l-utils \
        libegl-mesa0 libgles2 libgbm1 mesa-libgallium kmscube mesa-utils-bin \
        alsa-utils \
    && rm -rf /var/lib/apt/lists/*

COPY overlay/ /

RUN chmod 600 /etc/NetworkManager/system-connections/*.nmconnection \
    && chmod 440 /etc/sudoers.d/ubuntu \
    && mkdir -p /vendor /var/log/journal \
    && systemctl enable usb-gadget.service vendor.service \
        ssh.service NetworkManager.service avahi-daemon.service \
        systemd-timesyncd.service systemd-resolved.service \
        serial-getty@ttyGS0.service \
    # Modem + wifi: Android vendor daemons on Ubuntu (see docs/log.md, P6).
    && systemctl enable android-logd.service android-env.service modem.service \
        android-daemon@rmt_storage.service android-daemon@tftp_server.service \
        android-daemon@pd-mapper.service cnss-daemon.service \
        pixel2-boot-successful.service pixel2-screen.service \
        pixel2-status-led.service \
        pixel2-charge-limit.service \
    # Mainline kernel (P8.3): units gated with ConditionKernelVersion.
    && systemctl enable pixel2-modem-fw.service diag-router.service \
        rmtfs.service tqftpserv.service \
        pixel2-wifi-mac.service pixel2-wifi-mac-record.service \
        pixel2-camera-tuning.service \
        pixel2-audio.service \
    # No keyboard and no VT kernel: the screen is drawn by pixel2-screen.
    && systemctl mask getty@tty1.service \
    # Host keys are generated on first boot (ssh.service drop-in).
    && rm -f /etc/ssh/ssh_host_* \
    # Fresh machine-id on first boot.
    && : > /etc/machine-id \
    && passwd -l ubuntu
