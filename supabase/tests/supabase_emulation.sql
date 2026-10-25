-- Emulação mínima do Supabase (schema auth, auth.uid(), papéis) para testes locais. NÃO executar no Supabase real.
create role anon nologin; create role authenticated nologin;
create schema auth;
create table auth.users (id uuid primary key, email text, email_confirmed_at timestamptz);
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
grant usage on schema auth to anon, authenticated;
grant usage on schema public to anon, authenticated;
grant select on auth.users to authenticated; -- (no Supabase real o FK só precisa de referência)
insert into auth.users values ('11111111-1111-1111-1111-111111111111','enrique@x.com',now()),
 ('22222222-2222-2222-2222-222222222222','maria@x.com',now()),
 ('33333333-3333-3333-3333-333333333333','intruso@x.com',now()),
 ('44444444-4444-4444-4444-444444444444','naoconfirmado@x.com',null);
