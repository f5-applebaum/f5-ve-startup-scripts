#!/bin/bash

# Wait for disk re-sizing to finish before writing out pipe and log file
# ve.dir.resize: Successfully wrote the new partition table
for i in {1..60}; do [[ -f "/var/log/ve.dir.resize.log.bak" ]] && grep -q boot_marker /var/log/ve.dir.resize.log.bak && break || sleep 1; done

#### VARS #####
CLOUD_DIR="/config/cloud"
LOG_DIR="/var/log/cloud"
ICONTROLLX_INSTALL_DIR="/var/config/rest/downloads"

# Send output to log file and serial console
for i in $CLOUD_DIR $LOG_DIR $ICONTROLLX_INSTALL_DIR; do mkdir -p $i; done
LOG_FILE=$LOG_DIR/startup-script.log
[[ ! -f $LOG_FILE ]] && touch $LOG_FILE || { echo "Run Only Once. Exiting"; exit; }
npipe=/tmp/$$.tmp
trap "rm -f $npipe" EXIT
mknod $npipe p
tee <$npipe -a $LOG_FILE /dev/ttyS0 &
exec 1>&-
exec 1>$npipe
exec 2>&1

echo "$(date) : Starting Custom Script"

# SOME BIG-IP UTILS INLINE
function wait_for_bigip() {
    echo "** BigIP waiting ..."
    bigstart_wait mcpd ready
    while ! tmsh show sys mcp-state field-fmt | grep -qE 'phase.+running' || pidof -x mprov.pl >/dev/null 2>&1; do sleep 1; done
    while [[ ! $(curl -u 'admin:' -s http://localhost:8100/shared/echo | jq -r .stage) = "STARTED" ]]; do echo "waiting for iControl..."; sleep 10; done
    if [[ ! $(getdb Provision.CPU.asm) == 0 ]]; then perl -MF5::ASMReady -e '$|++; do {print "waiting for asm...\n"; sleep(1)} while !F5::ASMReady::is_asm_ready()'; fi
    echo "** BigIp ready."
}

function install_lx {
    FILE_PATH=${1}
    local MAX_RETRIES=${2:-10}
    local DELAY=${3:-10}

    local STATUS_MAX_RETRIES=50

    local RETRY=1
    until [ ${RETRY} -ge ${MAX_RETRIES} ]; do
        # echo "$(date) - Installing ${FILE_PATH}..."
        TASK_ID=$( curl -u admin: -s -H 'Content-Type: application/json' --data '{"operation":"INSTALL","packageFilePath":"'"${FILE_PATH}"'"}' http://localhost:8100/mgmt/shared/iapp/package-management-tasks | jq -r .id )

        echo "$(date) - TASK_ID = ${TASK_ID}"

        local STATUS_RETRY=1
        if [[ "${TASK_ID}" != "null" ]]
        then  
            until [ ${STATUS_RETRY} -ge ${STATUS_MAX_RETRIES} ]; do
                STATUS=$( curl -u admin: -s http://localhost:8100/mgmt/shared/iapp/package-management-tasks/${TASK_ID} | jq -r .status )
                if [[ "${STATUS}" == "FINISHED" ]]; then
                    echo "$(date) - Status = \"${STATUS}\""
                    return 0
                elif [[ "${STATUS}" == "FAILED" ]]; then
                    echo "$(date) - Status = \"${STATUS}\""
                    STATUS_RETRY=${STATUS_MAX_RETRIES}
                else
                    echo "$(date) - ${FILE_PATH}: Status = \"${STATUS}\". Install Attempt ${RETRY}/${MAX_RETRIES}. Polling status ${STATUS_RETRY}/${STATUS_MAX_RETRIES}. Sleeping ${DELAY}s."
                    ((STATUS_RETRY++))
                    sleep ${DELAY}
                fi
            done
        else
            echo "$(date) - No TASK_ID provided. Trying Again..."
        fi
        ((RETRY++))
    done

    # timed out
    return 1

}
### OR SOURCE THEM INSTEAD
# curl -o /config/cloud/utils.sh -s --fail --retry 60 -m 10 -L https://gist.githubusercontent.com/f5-applebaum/93818d6c86ab3034d0ee0b88093f91f1/raw/67f600810f4f655df3e9ba8eb57724959c266b74/utils.sh
# . /config/cloud/utils.sh

# WAIT FOR BIG-IP SYSTEMS & API TO BE UP
echo "$(date) : Start wait_for_bigip"
wait_for_bigip

# INSTALL TOOLCHAIN APIS
ICONTROLLX_PACKAGE_URLS=(    
    "f5-declarative-onboarding-1.16.0-8.noarch.rpm"
    "f5-appsvcs-3.23.0-5.noarch.rpm"
    "f5-telemetry-1.15.0-4.noarch.rpm"
)

for FILE in ${ICONTROLLX_PACKAGE_URLS[@]};
do
    echo "$(date) - Installing ${ICONTROLLX_INSTALL_DIR}/${FILE##*/}"
    install_lx "${ICONTROLLX_INSTALL_DIR}/${FILE##*/}"
    # restnoded needs time before next lx package to register
    sleep 15
done

echo "$(date) : Finished Custom Script"
