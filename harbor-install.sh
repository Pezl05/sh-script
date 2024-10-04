#!/bin/bash

source harbor.conf
set -e  # Exit the script when a command fails

function handle_error {
    echo "An error occurred: $1"
    exit 1
}

# Use trap to catch errors and call the handle_error function
trap 'handle_error "Error on line $LINENO"' ERR

# Preparation Docker
if ! command -v docker &> /dev/null; then
    if [[ -f /etc/redhat-release ]]; then

        # Set up the repository for RHEL
        echo "Yum-utils Installing ..."
        sudo yum install -y yum-utils tar wget
        echo "Install yum-utils successful !!"
        echo -e "==================================================================================================================== \n\n"

        sudo yum-config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo

        # Install the Docker packages:
        echo "Docker Installing ..."
        sudo yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        sudo systemctl enable docker
        sudo systemctl start docker

    elif [[ -f /etc/lsb-release || -f /etc/debian_version ]]; then

        # Add Docker's official GPG key for Ubuntu
        echo "Add Docker's official GPG key ..."
        sudo apt-get update
        sudo apt-get install -y ca-certificates curl tar wget
        sudo install -m 0755 -d /etc/apt/keyrings
        sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
        sudo chmod a+r /etc/apt/keyrings/docker.asc

        # Add the repository to Apt sources:
        echo "Add the repository to Apt sources ..."
        echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
        $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
        sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

        sudo apt-get update
        echo -e "==================================================================================================================== \n\n"

        # Install the Docker packages:
        echo "Docker Installing ..."
        sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    else
        echo "Cannot determine the operating system !!!"
        exit 1
    fi
fi
echo "Installation Docker successful !!!"
echo -e "==================================================================================================================== \n\n"

# Add Docker's official GPG key for Ubuntu
echo "Install Package manage file harbor ..."
if [[ -f /etc/redhat-release ]]; then
    sudo yum install -y tar wget
elif [[ -f /etc/lsb-release || -f /etc/debian_version ]]; then
    sudo apt-get install -y tar wget
else
    echo "Cannot determine the operating system !!!"
    exit 1
fi
echo "Install Package successful !!"
echo -e "==================================================================================================================== \n\n"

# Download Harbor Installer
echo "Download Harbor Installer ..."
FILE_HARBOR=$(basename "$HARBOR_LOAD_URL")
if [[ ! -f $FILE_HARBOR ]]; then
    wget $HARBOR_LOAD_URL
fi
if [ -d "harbor" ]; then
    mv harbor harbor-bak
    echo "Backup Harbor directory !!"
fi
tar -xvzf $FILE_HARBOR
echo "Download Harbor successful !!"
echo -e "==================================================================================================================== \n\n"

# Genarate Certificate 
echo "Download Harbor Installer ..."
if [[ "$HARBOR_GEN_CERT" == true ]]; then
    if [ ! -f $HARBOR_NGINX_KEY ] && [ ! -f $HARBOR_NGINX_CERT ]; then
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout $HARBOR_NGINX_KEY -out $HARBOR_NGINX_CERT -subj "/C=TH/ST=Bangkok/L=Dindaeng/O=Sirisoft/OU=Software Engineer/CN=$HARBOR_HOST_NAME"
        sudo chmod 600 $HARBOR_NGINX_KEY
        sudo chmod 644 $HARBOR_NGINX_CERT
    else
        echo "Certificate Files exist !!"
    fi
fi

# Configure Harbor file
echo "Configure Harbor file ..."
cp ./harbor/harbor.yml.tmpl ./harbor/harbor.yml
sudo sed -i "s|hostname: .*|hostname: $HARBOR_HOST_NAME|" ./harbor/harbor.yml
sudo sed -i "s|certificate: .*|certificate: $HARBOR_NGINX_CERT|" ./harbor/harbor.yml
sudo sed -i "s|private_key: .*|private_key: $HARBOR_NGINX_KEY|" ./harbor/harbor.yml
sudo sed -i "s|harbor_admin_password: .*|harbor_admin_password: $HARBOR_ADMIN_PASSWORD|" ./harbor/harbor.yml
sudo sed -i "s|password: root123|password: $HARBOR_DATABASE_PASSWORD|" ./harbor/harbor.yml
sudo sed -i "s|data_volume: .*|data_volume: $HARBOR_DATA_VOLUME|" ./harbor/harbor.yml
echo -e "==================================================================================================================== \n\n"

# Install Harbor
echo "Harbor Installing ..."
if [[ "$HARBOR_ENABLE_TRIVY" == true ]]; then
    ./harbor/install.sh --with-trivy
else
    ./harbor/install.sh
fi
echo "Install Harbor successful !!"
echo -e "==================================================================================================================== \n\n"

# Configure Common
echo "Configure Common file ..."
cat <<EOF > $PWD/harbor/common/config/log/logrotate.conf
/var/log/docker/*.log {
        daily
        rotate $HARBOR_ROTATE
        copytruncate
        compress
        missingok
        notifempty
        dateext
        dateformat -%Y%m%d
}
EOF
echo "Logrotate ... ✔"

# Set Time Zone
echo -e "\nTZ=Asia/Bangkok" >> $PWD/harbor/common/config/db/env
echo "Time Zone ... ✔"

# Create File Service
if [ ! -f /etc/systemd/system/harbor.service ]; then
cat > /etc/systemd/system/harbor.service <<EOF
[Unit]
Description=Harbor Docker Compose Application Service
Requires=docker.service
After=docker.service

[Service]
WorkingDirectory=$PWD/harbor
ExecStart=/bin/docker compose up
ExecStop=/bin/docker compose down
TimeoutStartSec=0
Restart=on-failure
StartLimitBurst=3

[Install]
WantedBy=multi-user.target
EOF
fi 

echo "File Systemd ... ✔"

sudo systemctl daemon-reload
sudo systemctl enable harbor.service
sudo systemctl restart harbor.service
echo "Start Harbor ... ✔"

echo -e "==================================================================================================================== \n\n"

echo "Harbor is ready for use. Successfully ✔✔✔ "
echo "URL: https://$HARBOR_HOST_NAME"
echo "Username: admin"
echo "Password: $HARBOR_ADMIN_PASSWORD"
echo -e "\n\n"
