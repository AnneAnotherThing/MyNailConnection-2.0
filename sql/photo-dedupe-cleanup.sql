-- MNC: remove the duplicate photos found 2026-10-11 (approved by Anne that day).
-- Found by SHA-256 of every stored image. Rule: keep the OLDEST copy, give
-- it the tags from every copy (the later copies carried the richer tags),
-- move hearts (user_inspo) from a removed copy to the kept one, and delete
-- the extra feed posts. Then one feed post per image per tech, enforced.
--
--   Julieth (d88597b9): Gallery 7 -> 4, feed posts 4 -> 2
--     keep 1789018052696-csc3x, remove 1789019146951-vr97w
--     keep 1789018052701-ehdud, remove 1789019146948-yr91h and 1789019717853-mg04x
--     keep post 6b0a4dbc, delete posts 609ac2b1 and eb92500c
--   Maria Alejandra osorio de macias (f131780a): Gallery 37 -> 36
--     keep 1775069441621-gcbiv, remove 1775069458892-gisl1 (never posted)
--   Anne's old email account (annewilson1021@gmail.com, no tech row): feed
--     keep de4e368f, delete fdd2b00d (same image)
--     keep c92e8c3b, delete 3dae49c2 (same image)
--
-- Run AFTER sql/photo-dedupe-hash.sql and sql/photo-hash-backfill.sql.
-- One DO block, so it runs whole or not at all in the Supabase editor (which
-- does not keep a temporary table between statements). It stops with an
-- error and changes nothing if a kept copy is missing. Re-running is safe:
-- removed copies are skipped.
-- The 6 image files (and their _thumb.jpg) stay in the tech-photos bucket
-- until deleted in Storage; SQL cannot delete storage files.

do $$
declare
  r       record;
  v_keep  jsonb;
  v_extra jsonb;
  v_tags  jsonb;
begin
  for r in select * from (values
    ('d88597b9-1d68-447f-9ec9-82fbcfbe43f8'::uuid,
     'https://nwqnakoongrorbwnrqzc.supabase.co/storage/v1/object/public/tech-photos/gallery/julieth-lopez-yela/1789018052696-csc3x.jpeg',
     'https://nwqnakoongrorbwnrqzc.supabase.co/storage/v1/object/public/tech-photos/gallery/julieth-lopez-yela/1789019146951-vr97w.jpeg'),
    ('d88597b9-1d68-447f-9ec9-82fbcfbe43f8'::uuid,
     'https://nwqnakoongrorbwnrqzc.supabase.co/storage/v1/object/public/tech-photos/gallery/julieth-lopez-yela/1789018052701-ehdud.jpeg',
     'https://nwqnakoongrorbwnrqzc.supabase.co/storage/v1/object/public/tech-photos/gallery/julieth-lopez-yela/1789019146948-yr91h.jpeg'),
    ('d88597b9-1d68-447f-9ec9-82fbcfbe43f8'::uuid,
     'https://nwqnakoongrorbwnrqzc.supabase.co/storage/v1/object/public/tech-photos/gallery/julieth-lopez-yela/1789018052701-ehdud.jpeg',
     'https://nwqnakoongrorbwnrqzc.supabase.co/storage/v1/object/public/tech-photos/gallery/julieth-lopez-yela/1789019717853-mg04x.jpeg'),
    ('f131780a-ba84-4c49-8f3c-4d604bc6dc45'::uuid,
     'https://nwqnakoongrorbwnrqzc.supabase.co/storage/v1/object/public/tech-photos/gallery/maria-alejandra-osorio-de-macias/1775069441621-gcbiv.jpg',
     'https://nwqnakoongrorbwnrqzc.supabase.co/storage/v1/object/public/tech-photos/gallery/maria-alejandra-osorio-de-macias/1775069458892-gisl1.jpg'),
    (null::uuid,
     'https://nwqnakoongrorbwnrqzc.supabase.co/storage/v1/object/public/tech-photos/gallery/anne-wilson/1785791541195-pqzww.jpg',
     'https://nwqnakoongrorbwnrqzc.supabase.co/storage/v1/object/public/tech-photos/gallery/anne-wilson/1785812065528-ohv5m.jpg'),
    (null::uuid,
     'https://nwqnakoongrorbwnrqzc.supabase.co/storage/v1/object/public/tech-photos/gallery/anne-wilson/1785799772849-8yddj.jpg',
     'https://nwqnakoongrorbwnrqzc.supabase.co/storage/v1/object/public/tech-photos/gallery/anne-wilson/1785891150577-jy0cf.jpg')
  ) v(tech_id, keep_url, extra_url) loop

    -- Gallery (Anne's old account has no tech row: hearts only).
    if r.tech_id is not null then
      v_keep := null; v_extra := null;
      select p into v_keep
        from public.techs t, jsonb_array_elements(coalesce(t.photos, '[]'::jsonb)) p
       where t.id = r.tech_id and p ->> 'url' = r.keep_url;
      if v_keep is null then
        raise exception 'kept photo missing, nothing changed: %', r.keep_url;
      end if;
      select p into v_extra
        from public.techs t, jsonb_array_elements(coalesce(t.photos, '[]'::jsonb)) p
       where t.id = r.tech_id and p ->> 'url' = r.extra_url;
      if v_extra is null then
        raise notice 'already removed: %', r.extra_url;
      else
        -- Tags: the kept copy's first, then any new ones from the extra, in order.
        select coalesce(jsonb_agg(to_jsonb(x.t) order by x.first_o), '[]'::jsonb) into v_tags
          from (select a.t, min(a.o) as first_o
                  from (select k.t, k.o from jsonb_array_elements_text(coalesce(v_keep -> 'tags', '[]'::jsonb)) with ordinality k(t, o)
                        union all
                        select e.t, e.o + 1000 from jsonb_array_elements_text(coalesce(v_extra -> 'tags', '[]'::jsonb)) with ordinality e(t, o)) a
                 group by a.t) x;

        update public.techs t
           set photos = (
             select coalesce(jsonb_agg(
                      case when e.p ->> 'url' = r.keep_url then e.p || jsonb_build_object('tags', v_tags) else e.p end
                      order by e.o), '[]'::jsonb)
               from jsonb_array_elements(t.photos) with ordinality e(p, o)
              where e.p ->> 'url' <> r.extra_url)
         where t.id = r.tech_id;
      end if;
    end if;

    -- Hearts: a heart on a removed copy moves to the kept copy, unless that
    -- person already hearted the kept copy (then the extra heart goes).
    delete from public.user_inspo x
     where x.photo_url = r.extra_url
       and exists (select 1 from public.user_inspo k
                    where k.photo_url = r.keep_url
                      and ((k.user_id is not null and k.user_id = x.user_id)
                           or (k.user_email is not null and lower(k.user_email) = lower(x.user_email))));
    update public.user_inspo set photo_url = r.keep_url where photo_url = r.extra_url;
  end loop;

  -- The extra feed posts.
  delete from public.board_posts
   where id in ('609ac2b1-9f93-4c32-b6fd-551147e68c0f',
                'eb92500c-4846-44f6-8d1b-045a6458c0ba',
                'fdd2b00d-5559-4fca-9452-9eca30156f43',
                '3dae49c2-06bb-475f-89bc-9a5015fdf660');

  -- One feed post per image per tech from here on. The Release Wizard treats
  -- the 409 this raises as "already posted".
  create unique index if not exists board_posts_one_image_per_tech
    on public.board_posts (image_hash, coalesce(tech_uuid::text, lower(tech_id)))
    where image_hash is not null;
end $$;

-- Check: Julieth 4 photos and 2 posts, Maria Alejandra 36 photos, and no
-- photo or post anywhere still pointing at a removed copy (last column 0).
select
  (select jsonb_array_length(photos) from public.techs where id = 'd88597b9-1d68-447f-9ec9-82fbcfbe43f8') as julieth_photos,
  (select count(*) from public.board_posts where tech_uuid = 'd88597b9-1d68-447f-9ec9-82fbcfbe43f8') as julieth_posts,
  (select jsonb_array_length(photos) from public.techs where id = 'f131780a-ba84-4c49-8f3c-4d604bc6dc45') as maria_photos,
  (select count(*) from public.board_posts where tech_id = 'annewilson1021@gmail.com') as old_account_posts,
  (select count(*) from public.techs t, jsonb_array_elements(coalesce(t.photos, '[]'::jsonb)) p
    where p ->> 'url' in ('https://nwqnakoongrorbwnrqzc.supabase.co/storage/v1/object/public/tech-photos/gallery/julieth-lopez-yela/1789019146951-vr97w.jpeg',
                          'https://nwqnakoongrorbwnrqzc.supabase.co/storage/v1/object/public/tech-photos/gallery/julieth-lopez-yela/1789019146948-yr91h.jpeg',
                          'https://nwqnakoongrorbwnrqzc.supabase.co/storage/v1/object/public/tech-photos/gallery/julieth-lopez-yela/1789019717853-mg04x.jpeg',
                          'https://nwqnakoongrorbwnrqzc.supabase.co/storage/v1/object/public/tech-photos/gallery/maria-alejandra-osorio-de-macias/1775069458892-gisl1.jpg'))
  + (select count(*) from public.board_posts where image_url in (select extra_url from (values
        ('https://nwqnakoongrorbwnrqzc.supabase.co/storage/v1/object/public/tech-photos/gallery/julieth-lopez-yela/1789019146948-yr91h.jpeg'),
        ('https://nwqnakoongrorbwnrqzc.supabase.co/storage/v1/object/public/tech-photos/gallery/julieth-lopez-yela/1789019717853-mg04x.jpeg'),
        ('https://nwqnakoongrorbwnrqzc.supabase.co/storage/v1/object/public/tech-photos/gallery/anne-wilson/1785812065528-ohv5m.jpg'),
        ('https://nwqnakoongrorbwnrqzc.supabase.co/storage/v1/object/public/tech-photos/gallery/anne-wilson/1785891150577-jy0cf.jpg')) v(extra_url)))
  as still_pointing_at_removed;
