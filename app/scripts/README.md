# app/scripts — Control Scripts (Single Container)

These scripts now focus on running examples inside the single `data-lab` container.

- `services_start.sh`   — interactive tech-stack launcher; option 3 starts the core Spark/Hadoop/Hive/Kafka services (use `services_start.sh --start-core` / `--stop-core` for automation) and option 11 runs all stack demos
- `services_stop.sh`    — stop menu for all tech stack services (and optional container stop)
- `services_restart.sh` — restart menu for services/container
- `services_update.sh`  — rebuild image with additional options to start services and run demos
