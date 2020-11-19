#!/bin/bash -x

# Log to local file and serial console
mkdir -p /var/log/cloud /config/cloud /var/config/rest/downloads
LOG_FILE=/var/log/cloud/startup-script.log
touch ${LOG_FILE}
npipe=/tmp/$$.tmp
trap "rm -f $npipe" EXIT
mknod $npipe p
tee <$npipe -a ${LOG_FILE} /dev/ttyS0 &
exec 1>&-
exec 1>$npipe
exec 2>&1

echo "$(date +"%Y-%m-%dT%H:%M:%S.%3NZ") : Starting Custom Script"
# # Optional optimizations required as early as possible in boot sequence before MCDP starts up.
# # In Azure, only works if invoked from Cloud-Init via custom_data in os_profile. 
# # Custom-Script Extension invoked little too late.
# ! grep -q 'provision asm' /config/bigip_base.conf && echo 'sys provision asm { level nominal }' >> /config/bigip_base.conf
/usr/bin/setdb provision.extramb 500
/usr/bin/setdb restjavad.useextramb true

# VARS FROM TEMPLATE
PACKAGE_URL='https://cdn.f5.com/product/cloudsolutions/f5-bigip-runtime-init/v1.1.0/dist/f5-bigip-runtime-init-1.1.0-1.gz.run'
RUNTIME_CONFIG='https://raw.githubusercontent.com/f5-applebaum/deployments-v2/0.0.1/dev/bigip-configurations/bigip-config.yaml'

# Download or render f5-bigip-runtime-init config
if [[ "${RUNTIME_CONFIG}" =~ ^http.* ]]; then
  curl -sfv --retry 60 --connect-timeout 5 -L "${RUNTIME_CONFIG}" -o /config/cloud/runtime-init.conf
else
  printf '%s\n' "${RUNTIME_CONFIG}" | jq  > /config/cloud/runtime-init.conf
fi

# Download and install f5-bigip-runtime-init package
for i in {1..30}; do
    curl -fv --retry 1 --connect-timeout 5 -L "${PACKAGE_URL}" -o "/var/config/rest/downloads/${PACKAGE_URL##*/}" && break || sleep 10
done
bash "/var/config/rest/downloads/${PACKAGE_URL##*/}" -- '--cloud azure'

# Run
f5-bigip-runtime-init --config-file /config/cloud/runtime-init.conf

