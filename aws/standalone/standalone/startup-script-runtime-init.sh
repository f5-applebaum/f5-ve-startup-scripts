#!/bin/bash -x

# NOTE: Run once Initialization Only (Cloud-Init behavior vs. re-entrant like Azure Custom Script Extension )
# For 15.1+ and above, can disable Azure Custom Script extension and pass to cloud-init ( via custom_data in os_profile )

# Send output to log file and serial console
mkdir -p  /var/log/cloud /config/cloud /var/config/rest/downloads
LOG_FILE=/var/log/cloud/startup-script.log
[[ ! -f $LOG_FILE ]] && touch $LOG_FILE || { echo "Run Only Once. Exiting"; exit; }
npipe=/tmp/$$.tmp
trap "rm -f $npipe" EXIT
mknod $npipe p
tee <$npipe -a $LOG_FILE /dev/ttyS0 &
exec 1>&-
exec 1>$npipe
exec 2>&1

# Opptional WAF optimization
# Must be done as early in boot as possible before MCPD starts ( Cloud-init only ) 
/usr/bin/setdb provision.extramb 500
/usr/bin/setdb restjavad.useextramb true
/usr/bin/setdb setup.run false

### write_files:
# Download or Render BIG-IP Runtime Init Config 
cat << 'EOF' > /config/cloud/runtime-init-conf.yaml
runtime_parameters: []
pre_onboard_enabled: []
extension_packages:
    install_operations:
        - extensionType: do
          extensionVersion: 1.16.0
        - extensionType: as3
          extensionVersion: 3.23.0
        - extensionType: ts
          extensionVersion: 1.12.0
extension_services:
    service_operations: []
post_onboard_enabled: []
EOF

### runcmd:
# Download
PACKAGE_URL='https://cdn.f5.com/product/cloudsolutions/f5-bigip-runtime-init/v1.1.0/dist/f5-bigip-runtime-init-1.1.0-1.gz.run'
for i in {1..30}; do
    curl -fv --retry 1 --connect-timeout 5 -L "${PACKAGE_URL}" -o "/var/config/rest/downloads/${PACKAGE_URL##*/}" && break || sleep 10
done
# Install
bash /var/config/rest/downloads/f5-bigip-runtime-init-1.0.0-1.gz.run -- '--cloud aws'
# Run
f5-bigip-runtime-init --config-file /config/cloud/runtime-init-conf.yaml

