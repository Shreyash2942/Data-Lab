# Java Layer

Java 11 (OpenJDK) is installed globally in the container. Project samples live under `~/java`, which mirrors `repo_root/java`.

## Layout

| Path | Purpose |
| --- | --- |
| `java/Example.java` | Simple class that prints version info; use it as your starting point. |
| `java/build.sh` *(optional)* | Create one if you prefer scripted builds or Gradle/Maven wrappers. |

Feel free to add packages or subdirectories; everything under `java/` is mounted into the container automatically.

## Running the sample

```bash
cd ~/java
javac Example.java
java -cp . Example
```

Alternatively, the helper menu exposes option `5` (or `bash ~/app/services_demo.sh --run-java-example`) to compile/run the demo automatically.

## Notes

- `$JAVA_HOME` is set to `/usr/lib/jvm/java-11-openjdk-amd64`, and `JAVA_HOME/bin` is already on `PATH`.
- Place build artifacts or logs in `~/runtime/java` (create as needed) so they persist on the host and remain outside git.
- For larger apps, drop a `pom.xml` or `build.gradle` in this directory and run Maven/Gradle directly inside the container.

## Resources

- Official docs: https://openjdk.org/projects/jdk/11/
