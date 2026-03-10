# Delta Query (Trino + Superset)

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

## 3) Query Delta table in SQL Lab

```sql
SHOW TABLES FROM demo_delta;
SELECT * FROM demo_delta.table_delta;
```
