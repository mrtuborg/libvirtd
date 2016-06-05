#!/bin/bash
org=${2}
server_address=${1}

[ -z "${server_address}"  ] && \
              echo "Specify server_address as an 1st arg" && \
              exit -1

server_hostname=${server_address}
#$(ssh root@${host_system} hostname)
NET_IP=$(ifconfig ${NET_IF} 2>/dev/null | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1' | head -n 1)
client_hostname=${NET_IP}
#$(hostname)

[ -z "${org}" ] && org=libvirt.org

# 1. Create the Client Certificate Template files 
echo "country = AU"             > host_client_template.info
echo "state = Queensland"      >> host_client_template.info
echo "locality = Brisbane"     >> host_client_template.info
echo "organization = ${org}"   >> host_client_template.info
echo "cn = ${server_hostname}" >> host_client_template.info
echo "tls_www_client"          >> host_client_template.info
echo "encryption_key"          >> host_client_template.info
echo "signing_key"             >> host_client_template.info

echo "country = AU"             > admin_desktop_client_template.info
echo "state = Queensland"      >> admin_desktop_client_template.info
echo "locality = Brisbane"     >> admin_desktop_client_template.info
echo "organization = ${org}"   >> admin_desktop_client_template.info
echo "cn = ${client_hostname}" >> admin_desktop_client_template.info
echo "tls_www_client"          >> admin_desktop_client_template.info
echo "encryption_key"          >> admin_desktop_client_template.info
echo "signing_key"             >> admin_desktop_client_template.info

# 2. Create the Client Certificate Private Key files using certtool
#
# These keys are used to create the TLS Client Certificates, by each
# virtualisation host when the virtualisation system starts up, and
# by the administration desktop each time the virtualisation tools are used.
#
# We create a unique private key for each client, also ensuring
# the permissions only allow very restricted access to these files:
#

(umask 277 && certtool --generate-privkey > host_client_key.pem)
(umask 277 && certtool --generate-privkey > admin_desktop_client_key.pem)

# NOTE - The security of these private key files is very important.
#
# If an unauthorised person obtains one of these private key files,
# they could use it with a Client Certificate to impersonate one of your
# virtualisation clients. Depending upon your host configuration, they
# may then be able to perform administrative commands on your host servers. # Use good unix security to restrict access to the key files appropriately.
#
#--------------------------------------------------------------------------
# 3. Combine the template files with the private key files,
#    to create the Client Certificates

# We generate Client Certificates using the template files, along
# with the corresponding private key files. Also, the Certificate Authority
# Certificate file is added with its private key, to ensure each new client
# certificate is signed properly.
#
# For our two virtualisation hosts and the admin desktop, this means:

certtool --generate-certificate \
         --template host_client_template.info \
         --load-privkey host_client_key.pem \
         --load-ca-certificate certificate_authority_certificate.pem \
         --load-ca-privkey certificate_authority_key.pem \
         --outfile host_client_certificate.pem

# Make a note of the highlighted contents of the Subject field
# in the output. This is the Distinguished Name of the client.
# It is used in an optional final part of TLS configuration, where access
# is restricted to only specific clients.
# So keep a copy of it around until then.

# In addition to the displayed output, the certtool command will have
# created the file host_client_certificate.pem.

# We do the same thing for the administrative desktop,
# after adjusting the input and output files names:

certtool --generate-certificate \
         --template admin_desktop_client_template.info \
         --load-privkey admin_desktop_client_key.pem \
         --load-ca-certificate certificate_authority_certificate.pem \
         --load-ca-privkey certificate_authority_key.pem \
         --outfile admin_desktop_client_certificate.pem

# 4. Cleanup
rm host_client_template.info admin_desktop_client_template.info

# 5. Moving the Certificates into place
scp -p host_client_certificate.pem root@${server_address}:clientcert.pem
scp -p host_client_key.pem root@${server_address}:clientkey.pem

ssh root@${server_address} "mv clientcert.pem /etc/pki/libvirt/"
ssh root@${server_address} "chown root:root /etc/pki/libvirt/clientcert.pem"
ssh root@${server_address} "chmod 400 /etc/pki/libvirt/clientcert.pem"

ssh root@${server_address} "mv clientkey.pem /etc/pki/libvirt/private/"
ssh root@${server_address} "chown root:root /etc/pki/libvirt/private/clientkey.pem"
ssh root@${server_address} "chmod 400 /etc/pki/libvirt/private/clientkey.pem"
ssh root@${server_address} "restorecon /etc/pki/libvirt/clientcert.pem /etc/pki/libvirt/private/clientkey.pem"


#echo "cert_file = '/etc/pki/libvirt/clientcert.pem'" > libvirtd.conf
#echo " key_file = '/etc/pki/libvirt/private/clientkey.pem'" >> libvirtd.conf

sudo mkdir -pv /etc/pki/libvirt/private
sudo mv admin_desktop_client_certificate.pem   /etc/pki/libvirt/clientcert.pem
sudo chmod 444 /etc/pki/libvirt/clientcert.pem
sudo restorecon /etc/pki/libvirt/clientcert.pem

sudo mv admin_desktop_client_key.pem           /etc/pki/libvirt/private/clientkey.pem
sudo chmod 400 /etc/pki/libvirt/private/clientkey.pem
sudo restorecon /etc/pki/libvirt/private/clientkey.pem

#sudo mv libvirtd.conf /etc/libvirt/libvirtd.conf
#sudo restorecon /etc/libvirt/libvirtd.conf

