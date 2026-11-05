-- ============================================================
-- ZAssist: схема базы Supabase
-- Выполните этот скрипт целиком в SQL Editor вашего проекта
-- на supabase.com (SQL Editor → New query → вставить → Run).
-- ============================================================

-- Проекты (чаты) пользователя
create table if not exists public.projects (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  title text not null default 'Новый проект',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Сообщения внутри проекта
create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  role text not null check (role in ('user', 'assistant', 'system')),
  content text not null,
  created_at timestamptz not null default now()
);

-- Каждый видит и меняет только свои данные
alter table public.projects enable row level security;
alter table public.messages enable row level security;

drop policy if exists "Свои проекты" on public.projects;
create policy "Свои проекты" on public.projects
  for all to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "Свои сообщения" on public.messages;
create policy "Свои сообщения" on public.messages
  for all to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Индексы для быстрой загрузки списков и чатов
create index if not exists projects_user_idx on public.projects (user_id, created_at desc);
create index if not exists messages_project_idx on public.messages (project_id, created_at);
