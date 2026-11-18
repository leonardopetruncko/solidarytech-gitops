-- Roda como usuário master do RDS, no banco "postgres". Idempotente.
-- Menor privilégio: cada serviço tem o próprio usuário, dono só do próprio banco.
SELECT format('CREATE ROLE %I LOGIN', :'app_user')
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = :'app_user') \gexec
SELECT format('ALTER ROLE %I PASSWORD %L', :'app_user', :'app_pass') \gexec
-- No RDS o master precisa ser membro do papel para criar um banco com esse dono.
SELECT format('GRANT %I TO CURRENT_USER', :'app_user') \gexec
SELECT format('CREATE DATABASE %I OWNER %I', :'db_name', :'app_user')
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = :'db_name') \gexec
SELECT format('REVOKE ALL ON DATABASE %I FROM PUBLIC', :'db_name') \gexec