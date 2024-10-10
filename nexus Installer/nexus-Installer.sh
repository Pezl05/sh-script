#!/bin/bash

source nexus.conf
set -e  # Exit the script when a command fails

function handle_error {
    echo "An error occurred: $1"
    exit 1
}

# Use trap to catch errors and call the handle_error function
trap 'handle_error "Error on line $LINENO"' ERR

# Create User
if ! id "$NEXUS_USER" &>/dev/null; then
    echo "Creating user $NEXUS_USER..."
    sudo useradd --system --no-create-home --home-dir $NEXUS_PATH $NEXUS_USER
    echo "User $NEXUS_USER created successfully."
fi


# Preparation Directory
if [[ ! -d "$NEXUS_PATH/certs" && "$NEXUS_GEN_CERT" == true ]]; then
    mkdir -p $NEXUS_PATH/certs
    chown -R $NEXUS_USER:$NEXUS_USER $NEXUS_PATH
    chmod -R 0755 $NEXUS_PATH
fi
if [ ! -d "/var/log/nexus" ]; then
    mkdir /var/log/nexus
    chown -R $NEXUS_USER:$NEXUS_USER /var/log/nexus
    chmod -R 0755 /var/log/nexus
fi
if [ ! -d "$NEXUS_PATH" ]; then
    mkdir $NEXUS_PATH
    chown -R $NEXUS_USER:$NEXUS_USER $NEXUS_PATH
    chmod -R 0755 $NEXUS_PATH
fi

# Preparation Java
if ! command -v java &> /dev/null; then
    if [[ -f /etc/redhat-release ]]; then

        sudo yum update
        sudo yum install -y java-$NEXUS_JAVA_VERSION-openjdk tar wget nc

    elif [[ -f /etc/lsb-release || -f /etc/debian_version ]]; then

        sudo apt update
        sudo apt install -y openjdk-$NEXUS_JAVA_VERSION-jdk openjdk-$NEXUS_JAVA_VERSION-jre tar wget netcat-openbsd

    else
        echo "Cannot determine the operating system !!!"
        exit 1
    fi
fi
sudo java -version
echo "Installation Java successful !!!"
echo -e "==================================================================================================================== \n\n"

# Genarate Certificate 
echo "Genarate Certificate Nexus ..."
if [[ "$NEXUS_GEN_CERT" == true ]]; then
    if [ ! -f $NEXUS_KEYSTORE ] ; then
        keytool -genkeypair -alias $NEXUS_HOST_NAME \
            -keyalg RSA -keysize 2048 -validity 365 \
            -keystore $NEXUS_KEYSTORE \
            -storepass $NEXUS_KEYPASS \
            -keypass $NEXUS_KEYPASS \
            -dname "CN=$NEXUS_HOST_NAME, OU=Software Engineer, O=Sirisoft, L=Dindaeng, ST=Bangkok, C=TH"
        sudo chown -R $NEXUS_USER:$NEXUS_USER $NEXUS_KEYSTORE
        echo "Genarate Certificate successful !!"
    else
        echo "Certificate Files exist !!"
    fi
    echo -e "==================================================================================================================== \n\n"
fi

# Download Nexus Installer
echo "Download Nexus Installer ..."
FILE_NEXUS=$(basename "$NEXUS_LOAD_URL")
if [[ ! -f $FILE_NEXUS ]]; then
    wget $NEXUS_LOAD_URL
fi
if [ -d "$NEXUS_PATH/nexus" ]; then
    mv $NEXUS_PATH/nexus $NEXUS_PATH/nexus-bak
    echo "Backup Nexus directory !!"
fi
tar -xvzf $FILE_NEXUS
rm -rf $FILE_NEXUS sonatype-work
mv nexus-3* $NEXUS_PATH/nexus
chown -R $NEXUS_USER:$NEXUS_USER $NEXUS_PATH
echo "Download Nexus successful !!"
echo -e "==================================================================================================================== \n\n"

# Configure Nexus file
echo "Configure Nexus file ..."
sudo sed -i 's/#run_as_user=""/run_as_user="nexus"/' $NEXUS_PATH/nexus/bin/nexus.rc
sudo sed -i "s/2703m/$NEXUS_MEMORY/g" $NEXUS_PATH/nexus/bin/nexus.vmoptions
sudo sed -i "s|\.\./sonatype-work/nexus3/log|/var/log/nexus|g" $NEXUS_PATH/nexus/bin/nexus.vmoptions
sudo sed -i "s:/sonatype-work/nexus3:/nexus-data/nexus3:g" $NEXUS_PATH/nexus/bin/nexus.vmoptions
sudo sed -i "s|\${karaf.data}/log|/var/log/nexus|g" $NEXUS_PATH/nexus/etc/logback/logback.xml

# Config HTTPs
if [[ "$NEXUS_GEN_CERT" == true ]]; then

    sudo sed -i 's|application-port=8081|application-port-ssl=8443|g' $NEXUS_PATH/nexus/etc/nexus-default.properties
    sudo sed -i 's|nexus-args=${jetty.etc}/jetty.xml,${jetty.etc}/jetty-http.xml,${jetty.etc}/jetty-requestlog.xml|nexus-args=${jetty.etc}/jetty.xml,${jetty.etc}/jetty-requestlog.xml,${jetty.etc}/jetty-https.xml|g' $NEXUS_PATH/nexus/etc/nexus-default.properties
    sudo sed -i "s|<Set name=\"KeyStorePath\"><Property name=\"ssl.etc\"/>/keystore.jks</Set>|<Set name=\"KeyStorePath\">$NEXUS_KEYSTORE</Set>|g" $NEXUS_PATH/nexus/etc/jetty/jetty-https.xml
    sudo sed -i "s|<Set name=\"TrustStorePath\"><Property name=\"ssl.etc\"/>/keystore.jks</Set>|<Set name=\"TrustStorePath\">$NEXUS_KEYSTORE</Set>|g" $NEXUS_PATH/nexus/etc/jetty/jetty-https.xml
    sudo sed -i "s|password|$NEXUS_KEYPASS|g" $NEXUS_PATH/nexus/etc/jetty/jetty-https.xml

fi

# Config Log Rotate
sudo sed -E -i "s/(^.*maxHistory>)[0-9]+(.*$)/\1$NEXUS_ROTATE\2/g" $NEXUS_PATH/nexus/etc/logback/logback.xml

# Create File Service
if [ ! -f /etc/systemd/system/nexus.service ]; then
cat > /etc/systemd/system/nexus.service <<EOF
[Unit]
Description=nexus service
After=network.target
  
[Service]
Type=forking
LimitNOFILE=65536
ExecStart=$NEXUS_PATH/nexus/bin/nexus start
ExecStop=$NEXUS_PATH/nexus/bin/nexus stop 
User=$NEXUS_USER
Restart=on-abort
TimeoutSec=600
  
[Install]
WantedBy=multi-user.target
EOF
fi 

sudo systemctl daemon-reload
sudo systemctl enable nexus.service
sudo systemctl restart nexus.service

echo "Config Nexus successful !!"
echo -e "==================================================================================================================== \n\n"

echo "Install Java          ... successful ✔"
echo "Download Nexus        ... successful ✔"
echo "Config Nexus          ... successful ✔"
if [[ "$NEXUS_GEN_CERT" == true ]]; then
    echo "Config HTTPs          ... successful ✔"
fi
echo "File Systemd          ... successful ✔"

echo -e "==================================================================================================================== \n\n"

# Set port for connect nexus console
NEXUS_PORT=$(( [ "$NEXUS_GEN_CERT" == true ] && echo 8443 ) || echo 8081 )
LOADING=0

# Wait for Nexus started
echo -n "Starting "
while ! nc -z localhost "$NEXUS_PORT"; do
    echo -n "."
    LOADING=$((LOADING + 1))

    if [ "$LOADING" -gt 5 ]; then
        echo -ne "\r"
        echo -n "Starting "
        LOADING=0
    fi

    sleep 2
done

tput cuu 1 # Move to line before
tput el # Clear line
echo "Nexus Service     Started ... ✔"
echo "URL: https://$NEXUS_HOST_NAME"
echo "Username: admin"
echo "Password: $(cat $NEXUS_PATH/nexus-data/nexus3/admin.password)"