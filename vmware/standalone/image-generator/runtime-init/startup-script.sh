#!/bin/bash -x

# Wait for disk re-sizing to finisih before starting
# ve.dir.resize: Successfully wrote the new partition table
for i in {1..60}; do [[ -f "/var/log/ve.dir.resize.log.bak" ]] && grep -q boot_marker /var/log/ve.dir.resize.log.bak && break || sleep 1; done

# Send output to log file and serial console
mkdir -p  /var/log/cloud /config/cloud /var/lib/cloud /var/config/rest/downloads 
LOG_FILE=/var/log/cloud/startup-script.log
[[ ! -f $LOG_FILE ]] && touch $LOG_FILE || { echo "Run Only Once. Exiting"; exit; }
npipe=/tmp/$$.tmp
trap "rm -f $npipe" EXIT
mknod $npipe p
tee <$npipe -a $LOG_FILE /dev/ttyS0 &
exec 1>&-
exec 1>$npipe
exec 2>&1

echo "$(date +"%Y-%m-%dT%H:%M:%S.%3NZ") : Starting Custom Script"

### write_files:
# Download or Render BIG-IP Runtime Init Config
# NOTE: When baked in, pre_onboard_enabled commands are able to run in time before MCPD starts 
cat << 'EOF' > /config/cloud/runtime-init-conf.yaml
runtime_parameters: []
pre_onboard_enabled:
  - name: provision_rest
    type: inline
    commands:
      - /usr/bin/setdb provision.extramb 500
      - /usr/bin/setdb restjavad.useextramb true
      - /usr/bin/setdb setup.run false
extension_packages:
    install_operations:
        - extensionType: do
          extensionVersion: 1.16.0
          extensionUrl: file:///var/config/rest/downloads/f5-declarative-onboarding-1.16.0-8.noarch.rpm
        - extensionType: as3
          extensionVersion: 3.23.0
          extensionUrl: file:///var/config/rest/downloads/f5-appsvcs-3.23.0-5.noarch.rpm
        - extensionType: ts
          extensionVersion: 1.15.0
          extensionUrl: file:///var/config/rest/downloads/f5-telemetry-1.15.0-4.noarch.rpm
extension_services:
    service_operations: []
post_onboard_enabled: []
EOF

### runcmd:
# source /usr/lib/bigstart/bigip-ready-functions
# wait_bigip_ready

# Install
bash /var/config/rest/downloads/f5-bigip-runtime-init-1.1.0-1.gz.run -- '--skip-verify'
# Run
f5-bigip-runtime-init --config-file /config/cloud/runtime-init-conf.yaml

echo "$(date +"%Y-%m-%dT%H:%M:%S.%3NZ") : Finished Custom Script"