-- Clients may only send the row's content. id, user_id (auth.uid() default) and received_at
-- (now() default) are server-owned: a client cannot backdate receipt or name another user.
revoke insert on table public.app_logs from authenticated;
grant insert (occurred_at, session_id, level, event, properties, app_version, os_version)
    on table public.app_logs to authenticated;
