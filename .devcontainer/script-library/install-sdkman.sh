JAVA_VERSION=${1:-"lts"}
export SDKMAN_DIR=${2:-"/usr/local/sdkman"}
USERNAME=${3:-"automatic"}
UPDATE_RC=${4:-"true"}

set -e

if [ "$(id -u)" -ne 0 ]; then
    echo -e 'Script must be run as root. Use sudo, su, or add "USER root" to your Dockerfile before running this script.'
    exit 1
fi

# Determine the appropriate non-root user
if [ "${USERNAME}" = "auto" ] || [ "${USERNAME}" = "automatic" ]; then
    USERNAME=""
    POSSIBLE_USERS=("vscode" "node" "codespace" "$(awk -v val=1000 -F ":" '$3==val{print $1}' /etc/passwd)")
    for CURRENT_USER in ${POSSIBLE_USERS[@]}; do
        if id -u ${CURRENT_USER} > /dev/null 2>&1; then
            USERNAME=${CURRENT_USER}
            break
        fi
    done
    if [ "${USERNAME}" = "" ]; then
        USERNAME=root
    fi
elif [ "${USERNAME}" = "none" ] || ! id -u ${USERNAME} > /dev/null 2>&1; then
    USERNAME=root
fi

updaterc() {
    if [ "${UPDATE_RC}" = "true" ]; then
        echo "Updating /etc/bash.bashrc and /etc/zsh/zshrc..."
        if [[ "$(cat /etc/bash.bashrc)" != *"$1"* ]]; then
            echo -e "$1" >> /etc/bash.bashrc
        fi
        if [ -f "/etc/zsh/zshrc" ] && [[ "$(cat /etc/zsh/zshrc)" != *"$1"* ]]; then
            echo -e "$1" >> /etc/zsh/zshrc
        fi
    fi
}

# Use SDKMAN to install something using a partial version match
sdk_install() {
    local install_type=$1
    local requested_version=$2
    local prefix=$3
    local suffix="${4:-"\\s*"}"
    local full_version_check=${5:-".*-[a-z]+"}
    if [ "${requested_version}" = "none" ]; then return; fi
    # Blank will install latest stable version SDKMAN has
    if [ "${requested_version}" = "lts" ] || [ "${requested_version}" = "default" ]; then
         requested_version=""
    elif echo "${requested_version}" | grep -oE "${full_version_check}" > /dev/null 2>&1; then
        echo "${requested_version}"
    else
        local regex="${prefix}\\K[0-9]+\\.[0-9]+\\.[0-9]+${suffix}"
        local version_list="$(. ${SDKMAN_DIR}/bin/sdkman-init.sh && sdk list ${install_type} 2>&1 | grep -oP "${regex}" | tr -d ' ' | sort -rV)"
        if [ "${requested_version}" = "latest" ] || [ "${requested_version}" = "current" ]; then
            requested_version="$(echo "${version_list}" | head -n 1)"
        else
            set +e
            requested_version="$(echo "${version_list}" | grep -E -m 1 "^${requested_version//./\\.}([\\.\\s]|$)")"
            set -e
        fi
        if [ -z "${requested_version}" ] || ! echo "${version_list}" | grep "^${requested_version//./\\.}$" > /dev/null 2>&1; then
            echo -e "Version $2 not found. Available versions:\n${version_list}" >&2
            exit 1
        fi
    fi
    su ${USERNAME} -c "umask 0002 && . ${SDKMAN_DIR}/bin/sdkman-init.sh && sdk install ${install_type} ${requested_version} && sdk flush archives && sdk flush temp"
}


architecture="$(uname -m)"
if [ "${architecture}" != "amd64" ] && [ "${architecture}" != "x86_64" ] && [ "${architecture}" != "arm64" ] && [ "${architecture}" != "aarch64" ]; then
    echo "(!) Architecture $architecture unsupported"
    exit 1
fi

# Install sdkman if not installed
if [ ! -d "${SDKMAN_DIR}" ]; then
    # Create sdkman group, dir, and set sticky bit
    if ! cat /etc/group | grep -e "^sdkman:" > /dev/null 2>&1; then
        groupadd -r sdkman
    fi
    usermod -a -G sdkman ${USERNAME}
    umask 0002
    # Install SDKMAN
    curl -sSL "https://get.sdkman.io?rcupdate=false" | bash
    chown -R :sdkman ${SDKMAN_DIR}
    find ${SDKMAN_DIR} -type d | xargs -d '\n' chmod g+s
    # Add sourcing of sdkman into bashrc/zshrc files (unless disabled)
    echo "export SDKMAN_DIR=${SDKMAN_DIR}" >> /home/${USERNAME}/.zshrc
    echo ". \${SDKMAN_DIR}/bin/sdkman-init.sh" >> /home/${USERNAME}/.zshrc
    echo "export SDKMAN_DIR=${SDKMAN_DIR}" >> /home/${USERNAME}/.bashrc
    echo ". \${SDKMAN_DIR}/bin/sdkman-init.sh" >> /home/${USERNAME}/.bashrc
fi

su ${USERNAME} -c "umask 0002 && . ${SDKMAN_DIR}/bin/sdkman-init.sh && sdk install java 22.3.r19-grl && sdk install maven && sdk install maven && sdk install springboot && sdk flush archives && sdk flush temp"