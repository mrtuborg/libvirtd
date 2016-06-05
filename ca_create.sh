#!/bin/bash
# Instructions: http://wiki.libvirt.org/page/TLSCreateCACert

host_system=${1}
org=${2}

[ -z "${host_system}" ] && echo "Please specify server host as a 1st argument" && exit -1

# 1. Create a Certificate Authority Template
[ -z "${org}" ] && org=libvirt.org
echo "cn = ${org}          " >  certificate_authority_template.info
echo "ca                   " >> certificate_authority_template.info
echo "cert_signing_key     " >> certificate_authority_template.info
echo "expiration_days = 365" >> certificate_authority_template.info 

# 2. Create a Certificate Authority Private Key file using certtool
#
#    Generate a private key, to be used with the 
#    Certificate Authority Certificate.
#
#    This key is used create your Certificate Authority Certificate,
#    and to sign the individual client and server TLS certificates.
(umask 277 && \
 certtool --generate-privkey > certificate_authority_key.pem)
# NOTE - The security of this private key is extremely important.
#
# If an unauthorised person obtains this key, it can be used with the
# CA certificate to sign any other certificate, including certificates
# they generate. Such bogus certificates could potentially allow them
# to perform administrative commands on your virtualized guests.


# 3. Combine the template file with the private key file
#    to create the Certificate Authority Certificate file
#
#    Generate the CA Certificate using the template file,
#    along with the CA private key:
certtool --generate-self-signed \
         --template certificate_authority_template.info \
         --load-privkey certificate_authority_key.pem \
         --outfile certificate_authority_certificate.pem

# This file is not as security sensitive as the private key file.
# It will be copied to each virtualisation host and administrative
# computer later in the TLS setup process.

# 4. Cleanup
rm certificate_authority_template.info

# 5. Transferring the certificate and setting it up on host_system
if [ -n "${host_system}" ]; then
        cat ~/.ssh/id_rsa.pub | ssh root@${host_system}  \
					'umask 0077; mkdir -p .ssh; cat >> .ssh/authorized_keys && echo "Key copied"'

	scp -p certificate_authority_certificate.pem \
	       root@${host_system}:cacert.pem

        ssh root@${host_system} "mkdir -pv /etc/pki/CA/private"
	ssh root@${host_system} "mv cacert.pem /etc/pki/CA"
        ssh root@${host_system} "chmod 444 /etc/pki/CA/cacert.pem"
	ssh root@${host_system} "restorecon /etc/pki/CA/cacert.pem"
fi

# 6. Transferring the files to the administrative desktop
sudo mkdir -pv /etc/pki/CA/private

sudo cp certificate_authority_certificate.pem /etc/pki/CA/cacert.pem
sudo chmod 444 /etc/pki/CA/cacert.pem
sudo restorecon /etc/pki/CA/cacert.pem

sudo cp certificate_authority_key.pem /etc/pki/CA/private/cakey.pem
sudo chmod 400 /etc/pki/CA/private/cakey.pem
sudo restorecon /etc/pki/CA/private/cakey.pem

