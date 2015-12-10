# strongswan-automatic-deployment
Automatic deployment of strongSwan VPN (IKEv1/v2) on Ubuntu 14.04 (Trusty). Currently uses strongSwan 5.3.5.
Partially based on https://www.zeitgeist.se/2013/11/22/strongswan-howto-create-your-own-vpn/.

The script was tested on the following servers:

* DigitalOcean, Ubuntu 14.04
* Amazon EC2, Ubuntu 14.04

Interoperability with iOS 9 and OS X 10.11 (El Capitan) was tested.

For instructions on client side configuration, visit https://wiki.strongswan.org/projects/strongswan/wiki/IOS_(Apple).

To deploy, run
```
sudo sh setup.sh
```
