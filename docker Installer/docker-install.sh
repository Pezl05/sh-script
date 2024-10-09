#!/bin/bash

set -e  # Exit the script when a command fails

function handle_error {
    echo "An error occurred: $1"
    exit 1
}

# Use trap to catch errors and call the handle_error function
trap 'handle_error "Error on line $LINENO"' ERR

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
