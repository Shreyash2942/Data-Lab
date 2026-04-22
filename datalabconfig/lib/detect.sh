#!/usr/bin/env bash

config::detect_resources() {
  local payload
  payload="$(python3 - <<'PY'
import math
import os

def read_first(path):
    try:
        with open(path, "r", encoding="utf-8") as fh:
            return fh.read().strip()
    except OSError:
        return ""

def host_cpu():
    return max(1, os.cpu_count() or 1)

def host_mem_gib():
    mem_kib = 0
    try:
        with open("/proc/meminfo", "r", encoding="utf-8") as fh:
            for line in fh:
                if line.startswith("MemTotal:"):
                    parts = line.split()
                    mem_kib = int(parts[1])
                    break
    except OSError:
        pass
    if mem_kib <= 0:
        return 1.0
    return round(mem_kib / 1024 / 1024, 1)

def cpu_limit():
    cpu_max = read_first("/sys/fs/cgroup/cpu.max")
    if cpu_max:
      parts = cpu_max.split()
      if len(parts) == 2 and parts[0] != "max":
          quota = int(parts[0])
          period = int(parts[1])
          if quota > 0 and period > 0:
              return max(1, math.floor(quota / period))
    quota = read_first("/sys/fs/cgroup/cpu/cpu.cfs_quota_us")
    period = read_first("/sys/fs/cgroup/cpu/cpu.cfs_period_us")
    if quota and period and quota != "-1":
        quota_i = int(quota)
        period_i = int(period)
        if quota_i > 0 and period_i > 0:
            return max(1, math.floor(quota_i / period_i))
    return None

def mem_limit_gib():
    mem_max = read_first("/sys/fs/cgroup/memory.max")
    if mem_max and mem_max != "max":
        value = int(mem_max)
        if value > 0:
            return round(value / 1024 / 1024 / 1024, 1)
    mem_limit = read_first("/sys/fs/cgroup/memory/memory.limit_in_bytes")
    if mem_limit:
        value = int(mem_limit)
        if 0 < value < (1 << 60):
            return round(value / 1024 / 1024 / 1024, 1)
    return None

host_cpu_count = host_cpu()
host_mem = host_mem_gib()
limit_cpu = cpu_limit()
limit_mem = mem_limit_gib()

effective_cpu = min(host_cpu_count, limit_cpu) if limit_cpu is not None else host_cpu_count
effective_mem = min(host_mem, limit_mem) if limit_mem is not None else host_mem
source = "cgroup" if (limit_cpu is not None or limit_mem is not None) else "host"

print(f"HOST_CPU={host_cpu_count}")
print(f"HOST_MEMORY_GIB={host_mem}")
print(f"EFFECTIVE_CPU={effective_cpu}")
print(f"EFFECTIVE_MEMORY_GIB={effective_mem}")
print(f"DETECTION_SOURCE={source}")
PY
)"

  while IFS='=' read -r key value; do
    key="$(strip_cr "${key}")"
    value="$(strip_cr "${value}")"
    case "${key}" in
      HOST_CPU) CONFIG_HOST_CPU="${value}" ;;
      HOST_MEMORY_GIB) CONFIG_HOST_MEMORY_GIB="${value}" ;;
      EFFECTIVE_CPU) CONFIG_EFFECTIVE_CPU="${value}" ;;
      EFFECTIVE_MEMORY_GIB) CONFIG_EFFECTIVE_MEMORY_GIB="${value}" ;;
      DETECTION_SOURCE) CONFIG_DETECTION_SOURCE="${value}" ;;
    esac
  done <<< "${payload}"

  export CONFIG_HOST_CPU CONFIG_HOST_MEMORY_GIB CONFIG_EFFECTIVE_CPU CONFIG_EFFECTIVE_MEMORY_GIB CONFIG_DETECTION_SOURCE
}

config::show_detected_resources() {
  config::detect_resources
  config::print_heading "Data Lab Config :: Detect"
  config::print_section "Host Resources"
  config::print_row "Host logical CPU" "${CONFIG_HOST_CPU}"
  config::print_row "Host memory (GiB)" "${CONFIG_HOST_MEMORY_GIB}"
  config::print_section "Container-Effective Resources"
  config::print_row "Effective logical CPU" "${CONFIG_EFFECTIVE_CPU}"
  config::print_row "Effective memory (GiB)" "${CONFIG_EFFECTIVE_MEMORY_GIB}"
  config::print_row "Detection source" "${CONFIG_DETECTION_SOURCE}"
  config::print_section "Guardrails"
  config::print_row "Spark worker core limit" "$(config::spark_worker_core_limit) ($(config::spark_cpu_limit_percent)% of effective CPU)"
}
