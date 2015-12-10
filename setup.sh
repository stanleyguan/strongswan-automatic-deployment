#!/bin/sh

version='5.3.5' # strongSwan version

RED='\033[0;31m'
BLUE='\033[0;34m'
GREEN='\033[0;32m'
GRAY='\033[0;37m'
NC='\033[0m'

echo ""
echo "${BLUE}strongSwan $version VPN (IKEv1/v2) deployment for Ubuntu 14.04"
echo "${BLUE}For operation with iOS 9 and Mac OS X 10.11 (El Capitan)"
echo ""

echo "${RED}Enter domain name of server:${NC}"
read domain
echo ""
echo "${RED}Username for VPN:${NC}"
read username
echo ""
echo "${RED}Password for ${NC}$username${RED}:${NC}"
read password
echo ""

echo "${RED}Please review config."
echo "${RED}Do you wish to continue? (y/n)${NC}"
while true; do
  read -p "" yn
  case $yn in
      [Yy]* ) break;;
      [Nn]* ) exit 0;;
      * ) echo "Please answer with y/n.";;
  esac
done

echo ""
echo "${BLUE}Installing compiler dependencies...${GRAY}"
apt-get update -y
apt-get install build-essential -y
aptitude install libgmp10 libgmp3-dev libssl-dev pkg-config libpcsclite-dev libpam0g-dev -y

echo ""
echo "${BLUE}Downloading strongSwan 5.3.5...${GRAY}"
wget "http://download.strongswan.org/strongswan-$version.tar.bz2"

echo "${BLUE}Unpacking...${GRAY}"
tar -jxf "strongswan-$version.tar.bz2" && cd "strongswan-$version"

echo "${BLUE}Configuring source...${GRAY}"
./configure --prefix=/usr --sysconfdir=/etc  --enable-openssl --enable-nat-transport --disable-mysql --disable-ldap  --disable-static --enable-shared --enable-md4 --enable-eap-mschapv2 --enable-eap-aka --enable-eap-aka-3gpp2  --enable-eap-gtc --enable-eap-identity --enable-eap-md5 --enable-eap-peap --enable-eap-radius --enable-eap-sim --enable-eap-sim-file --enable-eap-simaka-pseudonym --enable-eap-simaka-reauth --enable-eap-simaka-sql --enable-eap-tls --enable-eap-tnc --enable-eap-ttls

echo "${BLUE}Compiling...${GRAY}"
make && make install

echo ""
echo "${BLUE}Generating certificates...${GRAY}"
# CA cert
ipsec pki --gen --outform pem > caKey.pem
ipsec pki --self --in caKey.pem --dn "C=CH, O=strongSwan, CN=strongSwan CA" --ca --outform pem > caCert.pem

# Server cert
ipsec pki --gen --outform pem > serverKey.pem
ipsec pki --pub --in serverKey.pem | ipsec pki --issue --cacert caCert.pem --cakey caKey.pem \
          --dn "C=CH, O=strongSwan, CN=$domain" --san="$domain" \
          --flag serverAuth --flag ikeIntermediate --outform pem > serverCert.pem

# Client cert
ipsec pki --gen --outform pem > clientKey.pem
ipsec pki --pub --in clientKey.pem | ipsec pki --issue --cacert caCert.pem --cakey caKey.pem \
          --dn "C=CH, O=strongSwan, CN=$domain" --outform pem > clientCert.pem

# PKCS#12 file
openssl pkcs12 -export -inkey clientKey.pem -in clientCert.pem -name "$domain" \
               -certfile caCert.pem -caname "strongSwan CA" -out clientCert.p12 -password pass:"$password"

echo "${BLUE}Installing certificates...${GRAY}"
cp caCert.pem /etc/ipsec.d/cacerts/
cp serverCert.pem /etc/ipsec.d/certs/
cp serverKey.pem /etc/ipsec.d/private/

cp clientCert.pem /etc/ipsec.d/certs/
cp clientCert.p12 /etc/ipsec.d/certs/
cp clientKey.pem /etc/ipsec.d/private/

echo "${BLUE}Configuring iptables...${GRAY}"
iptables -A INPUT -p udp --dport 500 -j ACCEPT
iptables -A INPUT -p udp --dport 4500 -j ACCEPT
echo 1 > /proc/sys/net/ipv4/ip_forward
iptables -t nat -A POSTROUTING -s 10.97.97.0/24 -o eth0 -j MASQUERADE
iptables -A FORWARD -s 10.97.97.0/24 -j ACCEPT

cat > /etc/rc.local <<EOF
#!/bin/sh -e
#
# rc.local
#
# This script is executed at the end of each multiuser runlevel.
# Make sure that the script will "exit 0" on success or any other
# value on error.
#
# In order to enable or disable this script just change the execution
# bits.
#
# By default this script does nothing.

# VPN config
iptables -A INPUT -p udp --dport 500 -j ACCEPT
iptables -A INPUT -p udp --dport 4500 -j ACCEPT
echo 1 > /proc/sys/net/ipv4/ip_forward
iptables -t nat -A POSTROUTING -s 10.97.97.0/24 -o eth0 -j MASQUERADE
iptables -A FORWARD -s 10.97.97.0/24 -j ACCEPT
ipsec start

exit 0
EOF

echo "${BLUE}Configuring strongSwan...${GRAY}"
cat > /etc/ipsec.secrets <<EOF
# /etc/ipsec.secrets
: RSA serverKey.pem
$username : XAUTH "$password"
$username : EAP "$password"
EOF

cat > /etc/strongswan.conf <<EOF
# /etc/strongswan.conf - strongSwan configuration file
#
# Refer to the strongswan.conf(5) manpage for details
#
# Configuration changes should be made in the included files

charon {
        load_modular = yes
        dns1 = 8.8.8.8
        plugins {
                include strongswan.d/charon/*.conf
        }
}

include strongswan.d/*.conf
EOF

cat > /etc/ipsec.conf <<EOF
# /etc/ipsec.conf - strongSwan IPsec configuration file

# basic configuration

config setup
        strictcrlpolicy=no
        uniqueids = no

# Add connections here.

conn ikev1
        keyexchange=ikev1
        authby=xauthrsasig
        xauth=server
        left=%defaultroute
        leftsubnet=0.0.0.0/0
        leftfirewall=yes
        leftcert=serverCert.pem
        right=%any
#        rightsubnet=10.0.0.0/24
        rightsourceip=10.97.97.0/24
        rightcert=clientCert.pem
        dpdaction=clear
        auto=add

conn ikev2
        keyexchange=ikev2
        ike=aes256-sha1-modp1024,aes128-sha1-modp1024,3des-sha1-modp1024!
        esp=aes256-sha256,aes256-sha1,3des-sha1!
        dpdaction=clear
        dpddelay=300s
        rekey=no
        left=%defaultroute
        leftsubnet=0.0.0.0/0
        leftauth=pubkey
        leftcert=serverCert.pem
        leftsendcert=always
        leftid=@$domain
        right=%any
        rightsourceip=10.97.97.0/24
        rightauth=eap-mschapv2
        #rightsendcert=never   # see note
        eap_identity=%any
        auto=add
EOF

echo "${BLUE}Starting strongSwan...${GRAY}"
ipsec start

echo "${BLUE}Removing temporary files...${GRAY}"
cd ..
rm -f "strongswan-$version.tar.bz2"
rm -rf "strongswan-$version"

echo ""
echo "${GREEN}Done. Please download and install the following certificates on your devices:"
echo "${GREEN}/etc/ipsec.d/cacerts/caCert.pem"
echo "${GREEN}/etc/ipsec.d/certs/clientCert.p12"
echo "${GREEN}For Amazon EC2, modify security group to allow inbound UDP on ports 500 and 4500.${NC}"
echo "${GREEN}Good luck.${NC}"
exit 0
