# Scala Layer

Scala 2.13 (matching the Kafka stack) is available system-wide. Example sources live under `~/scala`, mirrored from `repo_root/scala`.

## Layout

| Path | Purpose |
| --- | --- |
| `scala/example.scala` | Minimal `object HelloDataLab` entry point demonstrating stdout + args. |

Add more `.scala` files or organize packages just as you would in a regular project; everything in this folder is mounted into the container.

## Running the sample

```bash
cd ~/scala
scalac example.scala
scala -cp . HelloDataLab
```

Menu helper: `bash ~/app/services_demo.sh --run-scala-example` (option `6`).

## Notes

- `scalac` and `scala` CLIs are on `PATH`.
- For SBT users, drop an `sbt` project here and run `sbt run` inside the container; the JVM + Scala toolchain is already available.
- Store build outputs/logs in `~/runtime/scala` if you need persistence outside git.

## Resources

- Official docs: https://docs.scala-lang.org/
