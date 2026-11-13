-- Brand catalog collections for NEXORA. Products are curated style selections, not brand-authenticated goods.
-- Ensure the existing products table has the catalog fields expected by the storefront.
-- Existing descriptions, stock counts, product IDs, and product rows are left intact.
alter table public.products add column if not exists category text not null default 'عام';
alter table public.products add column if not exists old_price numeric(12,2) not null default 0;
alter table public.products add column if not exists name text;
update public.products
set name = coalesce(nullif(btrim(name), ''), nullif(btrim(description), ''), 'منتج #' || id::text)
where name is null or btrim(name) = '';
alter table public.products alter column name set not null;
alter table public.products add column if not exists category text not null default 'عام';
alter table public.products add column if not exists old_price numeric(12,2) not null default 0;
alter table public.products add column if not exists brand text not null default '';
alter table public.products add column if not exists updated_at timestamptz not null default now();
alter table public.products add column if not exists updated_at timestamptz not null default now();
alter table public.products alter column stock set default 0;
create index if not exists products_brand_active_idx on public.products(brand,active);
drop policy if exists "nexora_products_public_read" on public.products;
create policy "nexora_products_public_read" on public.products for select to anon, authenticated using (active or public.is_nexora_owner());

insert into public.products(name,category,brand,price,old_price,image_url,active)
select v.name,'إكسسوارات وأزياء',v.brand,v.price,v.old_price,v.image_url,true
from (values
('حقيبة سهرة أنيقة','ALEXANDER MCQUEEN',480,590,'https://images.unsplash.com/photo-1584917865442-de89df76afd3?w=700'),
('سلسلة معدنية عصرية','ALEXANDER MCQUEEN',220,290,'https://images.unsplash.com/photo-1611652022419-a9419f5f6e4c?w=700'),
('ساعة بتصميم كلاسيكي','A.LANGE & SÖHNE',500,650,'https://images.unsplash.com/photo-1523275335684-37898b6baf30?w=700'),
('سوار معدني بسيط','A.LANGE & SÖHNE',180,240,'https://images.unsplash.com/photo-1611591437281-460bfbe1220a?w=700'),
('محفظة صغيرة أنيقة','BOTTEGA VENETA',350,450,'https://images.unsplash.com/photo-1627123424574-724758594e93?w=700'),
('حلق دائري ناعم','BOTTEGA VENETA',160,210,'https://images.unsplash.com/photo-1611652022419-a9419f5f6e4c?w=700'),
('وشاح خفيف للإطلالة','BURBERRY',260,340,'https://images.unsplash.com/photo-1601924994987-69e26d50dc26?w=700'),
('نظارة شمس كلاسيكية','BURBERRY',390,490,'https://images.unsplash.com/photo-1511499767150-a48a237f0083?w=700'),
('سلسلة بحلية لامعة','BVLGARI',290,380,'https://images.unsplash.com/photo-1611652022419-a9419f5f6e4c?w=700'),
('سوار رقيق','BVLGARI',190,250,'https://images.unsplash.com/photo-1611591437281-460bfbe1220a?w=700'),
('ساعة يومية أنيقة','BREGUET',470,590,'https://images.unsplash.com/photo-1523275335684-37898b6baf30?w=700'),
('مشبك شعر بتفاصيل ناعمة','BREGUET',120,170,'https://images.unsplash.com/photo-1590548784585-643d2b9f2925?w=700'),
('حقيبة كتف صغيرة','CHLOÉ',450,560,'https://images.unsplash.com/photo-1584917865442-de89df76afd3?w=700'),
('طقم حلق وسلسلة','CHLOÉ',240,310,'https://images.unsplash.com/photo-1611652022419-a9419f5f6e4c?w=700'),
('محفظة كروت عملية','COACH',210,280,'https://images.unsplash.com/photo-1622560480654-d96214fdc887?w=700'),
('حافظة موبايل أنيقة','COACH',170,230,'https://images.unsplash.com/photo-1603313011108-4d2e6e6f4b9f?w=700'),
('إكسسوار شعر لؤلؤ','DIOR',150,200,'https://images.unsplash.com/photo-1590548784585-643d2b9f2925?w=700'),
('نظارة شمس بإطار ناعم','DIOR',420,500,'https://images.unsplash.com/photo-1511499767150-a48a237f0083?w=700'),
('سوار معدني أنيق','CARTIER',320,410,'https://images.unsplash.com/photo-1611591437281-460bfbe1220a?w=700'),
('حلق بتصميم كلاسيكي','CARTIER',230,300,'https://images.unsplash.com/photo-1611652022419-a9419f5f6e4c?w=700')
) as v(name,brand,price,old_price,image_url)
where not exists(select 1 from public.products p where p.name=v.name and p.brand=v.brand);
