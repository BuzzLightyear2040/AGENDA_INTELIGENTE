-- Teste das regras RLS em um Postgres local que imita o Supabase.
-- Uso: psql -f supabase/tests/supabase_emulation.sql; psql -f supabase/migrations/20261025000000_agenda_schema.sql; psql -f supabase/tests/rls_test.sql
-- Cada bloco mostra o resultado esperado (contagens ou ERROR de RLS).
\set ON_ERROR_STOP 0
\set QUIET 1
-- helpers
create or replace function pg_temp.as_user(u text) returns void language plpgsql as $$ begin perform set_config('request.jwt.claim.sub', u, false); execute 'set role authenticated'; end $$;
\echo '--- 1. Enrique cria organização e vira admin'
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
select public.agenda_create_org('Agenda Enrique') as org \gset
insert into agenda_professionals (org_id,id,name,crm) values (:'org',1,'Dr. Enrique','1/RS'),(:'org',2,'Dra. Maria','2/RS');
update agenda_members set prof_id = 1 where org_id = :'org' and user_id = auth.uid();
insert into agenda_locations (org_id,id,name,city,lat,lng,hourly_rate,shift_hours,shift_start) values (:'org',10,'Hosp Jaboticaba','Jaboticaba - RS',-27.6,-53.2,100,24,420);
insert into agenda_events (org_id,id,prof_id,loc_id,day,text,type,hours) values (:'org',100,1,10,'2026-10-12','das 07h às 24h','plantao',17),(:'org',101,2,10,'2026-10-13','das 08h às 12h','plantao',4);
select count(*) as enrique_ve_eventos from agenda_events;
insert into agenda_invites (org_id,email,prof_id) values (:'org','maria@x.com',2),(:'org','naoconfirmado@x.com',2);
reset role;
\echo '--- 2. Maria aceita convite: vê só os próprios eventos'
select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
select public.agenda_accept_invites() as aceitos;
select role, prof_id from agenda_members where user_id = auth.uid();
select count(*) as maria_ve_eventos from agenda_events;
select count(*) as maria_ve_profs from agenda_professionals;
\echo '   Maria tenta lançar para o Enrique (deve FALHAR):'
insert into agenda_events (org_id,id,prof_id,loc_id,day,text) values (:'org',102,1,10,'2026-10-14','x');
\echo '   Maria lança para si (OK):'
insert into agenda_events (org_id,id,prof_id,loc_id,day,text) values (:'org',103,2,10,'2026-10-14','das 8 às 9');
\echo '   Maria tenta mudar evento dela para o Enrique (deve FALHAR):'
update agenda_events set prof_id = 1 where id = 103;
\echo '   Maria tenta se promover a admin (0 linhas / falha):'
update agenda_members set role = 'admin' where user_id = auth.uid();
select role from agenda_members where user_id = auth.uid();
\echo '   Maria cria local por voz (OK) e tenta excluir local (0 linhas):'
insert into agenda_locations (org_id,id,name) values (:'org',11,'Tapera');
delete from agenda_locations where id = 10;
select count(*) as locais from agenda_locations;
\echo '   Maria tenta forjar updated_by:'
update agenda_events set updated_by = '11111111-1111-1111-1111-111111111111', text = 'das 8 às 10' where id = 103;
reset role; select updated_by = '22222222-2222-2222-2222-222222222222' as autor_correto from agenda_events where id = 103;
\echo '--- 3. Intruso não vê nada e não entra'
select pg_temp.as_user('33333333-3333-3333-3333-333333333333');
select count(*) as intruso_eventos from agenda_events;
select count(*) as intruso_orgs from agenda_orgs;
insert into agenda_members (org_id,user_id,role) values (:'org',auth.uid(),'admin');
insert into agenda_events (org_id,id,prof_id,loc_id,day) values (:'org',104,1,10,'2026-10-15');
select public.agenda_claim_professional(:'org', 5, 'Intruso');
select public.agenda_accept_invites() as intruso_aceitos;
reset role;
\echo '--- 4. E-mail não confirmado não aceita convite'
select pg_temp.as_user('44444444-4444-4444-4444-444444444444');
select public.agenda_accept_invites() as nao_confirmado_aceitos;
reset role;
\echo '--- 5. anon não acessa'
set role anon; select count(*) from agenda_events; reset role;
\echo '--- 6. Último admin não pode sair'
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
delete from agenda_members where user_id = auth.uid();
\echo '--- 7. Excluir profissional apaga eventos em cascata; excluir org funciona'
delete from agenda_professionals where id = 2;
select count(*) as eventos_restantes from agenda_events;
delete from agenda_orgs where id = :'org';
select count(*) as orgs from agenda_orgs;
reset role;
