import os
from pathlib import Path
from pyspark.sql import SparkSession

RUNTIME_ROOT = Path(os.environ.get("RUNTIME_ROOT", Path.home() / "runtime"))
DELTA_PATH = RUNTIME_ROOT / "lakehouse" / "delta_tables" / "customers"
DELTA_VERSION = os.environ.get("DELTA_VERSION", "3.2.0")
DELTA_PACKAGES = f"io.delta:delta-spark_2.12:{DELTA_VERSION},io.delta:delta-storage:{DELTA_VERSION}"
LOCAL_JARS = [
    Path.home() / ".ivy2" / "jars" / f"io.delta_delta-spark_2.12-{DELTA_VERSION}.jar",
    Path.home() / ".ivy2" / "jars" / f"io.delta_delta-storage-{DELTA_VERSION}.jar",
]


def log(msg: str) -> None:
    print(f"[*] {msg}")


def build_spark() -> SparkSession:
    local_jars = [str(p) for p in LOCAL_JARS if p.exists()]
    jars_conf = ",".join(local_jars) if local_jars else None
    extra_classpath = ":".join(local_jars) if local_jars else None

    builder = (
        SparkSession.builder.appName("data-lab-delta-demo")
        # Force local master for the demo so driver picks up the jars we ship/resolve.
        .config("spark.master", "local[*]")
        .config("spark.sql.extensions", "io.delta.sql.DeltaSparkSessionExtension")
        .config(
            "spark.sql.catalog.spark_catalog",
            "org.apache.spark.sql.delta.catalog.DeltaCatalog",
        )
    )
    # Ensure both delta-spark and delta-storage are on the classpath.
    if jars_conf:
        builder = builder.config("spark.jars", jars_conf)
        builder = builder.config("spark.driver.extraClassPath", extra_classpath)
        builder = builder.config("spark.executor.extraClassPath", extra_classpath)
    builder = builder.config("spark.jars.packages", DELTA_PACKAGES)
    return builder.getOrCreate()


def main():
    spark = build_spark()
    spark.sparkContext.setLogLevel("WARN")
    DELTA_PATH.parent.mkdir(parents=True, exist_ok=True)

    log("Writing initial Delta Lake table...")
    initial = spark.createDataFrame(
        [
            (1, "Notebook", 999.0),
            (2, "Keyboard", 79.5),
            (3, "Mouse", 25.0),
        ],
        ["id", "item", "price"],
    )
    initial.write.format("delta").mode("overwrite").save(str(DELTA_PATH))
    spark.read.format("delta").load(str(DELTA_PATH)).orderBy("id").show()

    log("Upserting price adjustments (id=2) and a new product...")
    updates = spark.createDataFrame(
        [
            (2, "Keyboard", 85.0),
            (4, "Monitor", 210.0),
        ],
        ["id", "item", "price"],
    )
    updates.write.format("delta").mode("append").save(str(DELTA_PATH))
    spark.read.format("delta").load(str(DELTA_PATH)).orderBy("id").show()

    log("DESCRIBE HISTORY output:")
    spark.sql(f"DESCRIBE HISTORY delta.`{str(DELTA_PATH)}`").select("version", "timestamp").show()

    log("Reading Delta table as version 0 (before upsert)...")
    (
        spark.read.format("delta")
        .option("versionAsOf", 0)
        .load(str(DELTA_PATH))
        .orderBy("id")
        .show()
    )

    spark.stop()
    log(f"Delta table stored at: {DELTA_PATH}")


if __name__ == "__main__":
    main()
