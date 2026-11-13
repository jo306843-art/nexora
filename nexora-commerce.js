/* NEXORA catalog management and daily wallet rewards */
(()=>{
 const cfg=window.NEXORA_CONFIG||{}, sb=window.supabase&&cfg.supabaseUrl&&cfg.supabaseAnonKey?window.supabase.createClient(cfg.supabaseUrl,cfg.supabaseAnonKey):null;
 const OWNER="jo306843@gmail.com", $=id=>document.getElementById(String(id).replace(/^#/, "")), esc=s=>String(s??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c])), money=n=>Number(n||0).toLocaleString("ar-EG",{maximumFractionDigits:2}), say=m=>window.toast?window.toast(m):alert(m);
 let owner=false,products=[],editing=null;
 async function check(){if(!sb)return null;const {data}=await sb.auth.getSession();owner=(data.session?.user?.email||"").toLowerCase()===OWNER;return data.session;}
 function addAdmin(){
  if(!owner||!$("#admin")||$("#nxCatalogAdmin"))return;
  const p=document.createElement("div");p.id="nxCatalogAdmin";p.className="panel";
  p.innerHTML='<h3>إدارة المنتجات المنشورة</h3><input class="field" id="nxName" placeholder="اسم المنتج"><input class="field" id="nxCat" placeholder="التصنيف"><input class="field" id="nxPrice" type="number" min="0.01" step="0.01" placeholder="السعر"><input class="field" id="nxOld" type="number" min="0" step="0.01" placeholder="السعر قبل الخصم (اختياري)"><input class="field" id="nxImage" placeholder="رابط صورة المنتج"><button class="primary" id="nxSave">نشر المنتج</button><button class="primary" id="nxCancel" style="display:none;background:#777">إلغاء التعديل</button><div id="nxProductsList">تحميل المنتجات...</div><hr><h3>مكافأة الدخول اليومية</h3><p class="muted">مكافأة اليوم الأول 20 جنيه، وتزيد 5 جنيه مع كل يوم متواصل. يمكنك تغيير مبلغ البداية أو إيقاف المكافأة بوضع صفر.</p><input class="field" id="nxRewardAmount" type="number" min="0" max="1000" step="0.5" value="20"><button class="primary" id="nxRewardSave">حفظ المكافأة</button>';
  $("#admin").appendChild(p);$("#nxSave").onclick=saveProduct;$("#nxCancel").onclick=clearForm;$("#nxRewardSave").onclick=saveReward;
 }
 function clearForm(){editing=null;["nxName","nxCat","nxPrice","nxOld","nxImage"].forEach(id=>$(id).value="");$("#nxSave").textContent="نشر المنتج";$("#nxCancel").style.display="none";}
 async function loadProducts(){
  const {data:rows,error}=await sb.from("products").select("id,name,category,price,old_price,image_url,active").order("created_at",{ascending:false});
  if(error){if($("#nxProductsList"))$("#nxProductsList").textContent="خطأ تحميل المنتجات: "+error.message;return;}
  products=rows||[];
  if(products.length){const visible=products.filter(p=>p.active||owner);data.splice(0,data.length,...data.filter(p=>!p[5]),...visible.map(p=>[p.name,p.category,Number(p.price),Number(p.old_price)||Number(p.price),p.image_url||"https://placehold.co/600x600?text=NEXORA",p.id]));if(typeof renderProducts==="function")renderProducts();}
  drawProducts();
 }
 function drawProducts(){const el=$("#nxProductsList");if(!el)return;el.innerHTML=products.map(p=>'<div style="padding:10px 0;border-bottom:1px solid #ddd"><b>'+esc(p.name)+'</b> · '+money(p.price)+' ج.م · '+(p.active?"منشور":"مخفي")+'<div style="display:flex;gap:6px;margin-top:6px"><button class="primary" data-e="'+p.id+'">تعديل</button><button class="primary" data-t="'+p.id+'" style="background:#718A7D">'+(p.active?"إخفاء":"نشر")+'</button><button class="primary" data-d="'+p.id+'" style="background:#a33">حذف</button></div></div>').join("")||"لا توجد منتجات في قاعدة البيانات.";
  el.querySelectorAll("[data-e]").forEach(b=>b.onclick=()=>{const p=products.find(x=>x.id===b.dataset.e);editing=p.id;$("#nxName").value=p.name;$("#nxCat").value=p.category;$("#nxPrice").value=p.price;$("#nxOld").value=p.old_price;$("#nxImage").value=p.image_url;$("#nxSave").textContent="حفظ التعديل";$("#nxCancel").style.display="block";});
  el.querySelectorAll("[data-t]").forEach(b=>b.onclick=async()=>{const p=products.find(x=>x.id===b.dataset.t);const {error}=await sb.from("products").update({active:!p.active,updated_at:new Date().toISOString()}).eq("id",p.id);if(error)say(error.message);else await loadProducts();});
  el.querySelectorAll("[data-d]").forEach(b=>b.onclick=async()=>{if(!confirm("حذف المنتج نهائيًا؟"))return;const {error}=await sb.from("products").delete().eq("id",b.dataset.d);if(error)say(error.message);else{say("تم حذف المنتج");await loadProducts();}});
 }
 async function saveProduct(){if(!owner)return;const name=$("#nxName").value.trim(),category=$("#nxCat").value.trim()||"عام",price=Number($("#nxPrice").value),old_price=Number($("#nxOld").value)||price,image_url=$("#nxImage").value.trim();if(!name||!Number.isFinite(price)||price<=0){say("اكتب اسم المنتج وسعرًا صحيحًا");return;}const row={name,category,price,old_price,image_url,updated_at:new Date().toISOString()};const q=editing?sb.from("products").update(row).eq("id",editing):sb.from("products").insert({...row,active:true});const {error}=await q;if(error){say("تعذر حفظ المنتج: "+error.message);return;}say("تم حفظ المنتج ونشره للعملاء");clearForm();await loadProducts();}
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
 window.nxClaimDailyReward=claimReward;\n async function saveReward(){if(!owner)return;const amount=Number($("#nxRewardAmount").value);if(!Number.isFinite(amount)||amount<0||amount>1000){say("المبلغ من صفر إلى 1000 جنيه");return;}const {error}=await sb.rpc("owner_set_daily_reward",{p_amount:amount});if(error)say("تعذر الحفظ: "+error.message);else{say("تم تحديث مكافأة الدخول اليومية");await loadReward();}}
 async function init(){if(!sb)return;await check();addAdmin();await loadProducts();await loadReward();sb.auth.onAuthStateChange(()=>setTimeout(async()=>{await check();addAdmin();await loadProducts();await loadReward();},100));}
 if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",init);else init();
})();