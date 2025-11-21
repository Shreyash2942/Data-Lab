import os
from pathlib import Path
from pyspark.sql import SparkSession

RUNTIME_ROOT = Path(os.environ.get("RUNTIME_ROOT", Path.home() / "runtime"))
HUDI_BASE_PATH = RUNTIME_ROOT / "lakehouse" / "hudi_tables" / "users"


def log(msg: str) -> None:
    print(f"[*] {msg}")


def build_spark() -> SparkSession:
    return (
        SparkSession.builder.appName("data-lab-hudi-demo")
        .config("spark.serializer", "org.apache.spark.serializer.KryoSerializer")
        .config("spark.sql.hive.convertMetastoreParquet", "false")
        .getOrCreate()
    )


def write_batch(df, mode="overwrite"):
    (
        df.write.format("hudi")
        .option("hoodie.table.name", "users_hudi")
        .option("hoodie.datasource.write.recordkey.field", "id")
        .option("hoodie.datasource.write.precombine.field", "ts")
        .option("hoodie.datasource.write.operation", "upsert")
        .mode(mode)
        .save(str(HUDI_BASE_PATH))
    )


def main():
    spark = build_spark()
    spark.sparkContext.setLogLevel("WARN")
    HUDI_BASE_PATH.parent.mkdir(parents=True, exist_ok=True)

    log("Writing initial snapshot (3 users)...")
    initial = spark.createDataFrame(
        [
            (1, "Alice", "2025-11-12"),
            (2, "Bob", "2025-11-12"),
            (3, "Charlie", "2025-11-12"),
        ],
        ["id", "name", "ts"],
    )
    write_batch(initial, mode="overwrite")
    (
        spark.read.format("hudi")
        .load(str(HUDI_BASE_PATH))
        .select("id", "name", "ts")
        .orderBy("id")
        .show()
    )

    log("Upserting a new user and an updated timestamp for Bob...")
    updates = spark.createDataFrame(
        [
            (2, "Bob", "2025-11-13"),
            (4, "Dana", "2025-11-13"),
        ],
        ["id", "name", "ts"],
    )
    write_batch(updates, mode="append")

    log("Current Hudi table contents (with commit timestamps)...")
    current = spark.read.format("hudi").load(str(HUDI_BASE_PATH))
    current.select("_hoodie_commit_time", "id", "name", "ts").orderBy("id").show()

    spark.stop()
    log(f"Finished. Data files live under: {HUDI_BASE_PATH}")


if __name__ == "__main__":
    main()
