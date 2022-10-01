# set a hostname:
hostnamectl set-hostname your-new-hostname
systemctl reboot

# erase RSA in case it's needed:
ssh-keygen -R <host>

# look for name of Ethernet adapter
ip a
# for example the Ethernet adapter's name is eth0
vi /etc/sysconfig/network-scripts/ifcfg-eth0

# Server IP # 
# IMPORTANT: change to "none"
BOOTPROTO=none
# 2x for Control Plane and 3x for Worker Node
IPADDR=192.168.1.20
# Subnet #
PREFIX=24
# Set default gateway IP #
GATEWAY=192.168.1.1
# Set dns servers #
DNS1=8.8.8.8
DNS1=8.8.4.4

# restart to take effect
systemctl restart network