-- 刪除帳號(App Store Guideline 5.1.1(v):可建帳號的 App 必須能在 App 內刪帳號)。
--
-- 只刪 auth.users 自己那一列:所有使用者資料表的 user_id 都
-- `references auth.users (id) on delete cascade`(見 schema migration),
-- 子表再經 workout/template 的 cascade 一併刪除,一個 statement 內完成。
--
-- 這支刻意是 security definer(其他 RPC 一律 invoker):authenticated 角色
-- 對 auth schema 沒有刪除權。範圍由 auth.uid() 釘死,只能刪呼叫者自己。
-- search_path 清空 + 全部 schema 限定名稱,防 search_path 劫持。
--
-- Apple 授權撤銷(revoke token)不在這裡:需要 Apple client secret(.p8),
-- 待 Mike 提供後另做(見 .claude/wip.md)。

create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  delete from auth.users where id = v_uid;
end;
$$;

revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;
