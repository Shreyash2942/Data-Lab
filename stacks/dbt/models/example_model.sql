{{ config(materialized='table' if target.type == 'hive' else 'view') }}

select 1 as id, 'hello from dbt in monolithic lab' as message
