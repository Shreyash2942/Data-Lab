CREATE TABLE IF NOT EXISTS demo_customers (
  id SERIAL PRIMARY KEY,
  name TEXT NOT NULL,
  city TEXT NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

INSERT INTO demo_customers (name, city)
VALUES
  ('Ava', 'San Francisco'),
  ('Liam', 'Austin'),
  ('Noah', 'Chicago')
ON CONFLICT DO NOTHING;

SELECT id, name, city, created_at
FROM demo_customers
ORDER BY id;
