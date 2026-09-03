-- Yamo V219 — production system-message automation engine
-- Run after V218. Safe to run more than once.
begin;

insert into public.yamo_admin_permissions(permission,label_ar,category) values
('system_messages.read','عرض رسائل النظام التلقائية','engagement'),
('system_messages.manage','إدارة رسائل النظام التلقائية','engagement'),
('system_messages.test','تجربة رسائل النظام','engagement')
on conflict(permission) do update set label_ar=excluded.label_ar,category=excluded.category;
insert into public.yamo_admin_role_permissions(role,permission) values
('super_admin','system_messages.read'),('super_admin','system_messages.manage'),('super_admin','system_messages.test'),
('admin','system_messages.read'),('admin','system_messages.manage'),('admin','system_messages.test') on conflict do nothing;

create table if not exists public.yamo_system_message_templates(
  event_key text primary key,
  category text not null,
  title_ar text not null,
  title_en text,
  body_ar text not null,
  body_en text,
  image_url text,
  deep_link text,
  channels text[] not null default array['in_app','push'],
  enabled boolean not null default true,
  cooldown_minutes integer not null default 0 check(cooldown_minutes>=0),
  max_retries integer not null default 3 check(max_retries between 0 and 10),
  variables text[] not null default '{}',
  description_ar text not null default '',
  updated_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.yamo_system_message_deliveries(
  id uuid primary key default gen_random_uuid(),
  event_key text not null references public.yamo_system_message_templates(event_key),
  user_id uuid not null references public.profiles(id),
  event_id text not null,
  payload jsonb not null default '{}',
  rendered_title text not null,
  rendered_body text not null,
  image_url text,
  deep_link text,
  channels text[] not null default '{}',
  status text not null default 'queued' check(status in('queued','sent','delivered','read','clicked','failed','cancelled')),
  attempt_count integer not null default 0,
  last_error text,
  notification_id text,
  queued_at timestamptz not null default now(),
  sent_at timestamptz,
  delivered_at timestamptz,
  read_at timestamptz,
  clicked_at timestamptz,
  unique(event_key,user_id,event_id)
);
create index if not exists yamo_system_deliveries_status_idx on public.yamo_system_message_deliveries(status,queued_at);
create index if not exists yamo_system_deliveries_user_idx on public.yamo_system_message_deliveries(user_id,queued_at desc);
alter table public.yamo_system_message_templates enable row level security;
alter table public.yamo_system_message_deliveries enable row level security;

insert into public.yamo_system_message_templates(event_key,category,title_ar,title_en,body_ar,body_en,deep_link,cooldown_minutes,variables,description_ar) values
('account.registered','الحساب','أهلًا {user_name} في يامو','Welcome to Yamo','تم إنشاء حسابك بنجاح. ابدأ واكتشف مجتمع يامو.','Your account was created successfully.','yamo://home',1440,array['user_name'],'أول تسجيل للحساب'),
('account.welcome','الحساب','مرحبًا بعودتك يا {user_name}','Welcome back','وحشتنا! شوف الجديد في يامو الآن.','See what is new on Yamo.','yamo://home',10080,array['user_name'],'رسالة عودة بعد عدم النشاط'),
('agency.join_requested','الوكالة','طلب انضمام جديد','New agency request','{user_name} أرسل طلب انضمام إلى وكالة {agency_name}.','A new host requested to join your agency.','yamo://agency/requests',0,array['user_name','agency_name'],'يصل إلى الوكيل'),
('agency.host_linked','الوكالة','تم ربطك بالوكالة','Agency linked','تم ربط حسابك بوكالة {agency_name} بنجاح.','Your account is now linked to the agency.','yamo://agency',0,array['agency_name'],'يصل للمضيف'),
('agency.request_accepted','الوكالة','تم قبول طلبك','Request accepted','أصبحت الآن ضمن وكالة {agency_name}.','Your agency request was accepted.','yamo://agency',0,array['agency_name'],'قبول المضيف'),
('agency.request_rejected','الوكالة','لم يتم قبول الطلب','Request declined','لم يتم قبول طلب الانضمام إلى {agency_name}.','Your agency request was declined.','yamo://agency',0,array['agency_name'],'رفض المضيف'),
('target.progress_25','التارجت','وصلت إلى 25% من التارجت','Target 25%','حققت {current_value} من {target_value}. استمر!','You reached 25% of your target.','yamo://income/target',10080,array['current_value','target_value'],'ربع التارجت'),
('target.progress_50','التارجت','نصف التارجت اتحقق','Target 50%','وصلت إلى 50%، باقي {remaining_value}.','You reached 50% of your target.','yamo://income/target',10080,array['remaining_value'],'نصف التارجت'),
('target.progress_75','التارجت','قربت تحقق التارجت','Target 75%','وصلت إلى 75%، كمل علشان تستلم مكافأتك.','You reached 75% of your target.','yamo://income/target',10080,'{}','ثلاثة أرباع التارجت'),
('target.completed','التارجت','مبروك! حققت التارجت','Target completed','حققت تارجت {period_name} واستحققت {reward}.','You completed your target.','yamo://income/target',0,array['period_name','reward'],'تحقيق التارجت للمضيف والوكيل'),
('target.expiring','التارجت','التارجت قرب ينتهي','Target ending soon','متبقي {remaining_time} لإكمال {remaining_value}.','Your target period is ending soon.','yamo://income/target',720,array['remaining_time','remaining_value'],'قبل نهاية الفترة'),
('target.missed','التارجت','انتهت فترة التارجت','Target period ended','حققت {current_value} من {target_value} خلال الفترة.','The target period has ended.','yamo://income/target',0,array['current_value','target_value'],'عدم تحقيق التارجت'),
('agency.new_host_bonus','الوكالة','مكافأة مضيف جديد','New host bonus','استحققت {reward} بونص عن المضيف {user_name}.','You earned a new-host bonus.','yamo://agency/income',0,array['reward','user_name'],'بونص أول أسبوعين'),
('income.weekly_ready','الدخل','تم اعتماد دخل الأسبوع','Weekly income ready','دخل هذا الأسبوع {amount} لؤلؤة. يمكنك مراجعة التفاصيل الآن.','Your weekly income is ready.','yamo://income',0,array['amount'],'اعتماد الأرباح'),
('withdrawal.opened','السحب','السحب متاح الآن','Withdrawal is open','يمكنك تقديم طلب سحب خلال الفترة المحددة.','Withdrawal is now available.','yamo://withdrawal',1440,'{}','فتح السحب'),
('withdrawal.approved','السحب','تم قبول طلب السحب','Withdrawal approved','تم قبول طلبك بقيمة {amount}.','Your withdrawal was approved.','yamo://withdrawal',0,array['amount'],'قبول السحب'),
('withdrawal.rejected','السحب','تم رفض طلب السحب','Withdrawal rejected','سبب الرفض: {reason}.','Your withdrawal was rejected.','yamo://withdrawal',0,array['reason'],'رفض السحب'),
('withdrawal.completed','السحب','تم تنفيذ السحب','Withdrawal completed','تم تنفيذ سحب {amount} بنجاح.','Your withdrawal was completed.','yamo://withdrawal',0,array['amount'],'اكتمال السحب'),
('gift.received','الهدايا','وصلتك هدية','Gift received','أرسل لك {sender_name} هدية {gift_name}.','You received a gift.','yamo://profile/gifts',0,array['sender_name','gift_name'],'استلام هدية'),
('vip.activated','VIP','تم تفعيل VIP {vip_level}','VIP activated','استمتع بمميزاتك حتى {expires_at}.','Enjoy your VIP benefits.','yamo://vip',0,array['vip_level','expires_at'],'شراء أو تفعيل VIP'),
('vip.expiring_3d','VIP','VIP ينتهي خلال 3 أيام','VIP expiring','جدد اشتراكك للحفاظ على المميزات.','Renew to keep your benefits.','yamo://vip',1440,'{}','قبل الانتهاء بثلاثة أيام'),
('vip.expiring_1d','VIP','VIP ينتهي غدًا','VIP expires tomorrow','باقي يوم واحد على انتهاء اشتراكك.','One day remains.','yamo://vip',1440,'{}','قبل الانتهاء بيوم'),
('vip.expired','VIP','انتهى اشتراك VIP','VIP expired','يمكنك التجديد واستعادة المميزات في أي وقت.','Renew anytime to restore benefits.','yamo://vip',0,'{}','انتهاء VIP'),
('level.upgraded','المستوى','وصلت إلى LVL {level}','Level upgraded','مبروك يا {user_name} على المستوى الجديد.','Congratulations on your new level.','yamo://profile',0,array['level','user_name'],'ترقية المستوى'),
('task.completed','المهام','تم إنجاز المهمة','Task completed','أنجزت {task_name} وربحت {reward}.','Task completed and reward earned.','yamo://tasks',0,array['task_name','reward'],'تحقيق مهمة'),
('reward.credited','المكافآت','تمت إضافة المكافأة','Reward credited','تمت إضافة {amount} {asset} إلى رصيدك.','Reward added to your balance.','yamo://wallet',0,array['amount','asset'],'نزول كوينز أو لؤلؤ'),
('relationship.requested','العلاقات','لديك دعوة جديدة','New relationship request','أرسل لك {user_name} دعوة {relationship_type}.','You received a relationship request.','yamo://relationships',0,array['user_name','relationship_type'],'دعوة CP أو أخوة'),
('relationship.accepted','العلاقات','تم قبول العلاقة','Relationship accepted','تم قبول علاقة {relationship_type} بنجاح.','Relationship accepted.','yamo://relationships',0,array['relationship_type'],'قبول العلاقة'),
('relationship.rejected','العلاقات','تم رفض الدعوة','Relationship declined','لم يتم قبول دعوة {relationship_type}.','Relationship request declined.','yamo://relationships',0,array['relationship_type'],'رفض العلاقة'),
('event.published','الفعاليات','فعالية جديدة: {event_name}','New event','اضغط لمعرفة المواعيد والجوائز.','Tap to view dates and rewards.','yamo://events/{event_id}',60,array['event_name','event_id'],'نشر فعالية'),
('event.starting','الفعاليات','الفعالية تبدأ قريبًا','Event starting soon','فعالية {event_name} تبدأ بعد {remaining_time}.','The event starts soon.','yamo://events/{event_id}',60,array['event_name','remaining_time','event_id'],'قرب بداية الحدث'),
('event.result','الفعاليات','ظهرت نتيجة الفعالية','Event result','مركزك {rank} ومكافأتك {reward}.','Event results are ready.','yamo://events/{event_id}',0,array['rank','reward','event_id'],'نتيجة الحدث'),
('moderation.warning','الإدارة','تنبيه إداري','Admin warning','{reason}','{reason}','yamo://support',0,array['reason'],'إنذار إداري'),
('moderation.banned','الإدارة','تم تقييد الحساب','Account restricted','السبب: {reason}. المدة: {duration}.','Your account was restricted.','yamo://support',0,array['reason','duration'],'حظر المستخدم'),
('room.announcement','الغرف','إعلان غرفة {room_name}','Room announcement','{message}','{message}','yamo://rooms/{room_id}',30,array['room_name','message','room_id'],'حدث أو مسابقة بالغرفة'),
('wallet.low_balance','الرصيد','رصيدك غير كافٍ','Low balance','تحتاج {required_coins} كوينز لإكمال العملية.','You need more coins.','yamo://recharge',720,array['required_coins'],'انخفاض الرصيد')
on conflict(event_key) do nothing;

create or replace function public.yamo_render_system_text(p_text text,p_payload jsonb)
returns text language plpgsql immutable as $$declare k text;v text;r text:=coalesce(p_text,'');begin for k,v in select key,value from jsonb_each_text(coalesce(p_payload,'{}')) loop r:=replace(r,'{'||k||'}',v);end loop;return r;end$$;

create or replace function public.emit_yamo_system_event(p_event_key text,p_user_id uuid,p_payload jsonb default '{}'::jsonb,p_event_id text default null)
returns uuid language plpgsql security definer set search_path=public,auth,pg_temp as $$
declare t public.yamo_system_message_templates%rowtype; d_id uuid; n_id text; title_text text; body_text text; link_text text; identity text;
begin
 select * into t from public.yamo_system_message_templates where event_key=p_event_key and enabled;
 if t.event_key is null or p_user_id is null then return null; end if;
 identity:=coalesce(nullif(p_event_id,''),md5(p_event_key||':'||p_user_id::text||':'||coalesce(p_payload::text,'{}')));
 if t.cooldown_minutes>0 and exists(select 1 from public.yamo_system_message_deliveries where event_key=p_event_key and user_id=p_user_id and queued_at>now()-make_interval(mins=>t.cooldown_minutes)) then return null; end if;
 title_text:=public.yamo_render_system_text(t.title_ar,p_payload);body_text:=public.yamo_render_system_text(t.body_ar,p_payload);link_text:=public.yamo_render_system_text(t.deep_link,p_payload);
 insert into public.yamo_system_message_deliveries(event_key,user_id,event_id,payload,rendered_title,rendered_body,image_url,deep_link,channels,status,attempt_count)
 values(p_event_key,p_user_id,identity,coalesce(p_payload,'{}'),title_text,body_text,t.image_url,link_text,t.channels,'queued',0)
 on conflict(event_key,user_id,event_id) do nothing returning id into d_id;
 if d_id is null then return null; end if;
 begin
   insert into public.yamo_notifications(user_id,kind,title_ar,body_ar,deep_link) values(p_user_id,'system',title_text,body_text,link_text) returning id::text into n_id;
   update public.yamo_system_message_deliveries set status='sent',attempt_count=1,sent_at=now(),notification_id=n_id where id=d_id;
 exception when others then update public.yamo_system_message_deliveries set status='failed',attempt_count=1,last_error=sqlerrm where id=d_id;
 end;
 return d_id;
end$$;
revoke all on function public.emit_yamo_system_event(text,uuid,jsonb,text) from public,anon,authenticated;
grant execute on function public.emit_yamo_system_event(text,uuid,jsonb,text) to service_role;

create or replace function public.emit_yamo_system_broadcast(p_event_key text,p_payload jsonb default '{}'::jsonb,p_event_id text default null,p_segment text default 'all')
returns integer language plpgsql security definer set search_path=public,auth,pg_temp as $$declare u record;n integer:=0;begin
 for u in select p.id from public.profiles p where case p_segment when 'all' then true when 'male' then lower(coalesce(p.gender,'')) in('male','ذكر') when 'female' then lower(coalesce(p.gender,'')) in('female','أنثى','انثى') when 'vip' then exists(select 1 from public.yamo_vip_subscriptions v where v.user_id=p.id and v.expires_at>now()) when 'hosts' then exists(select 1 from public.yamo_agency_hosts h where h.user_id=p.id and h.removed_at is null) else false end loop
   if public.emit_yamo_system_event(p_event_key,u.id,p_payload,coalesce(p_event_id,p_event_key)||':'||u.id::text) is not null then n:=n+1;end if;
 end loop;return n;end$$;
revoke all on function public.emit_yamo_system_broadcast(text,jsonb,text,text) from public,anon,authenticated;
grant execute on function public.emit_yamo_system_broadcast(text,jsonb,text,text) to service_role;

create or replace function public.admin_upsert_system_message_template(p_event_key text,p_payload jsonb)
returns text language plpgsql security definer set search_path=public,auth,pg_temp as $$begin
 perform public.yamo_admin_require('system_messages.manage');
 update public.yamo_system_message_templates set title_ar=coalesce(p_payload->>'title_ar',title_ar),title_en=case when p_payload?'title_en' then p_payload->>'title_en' else title_en end,body_ar=coalesce(p_payload->>'body_ar',body_ar),body_en=case when p_payload?'body_en' then p_payload->>'body_en' else body_en end,image_url=case when p_payload?'image_url' then nullif(p_payload->>'image_url','') else image_url end,deep_link=case when p_payload?'deep_link' then p_payload->>'deep_link' else deep_link end,channels=case when p_payload?'channels' then array(select jsonb_array_elements_text(p_payload->'channels')) else channels end,enabled=coalesce((p_payload->>'enabled')::boolean,enabled),cooldown_minutes=coalesce((p_payload->>'cooldown_minutes')::integer,cooldown_minutes),max_retries=coalesce((p_payload->>'max_retries')::integer,max_retries),updated_by=auth.uid(),updated_at=now() where event_key=p_event_key;
 if not found then raise exception 'template_not_found';end if;
 perform public.yamo_admin_log('system_message.template_update','yamo_system_message_templates',p_event_key,null,p_payload,'تعديل رسالة نظام');return p_event_key;
end$$;
grant execute on function public.admin_upsert_system_message_template(text,jsonb) to authenticated;

create or replace function public.admin_test_system_message(p_event_key text,p_legacy_id text,p_payload jsonb default '{}'::jsonb)
returns uuid language plpgsql security definer set search_path=public,auth,pg_temp as $$declare u uuid;result uuid;begin
 perform public.yamo_admin_require('system_messages.test');select id into u from public.profiles where legacy_id=p_legacy_id;if u is null then raise exception 'user_not_found';end if;
 result:=public.emit_yamo_system_event(p_event_key,u,p_payload||jsonb_build_object('user_name',(select display_name from public.profiles where id=u)),'test:'||gen_random_uuid()::text);
 perform public.yamo_admin_log('system_message.test','profile',p_legacy_id,null,jsonb_build_object('event_key',p_event_key),'تجربة رسالة نظام');return result;end$$;
grant execute on function public.admin_test_system_message(text,text,jsonb) to authenticated;

create or replace function public.admin_retry_system_message(p_delivery_id uuid)
returns boolean language plpgsql security definer set search_path=public,auth,pg_temp as $$declare d public.yamo_system_message_deliveries%rowtype;n_id text;begin
 perform public.yamo_admin_require('system_messages.manage');select * into d from public.yamo_system_message_deliveries where id=p_delivery_id for update;
 if d.id is null then raise exception 'delivery_not_found';end if;
 insert into public.yamo_notifications(user_id,kind,title_ar,body_ar,deep_link) values(d.user_id,'system',d.rendered_title,d.rendered_body,d.deep_link) returning id::text into n_id;
 update public.yamo_system_message_deliveries set status='sent',attempt_count=attempt_count+1,last_error=null,sent_at=now(),notification_id=n_id where id=d.id;return true;
exception when others then update public.yamo_system_message_deliveries set status='failed',attempt_count=attempt_count+1,last_error=sqlerrm where id=p_delivery_id;return false;end$$;
grant execute on function public.admin_retry_system_message(uuid) to authenticated;

create or replace function public.track_yamo_system_message(p_delivery_id uuid,p_action text)
returns boolean language plpgsql security definer set search_path=public,auth,pg_temp as $$begin
 if p_action not in('delivered','read','clicked') then return false;end if;
 update public.yamo_system_message_deliveries set status=p_action,delivered_at=case when p_action='delivered' then coalesce(delivered_at,now()) else delivered_at end,read_at=case when p_action='read' then coalesce(read_at,now()) else read_at end,clicked_at=case when p_action='clicked' then coalesce(clicked_at,now()) else clicked_at end where id=p_delivery_id and user_id=auth.uid();return found;end$$;
grant execute on function public.track_yamo_system_message(uuid,text) to authenticated;

create or replace function public.track_yamo_system_notification(p_notification_id text,p_action text)
returns boolean language plpgsql security definer set search_path=public,auth,pg_temp as $$begin
 if p_action not in('delivered','read','clicked') then return false;end if;
 update public.yamo_system_message_deliveries set status=p_action,delivered_at=case when p_action='delivered' then coalesce(delivered_at,now()) else delivered_at end,read_at=case when p_action in('read','clicked') then coalesce(read_at,now()) else read_at end,clicked_at=case when p_action='clicked' then coalesce(clicked_at,now()) else clicked_at end where notification_id=p_notification_id and user_id=auth.uid();return found;end$$;
grant execute on function public.track_yamo_system_notification(text,text) to authenticated;

create or replace function public.retry_failed_yamo_system_messages(p_limit integer default 100)
returns integer language plpgsql security definer set search_path=public,auth,pg_temp as $$declare d record;n integer:=0;n_id text;begin
 for d in select x.* from public.yamo_system_message_deliveries x join public.yamo_system_message_templates t using(event_key) where x.status='failed' and x.attempt_count<t.max_retries order by x.queued_at limit least(greatest(p_limit,1),500) loop
   begin insert into public.yamo_notifications(user_id,kind,title_ar,body_ar,deep_link) values(d.user_id,'system',d.rendered_title,d.rendered_body,d.deep_link) returning id::text into n_id;update public.yamo_system_message_deliveries set status='sent',attempt_count=attempt_count+1,last_error=null,sent_at=now(),notification_id=n_id where id=d.id;n:=n+1;exception when others then update public.yamo_system_message_deliveries set attempt_count=attempt_count+1,last_error=sqlerrm where id=d.id;end;
 end loop;return n;end$$;
revoke all on function public.retry_failed_yamo_system_messages(integer) from public,anon,authenticated;
grant execute on function public.retry_failed_yamo_system_messages(integer) to service_role;

drop view if exists public.admin_system_message_templates;
create view public.admin_system_message_templates as select t.*,
 (select count(*) from public.yamo_system_message_deliveries d where d.event_key=t.event_key) sent_total,
 (select count(*) from public.yamo_system_message_deliveries d where d.event_key=t.event_key and d.status in('read','clicked')) read_total,
 (select count(*) from public.yamo_system_message_deliveries d where d.event_key=t.event_key and d.status='failed') failed_total
 from public.yamo_system_message_templates t where public.yamo_admin_has_permission('system_messages.read') or public.yamo_admin_has_permission('system_messages.manage');
drop view if exists public.admin_system_message_deliveries;
create view public.admin_system_message_deliveries as select d.*,p.legacy_id,p.display_name from public.yamo_system_message_deliveries d join public.profiles p on p.id=d.user_id where public.yamo_admin_has_permission('system_messages.read') or public.yamo_admin_has_permission('system_messages.manage');
grant select on public.admin_system_message_templates,public.admin_system_message_deliveries to authenticated;

-- Generic trigger adapter. Uses JSON so it remains compatible with schema variations.
create or replace function public.yamo_auto_message_trigger() returns trigger language plpgsql security definer set search_path=public,auth,pg_temp as $$
declare n jsonb:=to_jsonb(new);o jsonb:=case when tg_op='INSERT' then '{}'::jsonb else to_jsonb(old) end;u uuid;key text;data jsonb;eid text;
begin
 begin u:=coalesce(n->>'user_id',n->>'recipient_id',n->>'host_id',n->>'invitee_id')::uuid;exception when others then u:=null;end;
 data:=n||jsonb_build_object('user_name',coalesce(n->>'display_name',''),'agency_name',coalesce(n->>'agency_name',''),'amount',coalesce(n->>'amount',n->>'pearls',n->>'reward_value',''),'reason',coalesce(n->>'reason',n->>'admin_note',''),'vip_level',coalesce(n->>'level',''),'expires_at',coalesce(n->>'expires_at',''),'relationship_type',coalesce(n->>'relationship_type',n->>'type',''),'event_name',coalesce(n->>'title_ar',n->>'title',''),'event_id',coalesce(n->>'id',''));
 eid:=tg_table_name||':'||coalesce(n->>'id',n->>'user_id',gen_random_uuid()::text)||':'||coalesce(n->>'status',tg_op);
 if tg_table_name='profiles' and tg_op='INSERT' then key:='account.registered';u:=(n->>'id')::uuid;
 elsif tg_table_name='yamo_agency_invitations' then
   key:=case when tg_op='INSERT' then 'agency.join_requested' when n->>'status'='accepted' then 'agency.request_accepted' when n->>'status'='rejected' then 'agency.request_rejected' end;
   if tg_op='INSERT' then begin select a.owner_id,a.name into u,key from public.yamo_agencies a where a.id=(n->>'agency_id')::uuid;data:=data||jsonb_build_object('agency_name',key);key:='agency.join_requested';exception when others then null;end;end if;
 elsif tg_table_name='yamo_agency_hosts' and tg_op='INSERT' then key:='agency.host_linked';
 elsif tg_table_name='yamo_vip_subscriptions' and tg_op in('INSERT','UPDATE') then key:='vip.activated';
 elsif tg_table_name='yamo_withdraw_requests' and tg_op='UPDATE' and n->>'status' is distinct from o->>'status' then key:=case n->>'status' when 'approved' then 'withdrawal.approved' when 'rejected' then 'withdrawal.rejected' when 'completed' then 'withdrawal.completed' end;
 elsif tg_table_name='yamo_relationships' then key:=case when tg_op='INSERT' then 'relationship.requested' when n->>'status'='accepted' then 'relationship.accepted' when n->>'status' in('rejected','declined') then 'relationship.rejected' end;
 elsif tg_table_name='yamo_events' and n->>'status'='live' and o->>'status' is distinct from 'live' then perform public.emit_yamo_system_broadcast('event.published',data,eid,'all');return new;
 end if;
 if key is not null and u is not null then perform public.emit_yamo_system_event(key,u,data,eid);end if;return new;
end$$;

do $$declare tbl text;begin foreach tbl in array array['profiles','yamo_agency_invitations','yamo_agency_hosts','yamo_vip_subscriptions','yamo_withdraw_requests','yamo_relationships','yamo_events'] loop if to_regclass('public.'||tbl) is not null then execute format('drop trigger if exists yamo_auto_system_message on public.%I',tbl);execute format('create trigger yamo_auto_system_message after insert or update on public.%I for each row execute function public.yamo_auto_message_trigger()',tbl);end if;end loop;end$$;

create or replace function public.yamo_host_target_message_trigger() returns trigger language plpgsql security definer set search_path=public,auth,pg_temp as $$
declare n jsonb:=to_jsonb(new);o jsonb:=case when tg_op='INSERT' then '{}'::jsonb else to_jsonb(old) end;u uuid;target numeric;achieved numeric;old_achieved numeric;pct numeric;old_pct numeric;key text;eid text;begin
 begin execute 'select user_id from public.hosts where id=$1' into u using (n->>'host_id')::uuid;exception when others then return new;end;
 target:=greatest(coalesce((n->>'target_coins')::numeric,0),coalesce((n->>'target_hours')::numeric,0));achieved:=case when coalesce((n->>'target_coins')::numeric,0)>0 then coalesce((n->>'achieved_coins')::numeric,0) else coalesce((n->>'achieved_hours')::numeric,0) end;old_achieved:=case when coalesce((o->>'target_coins')::numeric,0)>0 then coalesce((o->>'achieved_coins')::numeric,0) else coalesce((o->>'achieved_hours')::numeric,0) end;
 if target<=0 then return new;end if;pct:=achieved*100/target;old_pct:=old_achieved*100/target;eid:='host_target:'||coalesce(n->>'id','')||':';
 if pct>=100 and old_pct<100 then key:='target.completed';elsif pct>=75 and old_pct<75 then key:='target.progress_75';elsif pct>=50 and old_pct<50 then key:='target.progress_50';elsif pct>=25 and old_pct<25 then key:='target.progress_25';elsif n->>'status' in('missed','failed','ended') and o->>'status' is distinct from n->>'status' then key:='target.missed';end if;
 if key is not null then perform public.emit_yamo_system_event(key,u,jsonb_build_object('current_value',achieved,'target_value',target,'remaining_value',greatest(target-achieved,0),'period_name',coalesce(n->>'period_month',''),'reward',coalesce(n->>'reward','مكافأة التارجت')),eid||key);end if;return new;end$$;
do $$begin if to_regclass('public.host_targets') is not null then execute 'drop trigger if exists yamo_host_target_system_message on public.host_targets';execute 'create trigger yamo_host_target_system_message after insert or update on public.host_targets for each row execute function public.yamo_host_target_message_trigger()';end if;end$$;

create or replace function public.process_yamo_scheduled_system_messages()
returns integer language plpgsql security definer set search_path=public,auth,pg_temp as $$declare r record;n integer:=0;key text;begin
 for r in select user_id,level,expires_at from public.yamo_vip_subscriptions where expires_at between now()-interval '1 day' and now()+interval '4 days' loop
   key:=case when r.expires_at<=now() then 'vip.expired' when r.expires_at<=now()+interval '1 day' then 'vip.expiring_1d' when r.expires_at<=now()+interval '3 days' then 'vip.expiring_3d' end;
   if key is not null and public.emit_yamo_system_event(key,r.user_id,jsonb_build_object('vip_level',r.level,'expires_at',r.expires_at),key||':'||r.user_id::text||':'||r.expires_at::date::text) is not null then n:=n+1;end if;
 end loop;
 if to_regclass('public.host_targets') is not null and to_regclass('public.hosts') is not null then
   for r in execute $q$select h.user_id,t.id,t.period_year,t.period_month,greatest(coalesce(t.target_coins,0),coalesce(t.target_hours,0)) target_value,case when coalesce(t.target_coins,0)>0 then coalesce(t.achieved_coins,0) else coalesce(t.achieved_hours,0) end current_value,(make_date(t.period_year,t.period_month,1)+interval '1 month') period_end from public.host_targets t join public.hosts h on h.id=t.host_id where t.status='active'$q$ loop
     if r.period_end<=now() then key:='target.missed';elsif r.period_end<=now()+interval '2 days' then key:='target.expiring';else key:=null;end if;
     if key is not null and public.emit_yamo_system_event(key,r.user_id,jsonb_build_object('current_value',r.current_value,'target_value',r.target_value,'remaining_value',greatest(r.target_value-r.current_value,0),'remaining_time',case when key='target.expiring' then '48 ساعة' else '0' end),key||':'||r.id::text||':'||r.period_end::date::text) is not null then n:=n+1;end if;
   end loop;
 end if;
 n:=n+public.retry_failed_yamo_system_messages(100);return n;
end$$;
revoke all on function public.process_yamo_scheduled_system_messages() from public,anon,authenticated;
grant execute on function public.process_yamo_scheduled_system_messages() to service_role;

-- Supabase Cron is used when available; otherwise schedule the function hourly from Dashboard > Cron.
do $$begin if exists(select 1 from pg_extension where extname='pg_cron') then begin perform cron.unschedule('yamo-system-messages-hourly');exception when others then null;end;perform cron.schedule('yamo-system-messages-hourly','17 * * * *','select public.process_yamo_scheduled_system_messages()');end if;end$$;

commit;
select pg_notify('pgrst','reload schema');
