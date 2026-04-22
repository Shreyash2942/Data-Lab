# Iceberg Query (Trino + Superset)

Use one Superset connection (`Trino Lakehouse`) and query with 2-part names.

## 1) Start services

```bash
su - datalab
/home/datalab/app/start --start-lakehouse-stack
```

## 2) Create/refresh demo assets

```bash
datalab_app --setup-lakehouse-demo
```

## 3) Query Iceberg table in SQL Lab

```sql
SHOW TABLES FROM demo_iceberg;
SELECT * FROM demo_iceberg.iceberg_table;
```
