#!/bin/bash

source certificate.conf
set -e  # Exit the script when a command fails

function handle_error {
    echo "An error occurred: $1"
    exit 1
}

# Use trap to catch errors and call the handle_error function
trap 'handle_error "Error on line $LINENO"' ERR

# Instal Package
echo "Install Package manage certificate ..."
if [[ -f /etc/redhat-release ]]; then
    sudo yum install -y ca-certificates
elif [[ -f /etc/lsb-release || -f /etc/debian_version ]]; then
    sudo apt-get install -y ca-certificates
else
    echo "Cannot determine the operating system !!!"
    exit 1
fi
echo "Install Package successful !!"
echo -e "==================================================================================================================== \n\n"

# Genarate Certificate 
echo "Genarate Certificate ..."
if [ ! -f $GEN_CA_KEY ]; then
    openssl genrsa -out $GEN_CA_KEY 4096
    sudo chmod 600 $GEN_CA_KEY
    echo "CA Key created successfully !!"
else
    echo "CA Key Files exist !!"
fi
if [ ! -f $GEN_CA_CERT ]; then
    openssl req -x509 -new -nodes -sha512 -days 365 \
        -subj "$GEN_CERT_SUBJ" \
        -key $GEN_CA_KEY \
        -out $GEN_CA_CERT
    sudo chmod 644 $GEN_CA_CERT
    echo "CA Cert created successfully !!"
else
    echo "CA Cert Files exist !!"
fi    
if [ ! -f $GEN_NGINX_KEY ]; then
    openssl genrsa -out $GEN_NGINX_KEY 4096
    echo "Software Key created successfully !!"
else
    echo "Software Key Files exist !!"
fi
if [ ! -f $GEN_NGINX_CSR ]; then
    openssl req -sha512 -new \
        -subj "$GEN_CERT_SUBJ" \
        -key $GEN_NGINX_KEY \
        -out $GEN_NGINX_CSR
    echo "Software Key created successfully !!"
else
    echo "Software Key Files exist !!"
fi

cat > v3.ext <<-EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1=$GEN_CN
EOF

if [ ! -f $GEN_NGINX_CERT ]; then
    openssl x509 -req -sha512 -days 365 \
        -extfile v3.ext \
        -CA $GEN_CA_CERT -CAkey $GEN_CA_KEY -CAcreateserial \
        -in $GEN_NGINX_CSR \
        -out $GEN_NGINX_CERT
    echo "Software CERT created successfully !!"
else
    echo "Software CERT Files exist !!"
fi

if [ ! -f $GEN_NGINX_PEM ]; then
    openssl x509 -inform PEM -in $GEN_NGINX_CERT -out $GEN_NGINX_PEM
    echo "Software PEM created successfully !!"
else
    echo "Software PEM Files exist !!"
fi

echo -e "==================================================================================================================== \n\n"

