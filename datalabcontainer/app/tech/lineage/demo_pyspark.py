#!/usr/bin/env python3
from pyspark.sql import SparkSession
from pyspark.sql import functions as F
from pathlib import Path

base = Path('/home/datalab/runtime/lineage/demo')
bronze = base / 'bronze'
silver = base / 'silver'
base.mkdir(parents=True, exist_ok=True)

spark = SparkSession.builder.appName('datalab-lineage-demo').getOrCreate()
source_df = (
    spark.range(0, 10)
    .withColumn('category', F.when(F.col('id') % 2 == 0, F.lit('even')).otherwise(F.lit('odd')))
    .withColumn('label', F.concat(F.lit('row_'), F.col('id').cast('string')))
)
source_df.write.mode('overwrite').parquet(str(bronze))

filtered_df = (
    spark.read.parquet(str(bronze))
    .filter(F.col('id') >= 5)
    .withColumn('batch_name', F.lit('phase4_demo'))
)
filtered_df.write.mode('overwrite').parquet(str(silver))
print(f'Lineage demo rows: {filtered_df.count()}')
print(f'Bronze path: {bronze}')
print(f'Silver path: {silver}')
spark.stop()