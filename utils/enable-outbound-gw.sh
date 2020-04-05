#!/bin/bash

# This script configure a CentOS 7 Linux box as Outbound NAT Gateway (ONG)
# The ONG has two network interfaces:
# ens192 with IP 192.168.1.1/24 exposed to the esternal network and
# ens224 with IP 10.10.10.1/24 attached to the internal network.
# We want other clients attached to the internal network 10.10.10.0/24 to reach the external

# enable IP forwarding
sysctl -w net.ipv4.ip_forward=1

# start firewall
systemctl start firewalld

# enable NAT
firewall-cmd --zone=external --add-interface=ens192 --permanent
firewall-cmd --zone=internal --add-interface=ens224 --permanent
firewall-cmd --complete-reload
firewall-cmd --zone=external --add-masquerade --permanent
firewall-cmd --permanent --direct --passthrough ipv4 -t nat -I POSTROUTING -o ens192 -j MASQUERADE -s 10.10.10.0/24
firewall-cmd --permanent --zone=internal --add-service=dhcp
firewall-cmd --permanent --zone=internal --add-service=tftp
firewall-cmd --permanent --zone=internal --add-service=dns
firewall-cmd --permanent --zone=internal --add-service=http
firewall-cmd --permanent --zone=internal --add-service=ssh
firewall-cmd --permanent --zone=internal --add-port=8080/tcp
firewall-cmd --permanent --zone=internal --add-port=8081/tcp
firewall-cmd --complete-reload
