#!/bin/bash
org=${1}
host_system=${2}

[ -z "${org}" ] && org=libvirt.org
[ -z "${host_system}" ] && \
                   echo "Specify host address as a 2nd argument" && \
                   exit -1

host_name=$(ssh root@${host_system} hostname)

# 1. Create the Server Certificate Template
#
# The Name of your organization field should be adjusted to suit 
# your organization, and the Host Name field must be changed to 
# match the host name of the virtualisation host the template is for.

echo "organization = ${org}" > host_server_template.info
echo "cn = ${host_name}"    >> host_server_template.info
echo "tls_www_server"       >> host_server_template.info
echo "encryption_key"       >> host_server_template.info
echo "signing_key"          >> host_server_template.info

# 2. Create the Server Certificate Private Key files using certtool
#
# Generate the private key files, to be used with the 
# Server Certificates.
#
# These keys are used to create the TLS Server Certificates, and by
# each virtualisation host when the virtualisation system starts up.
#
# We create a unique private key per virtualisation host,
# also ensuring the permissions only allow very restricted access
# to these files

(umask 277 && certtool --generate-privkey > host_server_key.pem)

# NOTE - The security of these private key files is very important.
#
# If an unauthorised person obtains a server private key file,
# they could use it with a Server Certificate to impersonate one of
# your virtualisation hosts. Use good unix security to restrict access
# to the key files appropriately.

# --------------------------------------------------------------------
# 3. Combine the template files with the private key files,
#    to create the Server Certificate files

# We generate the Server Certificates using the template files, along
# with the corresponding private key files. Also, the Certificate
# Authority Certificate file is added along with its private key,
# to ensure each new server certificate is signed properly.

certtool --generate-certificate \
         --template host_server_template.info \
         --load-privkey host_server_key.pem \
         --load-ca-certificate certificate_authority_certificate.pem \
         --load-ca-privkey certificate_authority_key.pem \
         --outfile host_server_certificate.pem

# 4. Cleanup
rm host_server_template.info

# 5. Ownership, Permissions, and SELinux labels
ssh root@${host_system} "mkdir -pv /etc/pki/libvirt"
ssh root@${host_system} "chown root:qemu /etc/pki/libvirt"
ssh root@${host_system} "chmod 755 /etc/pki/libvirt"
#  SELinux label: system_u:object_r:cert_t:s0
ssh root@${host_system} "mkdir -pv /etc/pki/libvirt/private"
ssh root@${host_system} "chown root:qemu /etc/pki/libvirt/private"
ssh root@${host_system} "chmod 750 /etc/pki/libvirt/private"

scp host_server_certificate.pem root@${host_system}:servercert.pem
scp host_server_key.pem         root@${host_system}:serverkey.pem
ssh root@${host_system} "mv servercert.pem /etc/pki/libvirt/"
ssh root@${host_system} "mv serverkey.pem /etc/pki/libvirt/private/"
ssh root@${host_system} "chown root:qemu /etc/pki/libvirt/servercert.pem"
ssh root@${host_system} "chown root:qemu /etc/pki/libvirt/private/serverkey.pem"
ssh root@${host_system} "chmod 440 /etc/pki/libvirt/servercert.pem"
ssh root@${host_system} "chmod 440 /etc/pki/libvirt/private/serverkey.pem"
ssh root@${host_system} "restorecon -R /etc/pki/libvirt /etc/pki/libvirt/private"

# 6. Overriding the default locations
# If you need the Server Certificate file and its public key
# to be in a different location on the host, you can configure this
# in the /etc/libvirt/libvirtd.conf configuration file.

echo "cert_file = '/etc/pki/libvirt/servercert.pem'" > libvirtd.conf 
echo " key_file = '/etc/pki/libvirt/private/serverkey.pem'" >> libvirtd.conf

scp libvirtd.conf root@${host_system}:libvirtd.conf
ssh root@${host_system} "cat libvirtd.conf >> /etc/libvirt/libvirtd.conf"

