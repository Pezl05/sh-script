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

        if grep -i "centos" /etc/redhat-release > /dev/null; then
            sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
        elif grep -i "red hat" /etc/redhat-release > /dev/null; then
            sudo yum-config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
        else
            echo "Unsupported OS detected."
            exit 1
        fi

        # Install the Docker packages:
        echo "Docker Installing ..."
        sudo yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

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
sudo systemctl enable docker
sudo systemctl start docker
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
if [ -d "$HARBOR_PATH/harbor" ]; then
    mv $HARBOR_PATH/harbor $HARBOR_PATH/harbor-bak
    echo "Backup Harbor directory !!"
fi
tar -xvzf $FILE_HARBOR
mv $FILE_HARBOR $HARBOR_PATH/
echo "Download Harbor successful !!"
echo -e "==================================================================================================================== \n\n"

# Genarate Certificate 
echo "Genarate Certificate Harbor ..."
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
cp $HARBOR_PATH/harbor/harbor.yml.tmpl $HARBOR_PATH/harbor/harbor.yml
sudo sed -i "s|hostname: .*|hostname: $HARBOR_HOST_NAME|" $HARBOR_PATH/harbor/harbor.yml
sudo sed -i "s|certificate: .*|certificate: $HARBOR_NGINX_CERT|" $HARBOR_PATH/harbor/harbor.yml
sudo sed -i "s|private_key: .*|private_key: $HARBOR_NGINX_KEY|" $HARBOR_PATH/harbor/harbor.yml
sudo sed -i "s|harbor_admin_password: .*|harbor_admin_password: $HARBOR_ADMIN_PASSWORD|" $HARBOR_PATH/harbor/harbor.yml
sudo sed -i "s|password: root123|password: $HARBOR_DATABASE_PASSWORD|" $HARBOR_PATH/harbor/harbor.yml
sudo sed -i "s|data_volume: .*|data_volume: $HARBOR_DATA_VOLUME|" $HARBOR_PATH/harbor/harbor.yml
echo -e "==================================================================================================================== \n\n"

# Install Harbor
echo "Harbor Installing ..."
if [[ "$HARBOR_ENABLE_TRIVY" == true ]]; then
    $HARBOR_PATH/harbor/install.sh --with-trivy
else
    $HARBOR_PATH/harbor/install.sh
fi

# Create File Service
if [ ! -f /etc/systemd/system/harbor.service ]; then
cat > /etc/systemd/system/harbor.service <<EOF
[Unit]
Description=Harbor Docker Compose Application Service
Requires=docker.service
After=docker.service

[Service]
WorkingDirectory=$HARBOR_PATH/harbor
ExecStart=/bin/docker compose up
ExecStop=/bin/docker compose down
TimeoutStartSec=0
Restart=on-failure
StartLimitBurst=3

[Install]
WantedBy=multi-user.target
EOF
fi 

# Configure Common
echo "Configure Common file ..."
cat <<EOF > $HARBOR_PATH/harbor/common/config/log/logrotate.conf
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

# Set Time Zone
echo -e "\nTZ=Asia/Bangkok" >> $HARBOR_PATH/harbor/common/config/db/env

sudo systemctl daemon-reload
sudo systemctl enable harbor.service
sudo systemctl restart harbor.service

echo "Install Harbor successful !!"
echo -e "==================================================================================================================== \n\n"

echo "Logrotate ... ✔"
echo "Time Zone ... ✔"
echo "File Systemd ... ✔"
echo "Start Harbor ... ✔"

echo -e "==================================================================================================================== \n\n"

echo "Harbor is ready for use. Successfully ✔✔✔ "
echo "URL: https://$HARBOR_HOST_NAME"
echo "Username: admin"
echo "Password: $HARBOR_ADMIN_PASSWORD"
echo -e "\n\n"
