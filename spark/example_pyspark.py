from pyspark.sql import SparkSession

spark = SparkSession.builder.appName("data-lab-monolithic-example").getOrCreate()
df = spark.createDataFrame([(1, "alpha"), (2, "beta")], ["id", "value"])
df.show()
spark.stop()
