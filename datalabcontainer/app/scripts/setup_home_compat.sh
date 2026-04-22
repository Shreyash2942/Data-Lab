#!/usr/bin/env bash
set -euo pipefail

HOME_DIR="${DATALAB_HOME:-/home/datalab}"
WORKSPACE="${WORKSPACE:-${HOME_DIR}}"
RUNTIME_ROOT="${RUNTIME_ROOT:-${WORKSPACE}/runtime}"
JAVA_LINK_TARGET="${JAVA_HOME:-/usr/lib/jvm/java-11-openjdk-amd64}"

ensure_parent_dir() {
  mkdir -p "$(dirname "$1")"
}

ensure_link() {
  local target="$1"
  local link_path="$2"

  ensure_parent_dir "${link_path}"
  if [[ -L "${link_path}" || -f "${link_path}" ]]; then
    rm -f "${link_path}"
  elif [[ -d "${link_path}" ]]; then
    rm -rf "${link_path}"
  fi
  ln -s "${target}" "${link_path}"
}

write_script() {
  local path="$1"
  shift
  cat > "${path}" <<EOF
$1
EOF
  chmod +x "${path}"
}

mkdir -p "${HOME_DIR}/logs" "${HOME_DIR}/installs"

# Legacy top-level paths expected by older Data Lab containers.
ensure_link "${HOME_DIR}/lakehouse" "${HOME_DIR}/bootcamp"
ensure_link "${JAVA_LINK_TARGET}" "${HOME_DIR}/jsdk"
ensure_link "${RUNTIME_ROOT}/hive/logs/metastore.log" "${HOME_DIR}/hive_metastore.out"
ensure_link "${RUNTIME_ROOT}/hive/logs/hiveserver2.log" "${HOME_DIR}/hiveserver2.out"

# Legacy logs folder with service log shortcuts.
ensure_link "../runtime/airflow/logs" "${HOME_DIR}/logs/airflow"
ensure_link "../runtime/hadoop/logs" "${HOME_DIR}/logs/hadoop"
ensure_link "../runtime/hive/logs" "${HOME_DIR}/logs/hive"
ensure_link "../runtime/kafka/logs" "${HOME_DIR}/logs/kafka"
ensure_link "../runtime/spark/logs" "${HOME_DIR}/logs/spark"
ensure_link "../runtime/postgres/logs" "${HOME_DIR}/logs/postgres"
ensure_link "../runtime/mongodb/logs" "${HOME_DIR}/logs/mongodb"
ensure_link "../runtime/lineage/logs" "${HOME_DIR}/logs/lineage"
ensure_link "../runtime/monitoring/logs" "${HOME_DIR}/logs/monitoring"

# Legacy helper wrappers.
write_script "${HOME_DIR}/startApps" '#!/usr/bin/env bash
set -euo pipefail
exec bash "/home/datalab/app/start" "$@"'

write_script "${HOME_DIR}/installAll" '#!/usr/bin/env bash
set -euo pipefail
exec bash "/home/datalab/app/start" --start-full-platform'

write_script "${HOME_DIR}/installshive" '#!/usr/bin/env bash
set -euo pipefail
exec bash "/home/datalab/app/start" --start-hive'

write_script "${HOME_DIR}/keygen.sh" '#!/usr/bin/env bash
set -euo pipefail
key_file="${1:-${HOME}/.ssh/id_ed25519}"
mkdir -p "$(dirname "${key_file}")"
if command -v ssh-keygen >/dev/null 2>&1; then
  if [[ -f "${key_file}" ]]; then
    echo "Key already exists: ${key_file}"
    exit 0
  fi
  exec ssh-keygen -t ed25519 -N "" -f "${key_file}"
fi
echo "[!] ssh-keygen is not installed in this image."
exit 1'

# Legacy installs directory shortcuts.
ensure_link "../installAll" "${HOME_DIR}/installs/installAll"
ensure_link "../installshive" "${HOME_DIR}/installs/installshive"
ensure_link "../startApps" "${HOME_DIR}/installs/startApps"
ensure_link "../app" "${HOME_DIR}/installs/current"
