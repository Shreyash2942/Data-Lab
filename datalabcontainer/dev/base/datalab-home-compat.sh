#!/usr/bin/env bash

if [ -z "${BASH_VERSION:-}" ]; then
  return 0 2>/dev/null || exit 0
fi

__datalab_legacy_home_ls() {
  if [[ "${PWD:-}" == "${HOME:-}" ]]; then
    local has_path_arg=0
    local arg
    for arg in "$@"; do
      case "${arg}" in
        -*) ;;
        *) has_path_arg=1; break ;;
      esac
    done

    if [[ "${has_path_arg}" -eq 0 ]]; then
      if [[ "$#" -eq 0 ]]; then
        local ordered_entries=(
          airflow
          bootcamp
          hadoop
          hive
          hive_metastore.out
          hiveserver2.out
          installAll
          installs
          installshive
          jsdk
          kafka
          keygen.sh
          logs
          spark
          startApps
        )
        local hidden_entries=(
          app
          dbt
          java
          lakehouse
          mongodb
          postgres
          python
          redis
          runtime
          scala
          terraform
        )
        local entry
        local hidden
        local skip

        for entry in "${ordered_entries[@]}"; do
          [[ -e "${entry}" || -L "${entry}" ]] && printf '%s\n' "${entry}"
        done

        while IFS= read -r entry; do
          [[ -z "${entry}" ]] && continue
          skip=0
          for hidden in "${hidden_entries[@]}"; do
            [[ "${entry}" == "${hidden}" ]] && skip=1 && break
          done
          [[ "${skip}" -eq 1 ]] && continue
          for hidden in "${ordered_entries[@]}"; do
            [[ "${entry}" == "${hidden}" ]] && skip=1 && break
          done
          [[ "${skip}" -eq 0 ]] && printf '%s\n' "${entry}"
        done < <(command ls -1)
      else
        command ls \
          --group-directories-first \
          --hide=app \
          --hide=dbt \
          --hide=java \
          --hide=lakehouse \
          --hide=mongodb \
          --hide=postgres \
          --hide=python \
          --hide=redis \
          --hide=runtime \
          --hide=scala \
          --hide=terraform \
          "$@"
      fi
      return
    fi
  fi

  command ls "$@"
}

alias ls='__datalab_legacy_home_ls'
