#!/bin/bash

source sonarqube.conf
set -e  # Exit the script when a command fails

function handle_error {
    echo "An error occurred: $1"
    exit 1
}

# Use trap to catch errors and call the handle_error function
trap 'handle_error "Error on line $LINENO"' ERR

# Create sonar group
if ! getent group "$SONAR_USER" > /dev/null 2>&1; then
    echo "Creating group $SONAR_USER..."
    groupadd $SONAR_USER
    echo "Group $SONAR_USER created successfully."
fi

# Create sonar user
if ! id "$SONAR_USER" &>/dev/null; then
    echo "Creating user $SONAR_USER..."
    sudo useradd -d $SONAR_PATH -g $SONAR_USER $SONAR_USER
    echo "User $SONAR_USER created successfully."
fi

# Preparation Directory
if [ ! -d "/var/log/sonarqube" ]; then
    mkdir /var/log/sonarqube
    chown -R $SONAR_USER:$SONAR_USER /var/log/sonarqube
    chmod -R 0755 /var/log/sonarqube
fi
if [ ! -d "$SONAR_PATH" ]; then
    mkdir $SONAR_PATH
    chown -R $SONAR_USER:$SONAR_USER $SONAR_PATH
    chmod -R 0755 $SONAR_PATH
fi

# Preparation PostgreSQL
if ! command -v psql &> /dev/null; then
    if [[ -f /etc/redhat-release ]]; then

        sudo yum update
        sudo dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm
        sudo dnf -qy module disable postgresql
        sudo dnf install -y postgresql15-server
        sudo /usr/pgsql-15/bin/postgresql-15-setup initdb
        sudo systemctl enable postgresql-15
        sudo systemctl start postgresql-15

    elif [[ -f /etc/lsb-release || -f /etc/debian_version ]]; then

        sudo apt install -y curl ca-certificates
        sudo install -d /usr/share/postgresql-common/pgdg
        sudo curl -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc --fail https://www.postgresql.org/media/keys/ACCC4CF8.asc
        sudo sh -c 'echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
        sudo apt update
        sudo apt install -y postgresql-15

    else
        echo "Cannot determine the operating system !!!"
        exit 1
    fi
else
    echo "PostgreSQL Exists !!"
fi
sudo psql -V
echo "Installation PostgreSQL successful !!!"
echo -e "==================================================================================================================== \n\n"

DB_EXISTS=$(sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='sonarqube'")
if [ -z "$DB_EXISTS" ]; then
    # Create Database for SonarQube
    sudo -u postgres createuser sonar
    sudo -u postgres psql -c "ALTER USER $SONAR_USER WITH ENCRYPTED password '$SONAR_DB_PASSWORD';"
    sudo -u postgres psql -c "CREATE DATABASE sonarqube OWNER $SONAR_USER;"
    sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE sonarqube to $SONAR_USER;"
fi

# Preparation Java
if ! command -v java &> /dev/null; then
    if [[ -f /etc/redhat-release ]]; then

        sudo yum update
        sudo yum install -y java-$SONAR_JAVA_VERSION-openjdk tar wget unzip nc

    elif [[ -f /etc/lsb-release || -f /etc/debian_version ]]; then

        sudo apt update
        sudo apt install -y openjdk-$SONAR_JAVA_VERSION-jdk openjdk-$SONAR_JAVA_VERSION-jre tar wget unzip netcat-openbsd

    else
        echo "Cannot determine the operating system !!!"
        exit 1
    fi
fi
sudo java -version
echo "Installation Java successful !!!"
echo -e "==================================================================================================================== \n\n"

# Download Sonarqube Installer
echo "Download Sonarqube Installer ..."
FILE_SONAR=$(basename "$SONAR_LOAD_URL")
if [[ ! -f $FILE_SONAR ]]; then
    wget $SONAR_LOAD_URL
fi
if [ -d "$SONAR_PATH/sonarqube" ]; then
    mv $SONAR_PATH/sonarqube $SONAR_PATH/sonarqube-bak
    echo "Backup Sonarqube directory !!"
fi
unzip $FILE_SONAR
rm -rf $FILE_SONAR

DIR_SONAR=$(basename "$FILE_SONAR" .zip)
mv $DIR_SONAR $SONAR_PATH/sonarqube

chown -R $SONAR_USER:$SONAR_USER $SONAR_PATH
echo "Download Sonarqube successful !!"
echo -e "==================================================================================================================== \n\n"

# Configure Sonarqube file
echo "Configure Sonarqube file ..."
sudo sed -i "s|#sonar.jdbc.username=.*|sonar.jdbc.username=$SONAR_USER|" $SONAR_PATH/sonarqube/conf/sonar.properties
sudo sed -i "s|#sonar.jdbc.password=.*|sonar.jdbc.password=$SONAR_DB_PASSWORD|" $SONAR_PATH/sonarqube/conf/sonar.properties
sudo sed -i "s|#sonar.jdbc.url=jdbc:postgresql:.*|sonar.jdbc.url=jdbc:postgresql://localhost/sonarqube|" $SONAR_PATH/sonarqube/conf/sonar.properties
sudo sed -i "s|#sonar.web.javaOpts=.*|sonar.web.javaOpts=-Xmx$SONAR_MEMORY -Xms128m -XX:+HeapDumpOnOutOfMemoryError|" $SONAR_PATH/sonarqube/conf/sonar.properties
sudo sed -i "s|#sonar.ce.javaOpts=.*|sonar.ce.javaOpts=-Xmx$SONAR_MEMORY -Xms128m -XX:+HeapDumpOnOutOfMemoryError|" $SONAR_PATH/sonarqube/conf/sonar.properties
sudo sed -i "s|#sonar.path.logs=.*|sonar.path.logs=/var/log/sonarqube|" $SONAR_PATH/sonarqube/conf/sonar.properties
sudo sed -i "s|#sonar.path.data=.*|sonar.path.data=$SONAR_PATH/sonar-data|" $SONAR_PATH/sonarqube/conf/sonar.properties
sudo sed -i "s|#sonar.path.temp=.*|sonar.path.temp=$SONAR_PATH/sonar-temp|" $SONAR_PATH/sonarqube/conf/sonar.properties

# Log Retention
sudo sed -i "s|#sonar.log.rollingPolicy=.*|sonar.log.rollingPolicy=time:yyyy-MM-dd|" $SONAR_PATH/sonarqube/conf/sonar.properties
sudo sed -i "s|#sonar.log.maxFiles=.*|sonar.log.maxFiles=$SONAR_ROTATE|" $SONAR_PATH/sonarqube/conf/sonar.properties

# Create File Service
if [ ! -f /etc/systemd/system/sonarqube.service ]; then

SONAR_RUN=$(find $SONAR_PATH/sonarqube/lib/ -name "sonar-application-*")

cat > /etc/systemd/system/sonarqube.service <<EOF
[Unit]
Description=SonarQube service
After=syslog.target network.target

[Service]
Type=simple
User=$SONAR_USER
Group=$SONAR_USER
PermissionsStartOnly=true
ExecStart=/bin/nohup /bin/java -Xms32m -Xmx32m -Djava.net.preferIPv4Stack=true -jar $SONAR_RUN
StandardOutput=syslog
LimitNOFILE=131072
LimitNPROC=8192
TimeoutStartSec=5
Restart=always
SuccessExitStatus=143

[Install]
WantedBy=multi-user.target
EOF
fi 

sudo systemctl daemon-reload
sudo systemctl enable sonarqube.service
sudo systemctl restart sonarqube.service

echo "Config Sonarqube successful !!"
echo -e "==================================================================================================================== \n\n"

echo "Install Java              ... successful ✔"
echo "Download Sonarqube        ... successful ✔"
echo "Config Sonarqube          ... successful ✔"
echo "File Systemd              ... successful ✔"

echo -e "==================================================================================================================== \n\n"

# Wait for Nexus started
LOADING=0
echo -n "Starting "
while ! nc -z localhost 9000; do
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
echo "Sonarqube Service     Started ... ✔"
echo "URL: http://$(hostname -I | awk '{print $1}'):9000"
echo "Username: admin"
echo "Password: admin"