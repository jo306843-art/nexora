/* NEXORA catalog management and daily wallet rewards */
(()=>{
 const cfg=window.NEXORA_CONFIG||{}, sb=window.supabase&&cfg.supabaseUrl&&cfg.supabaseAnonKey?window.supabase.createClient(cfg.supabaseUrl,cfg.supabaseAnonKey):null;
 const OWNER="jo306843@gmail.com", $=id=>document.getElementById(String(id).replace(/^#/, "")), esc=s=>String(s??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c])), money=n=>Number(n||0).toLocaleString("ar-EG",{maximumFractionDigits:2}), say=m=>window.toast?window.toast(m):alert(m);
 let owner=false,products=[],editing=null;
 async function check(){if(!sb)return null;const {data}=await sb.auth.getSession();owner=(data.session?.user?.email||"").toLowerCase()===OWNER;return data.session;}
 function addAdmin(){
  if(!owner||!$("#admin")||$("#nxCatalogAdmin"))return;
  const p=document.createElement("div");p.id="nxCatalogAdmin";p.className="panel";
  p.innerHTML='<h3>إدارة المنتجات المنشورة</h3><input class="field" id="nxName" placeholder="اسم المنتج"><input class="field" id="nxCat" placeholder="التصنيف"><input class="field" id="nxPrice" type="number" min="0.01" step="0.01" placeholder="السعر"><input class="field" id="nxOld" type="number" min="0" step="0.01" placeholder="السعر قبل الخصم (اختياري)"><input class="field" id="nxImage" placeholder="رابط صورة المنتج"><input class="field" id="nxStock" type="number" min="0" step="1" value="0" placeholder="الكمية المتاحة بالمخزون"><button class="primary" id="nxSave">نشر المنتج</button><button class="primary" id="nxCancel" style="display:none;background:#777">إلغاء التعديل</button><div id="nxProductsList">تحميل المنتجات...</div><hr><h3>مكافأة الدخول اليومية</h3><p class="muted">مكافأة اليوم الأول 20 جنيه، وتزيد 5 جنيه مع كل يوم متواصل. يمكنك تغيير مبلغ البداية أو إيقاف المكافأة بوضع صفر.</p><input class="field" id="nxRewardAmount" type="number" min="0" max="1000" step="0.5" value="20"><button class="primary" id="nxRewardSave">حفظ المكافأة</button>';
  $("#admin").appendChild(p);$("#nxSave").onclick=saveProduct;$("#nxCancel").onclick=clearForm;$("#nxRewardSave").onclick=saveReward;
 }
 function clearForm(){editing=null;["nxName","nxCat","nxPrice","nxOld","nxImage","nxStock"].forEach(id=>$(id).value="");$("#nxSave").textContent="نشر المنتج";$("#nxCancel").style.display="none";}

 async function seedStarterCatalog(){
  if(!owner)return;
  const brands=["ALEXANDER MCQUEEN","A.LANGE & SÖHNE","BOTTEGA VENETA","BURBERRY","BVLGARI","BREGUET","CHLOÉ","COACH","DIOR","CARTIER"];
  const images=[
   "https://images.unsplash.com/photo-1617038220319-276d3cfab638?auto=format&fit=crop&w=900&q=85",
   "https://images.unsplash.com/photo-1611652022419-a9419f74343d?auto=format&fit=crop&w=900&q=85",
   "https://images.unsplash.com/photo-1611591437281-460bfbe1220a?auto=format&fit=crop&w=900&q=85",
   "https://images.unsplash.com/photo-1605100804763-247f67b3557e?auto=format&fit=crop&w=900&q=85",
   "https://images.unsplash.com/photo-1599643478518-a784e5dc4c8f?auto=format&fit=crop&w=900&q=85",
   "https://images.unsplash.com/photo-1523275335684-37898b6baf30?auto=format&fit=crop&w=900&q=85",
   "https://images.unsplash.com/photo-1524592094714-0f0654e20314?auto=format&fit=crop&w=900&q=85",
   "https://images.unsplash.com/photo-1508685096489-7aacd43bd3b1?auto=format&fit=crop&w=900&q=85",
   "https://images.unsplash.com/photo-1524805444758-089113d48a6d?auto=format&fit=crop&w=900&q=85",
   "https://images.unsplash.com/photo-1547996160-81dfa63595aa?auto=format&fit=crop&w=900&q=85"
  ];
  const jewelry=["طقم عقد وأقراط ذهبي","سوار أنيق مطلي بالذهب","خاتم نسائي بتصميم ناعم","أقراط لؤلؤية يومية","قلادة بحجر لامع"];
  const watches=["ساعة رجالي كلاسيك","ساعة رجالي ستانلس ستيل","ساعة رجالي بسوار جلدي","ساعة رجالي رياضية أنيقة","ساعة رجالي بميناء فاخر"];
  const {data:existing,error}=await sb.from("products").select("name,brand").limit(1000);
  if(error){console.warn("NEXORA catalog seed:",error.message);return;}
  const have=new Set((existing||[]).map(p=>p.name));
  const counts=new Map(brands.map(b=>[b,(existing||[]).filter(p=>(p.brand||"").toUpperCase()===b).length]));
  const rows=[];
  brands.forEach((brand,bi)=>{
   const watchBrand=brand==="A.LANGE & SÖHNE"||brand==="BREGUET"||brand==="CARTIER";
   for(let j=0;j<5;j++){
    const name=(watchBrand?watches[j]:jewelry[j])+" — "+brand+" "+(j+1);
    if(have.has(name))continue;
    const price=(watchBrand?[1450,1890,2150,1690,2490]:[280,390,520,340,650])[j]+bi*35;
    rows.push({name,description:"قطعة مختارة بتصميم أنيق — صور توضيحية للمنتج",category:watchBrand?"ساعات رجالي":"إكسسوارات حريمي",brand,price:Math.round(price),old_price:Math.round(price*1.25),image_url:images[(bi+j)%images.length],stock:12+j,active:true});
   }
  });
  if(rows.length){const {error:insertError}=await sb.from("products").insert(rows);if(insertError){console.warn("NEXORA catalog seed:",insertError.message);return;}}
 }

 async function loadProducts(){
  const {data:rows,error}=await sb.from("products").select("id,name,description,category,brand,price,old_price,image_url,stock,active").order("created_at",{ascending:false});
  if(error){if($("#nxProductsList"))$("#nxProductsList").textContent="خطأ تحميل المنتجات: "+error.message;return;}
  products=rows||[];
  const visible=products.filter(p=>p.active||owner);data.splice(0,data.length,...visible.map(p=>[p.name,p.category,Number(p.price),Number(p.old_price)||Number(p.price),p.image_url||"https://placehold.co/600x600?text=NEXORA",p.id,p.brand||""]));if(typeof renderProducts==="function")renderProducts();
  drawProducts();
 }
 function drawProducts(){const el=$("#nxProductsList");if(!el)return;el.innerHTML=products.map(p=>'<div style="padding:10px 0;border-bottom:1px solid #ddd"><b>'+esc(p.name)+'</b> · '+money(p.price)+' ج.م · المخزون: '+Number(p.stock||0)+' · '+(p.active?"منشور":"مخفي")+'<div style="display:flex;gap:6px;margin-top:6px"><button class="primary" data-e="'+p.id+'">تعديل</button><button class="primary" data-t="'+p.id+'" style="background:#718A7D">'+(p.active?"إخفاء":"نشر")+'</button><button class="primary" data-d="'+p.id+'" style="background:#a33">حذف</button></div></div>').join("")||"لا توجد منتجات في قاعدة البيانات.";
  el.querySelectorAll("[data-e]").forEach(b=>b.onclick=()=>{const p=products.find(x=>x.id===b.dataset.e);editing=p.id;$("#nxName").value=p.name;$("#nxCat").value=p.category;$("#nxPrice").value=p.price;$("#nxOld").value=p.old_price;$("#nxImage").value=p.image_url;$("#nxStock").value=p.stock??0;$("#nxSave").textContent="حفظ التعديل";$("#nxCancel").style.display="block";});
  el.querySelectorAll("[data-t]").forEach(b=>b.onclick=async()=>{const p=products.find(x=>x.id===b.dataset.t);const {error}=await sb.from("products").update({active:!p.active,updated_at:new Date().toISOString()}).eq("id",p.id);if(error)say(error.message);else await loadProducts();});
  el.querySelectorAll("[data-d]").forEach(b=>b.onclick=async()=>{if(!confirm("إخفاء المنتج من المتجر؟ سيظل محفوظًا في سجل الطلبات."))return;const {error}=await sb.from("products").update({active:false,updated_at:new Date().toISOString()}).eq("id",b.dataset.d);if(error)say(error.message);else{say("تم إخفاء المنتج مع الحفاظ على سجل الطلبات");await loadProducts();}});
 }
 async function saveProduct(){if(!owner)return;const name=$("#nxName").value.trim(),category=$("#nxCat").value.trim()||"عام",price=Number($("#nxPrice").value),old_price=Number($("#nxOld").value)||price,image_url=$("#nxImage").value.trim(),stock=Math.max(0,Math.floor(Number($("#nxStock").value)||0));if(!name||!Number.isFinite(price)||price<=0){say("اكتب اسم المنتج وسعرًا صحيحًا");return;}const row={name,description:name,category,price,old_price,image_url,stock,updated_at:new Date().toISOString()};const q=editing?sb.from("products").update(row).eq("id",editing):sb.from("products").insert({...row,active:true});const {error}=await q;if(error){say("تعذر حفظ المنتج: "+error.message);return;}say("تم حفظ المنتج ونشره للعملاء");clearForm();await loadProducts();}
 async function loadReward(){
  const session=await check();
  const days=$("#days");
  const claimButton=document.querySelector('#attendance button[onclick="nxClaimDailyReward()"]');
  if(!session){
   if(days)days.innerHTML='<div style="padding:12px;text-align:center">سجّل الدخول أولًا لعرض مكافأتك اليومية.</div>';
   if(claimButton){claimButton.disabled=false;claimButton.textContent="استلام مكافأة اليوم";}
   return;
  }
  const parts=new Intl.DateTimeFormat("en-CA",{timeZone:"Africa/Cairo",year:"numeric",month:"2-digit",day:"2-digit"}).formatToParts(new Date());
  const part=k=>parts.find(x=>x.type===k)?.value;
  const today=part("year")+"-"+part("month")+"-"+part("day");
  const yesterdayDate=new Date(Date.UTC(Number(part("year")),Number(part("month"))-1,Number(part("day"))-1));
  const yesterday=yesterdayDate.toISOString().slice(0,10);
  const [todayResult,prevResult]=await Promise.all([
   sb.from("daily_reward_claims").select("id").eq("user_id",session.user.id).eq("claim_date",today).maybeSingle(),
   sb.from("daily_reward_claims").select("amount").eq("user_id",session.user.id).eq("claim_date",yesterday).maybeSingle()
  ]);
  if(todayResult.error||prevResult.error){
   const msg=todayResult.error?.message||prevResult.error?.message;
   if(days)days.innerHTML='<div style="padding:12px;text-align:center;color:#a33">تعذر تحميل المكافأة: '+esc(msg)+'</div>';
   if(claimButton){claimButton.disabled=false;claimButton.textContent="إعادة المحاولة";}
   return;
  }
  const claimed=!!todayResult.data;
  const amount=prevResult.data?Number(prevResult.data.amount)+5:20;
  if(days)days.innerHTML='<div style="padding:12px;text-align:center"><b>مكافأة اليوم: '+money(amount)+' جنيه</b><div class="muted">'+(claimed?'تم استلام مكافأة اليوم بالفعل':'متاحة للاستلام مرة واحدة اليوم')+'</div></div>';
  if(claimButton){claimButton.disabled=claimed;claimButton.textContent=claimed?'تم استلام مكافأة اليوم':'استلام '+money(amount)+' جنيه';}
 }
 async function claimReward(){const session=await check();if(!session){say("سجّل الدخول أو أنشئ حسابًا أولًا لاستلام المكافأة");if(typeof showPage==="function")showPage("login");return;}const {data,error}=await sb.rpc("claim_daily_reward");if(error){say(error.message.includes("already_claimed_today")?"استلمت مكافأة اليوم بالفعل": "تعذر استلام المكافأة: "+error.message);return;}say("تم إضافة "+money(data?.[0]?.reward_amount)+" جنيه لرصيدك");await loadReward();window.dispatchEvent(new Event("nexora:wallet-refresh"));}
 window.nxClaimDailyReward=claimReward;
 async function saveReward(){if(!owner)return;const amount=Number($("#nxRewardAmount").value);if(!Number.isFinite(amount)||amount<0||amount>1000){say("المبلغ من صفر إلى 1000 جنيه");return;}const {error}=await sb.rpc("owner_set_daily_reward",{p_amount:amount});if(error)say("تعذر الحفظ: "+error.message);else{say("تم تحديث مكافأة الدخول اليومية");await loadReward();}}
 async function init(){if(!sb)return;await check();addAdmin();await seedStarterCatalog();await loadProducts();await loadReward();sb.auth.onAuthStateChange(()=>setTimeout(async()=>{await check();addAdmin();await loadProducts();await loadReward();},100));}
 if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",init);else init();
})();