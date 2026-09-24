-- LoadFlow - módulo de carregamento para o MESMO projeto Supabase do DockFlow.
-- Não altera nem apaga dados do DockFlow atual.
create extension if not exists pgcrypto;

create table if not exists public.loading_docks (
  id bigint generated always as identity primary key,
  name text not null unique,
  enabled boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.loading_tickets (
  id uuid primary key default gen_random_uuid(),
  tracking_token uuid not null unique default gen_random_uuid(),
  number bigint generated always as identity unique,
  first_name text not null,
  last_name text not null,
  plate text not null,
  load_number text not null,
  status text not null default 'waiting' check (status in ('waiting','called','done','cancelled')),
  dock_id bigint references public.loading_docks(id),
  created_at timestamptz not null default now(),
  called_at timestamptz,
  finished_at timestamptz
);

create table if not exists public.loading_push_subscriptions (
  id bigint generated always as identity primary key,
  ticket_id uuid not null references public.loading_tickets(id) on delete cascade,
  endpoint text not null unique,
  p256dh text not null,
  auth text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists loading_active_plate_idx on public.loading_tickets(plate) where status in ('waiting','called');
create unique index if not exists loading_active_load_idx on public.loading_tickets(load_number) where status in ('waiting','called');
create unique index if not exists loading_active_dock_idx on public.loading_tickets(dock_id) where status='called';
create index if not exists loading_waiting_idx on public.loading_tickets(created_at,number) where status='waiting';
create index if not exists loading_created_idx on public.loading_tickets(created_at desc);

insert into public.loading_docks(name) values ('Doca 01'),('Doca 02'),('Doca 03'),('Doca 04') on conflict(name) do nothing;

alter table public.loading_docks enable row level security;
alter table public.loading_tickets enable row level security;
alter table public.loading_push_subscriptions enable row level security;
revoke all on public.loading_docks, public.loading_tickets, public.loading_push_subscriptions from anon, authenticated;

create or replace function public.loading_driver_checkin(p_first_name text,p_last_name text,p_plate text,p_load_number text)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_first text:=btrim(p_first_name);v_last text:=btrim(p_last_name);
 v_plate text:=upper(regexp_replace(coalesce(p_plate,''),'[^a-zA-Z0-9]','','g'));
 v_load text:=upper(btrim(coalesce(p_load_number,'')));v_ticket public.loading_tickets;
begin
 if v_first is null or length(v_first) not between 2 and 60 or v_last is null or length(v_last) not between 2 and 80 then
   raise exception 'Informe nome e sobrenome válidos.' using errcode='P0001'; end if;
 if v_plate !~ '^[A-Z]{3}[0-9][A-Z0-9][0-9]{2}$' then raise exception 'Informe uma placa brasileira válida.' using errcode='P0001'; end if;
 if v_load !~ '^[A-Z0-9._/-]{2,40}$' then raise exception 'Informe um número de Load válido.' using errcode='P0001'; end if;
 insert into public.loading_tickets(first_name,last_name,plate,load_number) values(v_first,v_last,v_plate,v_load) returning * into v_ticket;
 return jsonb_build_object('tracking_token',v_ticket.tracking_token,'number',v_ticket.number);
exception when unique_violation then
 if exists(select 1 from public.loading_tickets where load_number=v_load and status in('waiting','called')) then
   raise exception 'Esta Load já está aguardando ou em carregamento.' using errcode='P0001';
 else raise exception 'Esta placa já está aguardando ou em carregamento.' using errcode='P0001'; end if;
end $$;
revoke all on function public.loading_driver_checkin(text,text,text,text) from public;
grant execute on function public.loading_driver_checkin(text,text,text,text) to anon,authenticated;

create or replace function public.loading_driver_status(p_token uuid)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v public.loading_tickets;v_pos bigint;v_dock text;
begin
 select * into v from public.loading_tickets where tracking_token=p_token;
 if not found then return null; end if;
 if v.status='waiting' then select count(*) into v_pos from public.loading_tickets where status='waiting' and (created_at,number)<=(v.created_at,v.number); end if;
 select name into v_dock from public.loading_docks where id=v.dock_id;
 return jsonb_build_object('number',v.number,'plate',v.plate,'load_number',v.load_number,'status',v.status,'position',v_pos,'dock',v_dock,'created_at',v.created_at,'called_at',v.called_at,'finished_at',v.finished_at);
end $$;
revoke all on function public.loading_driver_status(uuid) from public;
grant execute on function public.loading_driver_status(uuid) to anon,authenticated;

create or replace function public.loading_driver_save_push_subscription(p_token uuid,p_endpoint text,p_p256dh text,p_auth text)
returns void language plpgsql security definer set search_path=''
as $$
declare v_id uuid;
begin
 select id into v_id from public.loading_tickets where tracking_token=p_token and status in('waiting','called');
 if not found then raise exception 'Senha não está ativa.' using errcode='P0001'; end if;
 insert into public.loading_push_subscriptions(ticket_id,endpoint,p256dh,auth)
 values(v_id,p_endpoint,p_p256dh,p_auth)
 on conflict(endpoint) do update set ticket_id=excluded.ticket_id,p256dh=excluded.p256dh,auth=excluded.auth,updated_at=now();
end $$;
revoke all on function public.loading_driver_save_push_subscription(uuid,text,text,text) from public;
grant execute on function public.loading_driver_save_push_subscription(uuid,text,text,text) to anon,authenticated;

create or replace function public.loading_admin_dashboard()
returns jsonb language plpgsql security definer set search_path=''
as $$
declare d jsonb;t jsonb;
begin
 if not public.is_dock_admin() then raise exception 'Acesso não autorizado.' using errcode='42501'; end if;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]'::jsonb) into d from (select id,name,enabled from public.loading_docks) x;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at,x.number),'[]'::jsonb) into t from (
   select id,number,first_name,last_name,plate,load_number,status,dock_id,created_at,called_at,finished_at
   from public.loading_tickets
   where status in('waiting','called') or created_at >= date_trunc('day',now() at time zone 'America/Sao_Paulo') at time zone 'America/Sao_Paulo'
   order by created_at,number limit 1000
 ) x;
 return jsonb_build_object('docks',d,'tickets',t);
end $$;
revoke all on function public.loading_admin_dashboard() from public;
grant execute on function public.loading_admin_dashboard() to authenticated;

create or replace function public.loading_admin_call_next(p_dock_id bigint)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v public.loading_tickets;d public.loading_docks;
begin
 if not public.is_dock_admin() then raise exception 'Acesso não autorizado.' using errcode='42501'; end if;
 select * into d from public.loading_docks where id=p_dock_id for update;
 if not found or not d.enabled then raise exception 'Doca indisponível.' using errcode='P0001'; end if;
 if exists(select 1 from public.loading_tickets where dock_id=p_dock_id and status='called') then raise exception 'A doca já está ocupada.' using errcode='P0001'; end if;
 select * into v from public.loading_tickets where status='waiting' order by created_at,number limit 1 for update skip locked;
 if not found then raise exception 'Não há motoristas na fila.' using errcode='P0001'; end if;
 update public.loading_tickets set status='called',dock_id=p_dock_id,called_at=now() where id=v.id returning * into v;
 return jsonb_build_object('ticket_id',v.id,'number',v.number,'plate',v.plate,'load_number',v.load_number,'dock',d.name);
end $$;
revoke all on function public.loading_admin_call_next(bigint) from public;
grant execute on function public.loading_admin_call_next(bigint) to authenticated;

create or replace function public.loading_admin_finish(p_ticket_id uuid)
returns void language plpgsql security definer set search_path=''
as $$
begin
 if not public.is_dock_admin() then raise exception 'Acesso não autorizado.' using errcode='42501'; end if;
 update public.loading_tickets set status='done',finished_at=now() where id=p_ticket_id and status='called';
 if not found then raise exception 'Carregamento não encontrado.' using errcode='P0001'; end if;
end $$;
revoke all on function public.loading_admin_finish(uuid) from public;
grant execute on function public.loading_admin_finish(uuid) to authenticated;

create or replace function public.loading_admin_cancel(p_ticket_id uuid)
returns void language plpgsql security definer set search_path=''
as $$
begin
 if not public.is_dock_admin() then raise exception 'Acesso não autorizado.' using errcode='42501'; end if;
 update public.loading_tickets set status='cancelled',finished_at=now() where id=p_ticket_id and status in('waiting','called');
 if not found then raise exception 'Registro não está ativo.' using errcode='P0001'; end if;
end $$;
revoke all on function public.loading_admin_cancel(uuid) from public;
grant execute on function public.loading_admin_cancel(uuid) to authenticated;
