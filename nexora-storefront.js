/* NEXORA favorites and wallet order flow */
(()=>{
 const cfg=window.NEXORA_CONFIG||{},db=window.supabase&&cfg.supabaseUrl&&cfg.supabaseAnonKey?window.supabase.createClient(cfg.supabaseUrl,cfg.supabaseAnonKey):null;
 const $=id=>document.getElementById(id),esc=s=>String(s??"").replace(/[&<>"]/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"}[c]));
 const money=n=>Number(n||0).toLocaleString("ar-EG",{maximumFractionDigits:2});
 const say=m=>window.toast?window.toast(m):alert(m),OWNER="jo306843@gmail.com";
 let user=null,isOwner=false,favorites=new Set();
 const status={pending_review:"بانتظار مراجعة التحويل",paid:"تم تأكيد الدفع",rejected:"تم رفض التحويل",placed:"تم استلام الطلب",processing:"قيد التجهيز",shipped:"تم الشحن",completed:"مكتمل",cancelled:"ملغي — تم رد المبلغ"};
 async function auth(){if(!db)return null;const {data}=await db.auth.getSession();user=data.session?.user||null;isOwner=(user?.email||"").toLowerCase()===OWNER;return user;}
 function ensurePanels(){
  if(!$("favorites")){const sec=document.createElement("section");sec.className="page";sec.id="favorites";sec.innerHTML='<div class="subhead"><button onclick="showPage(\'profile\')">‹</button>قائمة المفضلة ♡</div><div class="products" id="nxFavoriteGrid"></div><p class="muted" id="nxFavoriteEmpty" style="text-align:center;padding:20px">لا توجد منتجات في المفضلة بعد.</p>';$("profile").parentNode.insertBefore(sec,$("profile").nextSibling);}
  if(!$("nxOrdersPanel")){const p=document.createElement("div");p.id="nxOrdersPanel";p.className="panel";p.innerHTML='<h3>طلباتي ومتابعة الشراء</h3><div id="nxCustomerOrders">سجّل الدخول لعرض طلباتك.</div>';$("profile").appendChild(p);}
  if(!$("nxOwnerOrders")&&$("admin")){const p=document.createElement("div");p.id="nxOwnerOrders";p.className="panel";p.innerHTML='<h3>طلبات المتجر</h3><div id="nxOwnerOrdersList">تحميل الطلبات...</div>';$("admin").appendChild(p);}
  const menu=$("profile").querySelector(".menu-list");
  if(menu&&!$("nxFavoritesLink")){const b=document.createElement("button");b.id="nxFavoritesLink";b.className="menu-row";b.innerHTML='<span class="mi">♡</span>المفضلة <span class="arrow">‹</span>';b.onclick=()=>{showPage("favorites");loadFavorites();};menu.insertBefore(b,menu.firstChild);}
 }

 function setupBrandCollections(){
  const section=$("brands");if(!section)return;
  const grid=section.querySelector(".brands");if(!grid)return;
  grid.querySelectorAll(".brand").forEach(card=>{
   const name=card.querySelector("strong")?.textContent?.trim();if(!name)return;
   card.style.cursor="pointer";card.setAttribute("role","button");card.setAttribute("tabindex","0");
   card.onclick=()=>openBrand(name);
   card.onkeydown=e=>{if(e.key==="Enter"||e.key===" "){e.preventDefault();openBrand(name);}};
  });
  if(!$("nxBrandCollection")){
   const panel=document.createElement("section");panel.className="page";panel.id="nxBrandCollection";
   panel.innerHTML='<div class="subhead"><button id="nxBrandBack">‹</button><span id="nxBrandTitle">المنتجات</span></div><p class="muted" style="padding:0 14px">تشكيلة مختارة تناسب أسلوب العلامة. المنتجات المعروضة ليست بالضرورة أصلية أو معتمدة من العلامة التجارية.</p><div class="section"><div class="products" id="nxBrandProducts"></div><p class="muted" id="nxBrandEmpty" style="text-align:center;padding:20px;display:none">لا توجد منتجات لهذه العلامة حاليًا.</p></div>';
   section.parentNode.insertBefore(panel,section.nextSibling);
   $("nxBrandBack").onclick=()=>showPage("brands");
  }
 }
 async function openBrand(name){
  if(!db){say("تعذر الاتصال بالمتجر حاليًا.");return;}
  $("nxBrandTitle").textContent=name;
  showPage("nxBrandCollection");
  const {data,error}=await db.from("products").select("id,name,description,category,brand,price,old_price,image_url,stock,active").ilike("brand",name).eq("active",true).order("created_at",{ascending:false});
  if(error){$("nxBrandProducts").innerHTML="تعذر تحميل المنتجات: "+esc(error.message);$("nxBrandEmpty").style.display="none";return;}
  const rows=data||[];
  $("nxBrandProducts").innerHTML=rows.map(p=>productCard(p,'<button class="add" onclick="event.stopPropagation();nxBuyOne(\\''+String(p.id)+'\\')">اطلب الآن</button>')).join("");
  $("nxBrandEmpty").style.display=rows.length?"none":"block";
 }

 function productCard(p,extra=""){
  const id=String(p.id),liked=favorites.has(id);
  return '<article class="product nx-product-card" onclick="nxOpenProduct(\''+id+'\')"><img loading="lazy" src="'+esc(p.image_url||"https://placehold.co/600x600?text=NEXORA")+'" alt="'+esc(p.name)+'"><div class="name">'+esc(p.name)+'</div><b class="price">'+money(p.price)+' ج.م</b><button class="nx-fav" aria-label="المفضلة" onclick="event.stopPropagation();nxToggleFavorite(\''+id+'\',this)">'+(liked?'♥':'♡')+'</button>'+extra+'</article>';
 }
 function addFavButtons(){
  if(typeof window.product!=="function")return;
  const original=window.product;
  if(original.__nxWrapped)return;
  const wrapped=function(p,i){
   const html=original(p,i),id=p[5];if(id===undefined||id===null)return html;
   return html.replace('<article class="product">','<article class="product nx-product-card" onclick="nxOpenProduct(\''+String(id)+'\')">')
    .replace('onclick="add('+i+')"','onclick="event.stopPropagation();add('+i+')"')
    .replace('</article>','<button class="nx-fav" aria-label="المفضلة" onclick="event.stopPropagation();nxToggleFavorite(\''+String(id)+'\',this)">'+(favorites.has(String(id))?'♥':'♡')+'</button></article>');
  };
  wrapped.__nxWrapped=true;window.product=wrapped;
 }
 window.nxOpenProduct=async id=>{
  if(!db){say("تفاصيل المنتج غير متاحة حاليًا.");return;}
  const {data:p,error}=await db.from("products").select("id,name,description,category,brand,price,old_price,image_url,stock,active").eq("id",id).maybeSingle();
  if(error||!p){say("تعذر فتح المنتج: "+(error?.message||"المنتج غير متاح"));return;}
  const html='<div class="nx-product-detail"><img src="'+esc(p.image_url||"https://placehold.co/800x800?text=NEXORA")+'" alt="'+esc(p.name)+'"><h2>'+esc(p.name)+'</h2><b class="price">'+money(p.price)+' ج.م</b>'+(Number(p.old_price)>Number(p.price)?'<del class="old">'+money(p.old_price)+' ج.م</del>':'')+'<p>'+esc(p.description||"لا يوجد وصف إضافي لهذا المنتج حاليًا.")+'</p><p class="muted">التصنيف: '+esc(p.category||"عام")+(p.brand?' · العلامة التجارية: '+esc(p.brand):'')+'</p><p class="muted">'+(p.stock>0?'متاح بالمخزون: '+Number(p.stock):'غير متاح حاليًا')+'</p><button class="primary" onclick="nxBuyOne(\''+String(p.id)+'\')">اطلب الآن</button><button class="add" style="margin-top:8px" onclick="nxToggleFavorite(\''+String(p.id)+'\',this)">'+(favorites.has(String(p.id))?'♥ إزالة من المفضلة':'♡ أضف إلى المفضلة')+'</button></div>';
  if(typeof window.openSheet==="function")window.openSheet("تفاصيل المنتج",html);
  else say("تعذر عرض تفاصيل المنتج.");
 };
 async function loadFavorites(){
  const grid=$("nxFavoriteGrid"),empty=$("nxFavoriteEmpty");if(!grid||!empty)return;
  if(!user){grid.innerHTML="";empty.textContent="سجّل الدخول لحفظ المفضلة ومزامنتها بين أجهزتك.";empty.style.display="block";return;}
  const {data,error}=await db.from("favorites").select("product_id,products(id,name,description,category,brand,price,old_price,image_url,stock,active)").eq("user_id",user.id);
  if(error){empty.textContent="تعذر تحميل المفضلة: "+error.message;empty.style.display="block";return;}
  favorites=new Set((data||[]).map(x=>String(x.product_id)));
  if(typeof renderProducts==="function")renderProducts();
  const rows=(data||[]).map(x=>x.products).filter(p=>p&&p.active!==false);
  grid.innerHTML=rows.map(p=>productCard(p,'<button class="add" style="background:#777;margin-top:6px" onclick="event.stopPropagation();nxToggleFavorite(\''+String(p.id)+'\')">إزالة من المفضلة</button>')).join("");
  empty.style.display=rows.length?"none":"block";
 }
 const favoriteLocks=new Set();
 window.nxToggleFavorite=async(id,button)=>{
  id=String(id);
  if(favoriteLocks.has(id))return;
  if(!await auth()){say("سجّل الدخول أولًا لحفظ المفضلة ومزامنتها بين أجهزتك.");showPage("login");return;}
  favoriteLocks.add(id);if(button)button.disabled=true;
  try{
   let error;
   if(favorites.has(id)){
    ({error}=await db.from("favorites").delete().eq("user_id",user.id).eq("product_id",id));
    if(!error){favorites.delete(id);say("تمت إزالة المنتج من المفضلة.");}
   }else{
    ({error}=await db.from("favorites").upsert({user_id:user.id,product_id:id},{onConflict:"user_id,product_id",ignoreDuplicates:true}));
    if(!error){favorites.add(id);say("تمت إضافة المنتج للمفضلة ♥");}
   }
   if(error){say("تعذر تحديث المفضلة: "+error.message);await loadFavorites();return;}
   document.querySelectorAll('[data-fav="'+CSS.escape(id)+'"]').forEach(b=>b.textContent=favorites.has(id)?"♥":"♡");
   await loadFavorites();
   if(typeof renderProducts==="function")renderProducts();
  }finally{favoriteLocks.delete(id);if(button)button.disabled=false;}
 };
 async function buy(items){
  if(!await auth()){say("سجّل الدخول أولًا للشراء من رصيدك.");showPage("login");return;}
  const {data:orderId,error}=await db.rpc("place_wallet_order",{p_items:items});
  if(error){say(error.message.includes("insufficient_balance")?"رصيدك غير كافٍ. اشحن محفظتك أولًا.":"تعذر إتمام الطلب: "+error.message);return;}
  say("تم تأكيد طلبك رقم #"+orderId+" وخصم قيمته من رصيدك.");
  if(typeof window.renderCart==="function"){if(typeof cart!=="undefined")cart=[];const c=$("cartCount");if(c)c.textContent="0";window.renderCart();}
  await loadOrders();window.dispatchEvent(new Event("nexora:wallet-refresh"));
 }
 window.nxBuyOne=async id=>buy([{product_id:id,quantity:1}]);
 window.nxWalletCheckout=async()=>{
  if(typeof cart==="undefined"||!cart.length){say("السلة فارغة.");return;}
  const grouped=new Map();
  for(const p of cart){if(!p[5]){say("حدّث قائمة المنتجات ثم حاول مرة أخرى.");return;}const v=grouped.get(p[5])||0;grouped.set(p[5],v+1);}
  await buy([...grouped].map(([product_id,quantity])=>({product_id,quantity})));
 };
 window.nxCancelOrder=async id=>{
  if(!confirm("هل تريد إلغاء الطلب؟ سيتم رد المبلغ إلى رصيدك إذا كان الطلب لم يبدأ تجهيزه."))return;
  const {error}=await db.rpc("cancel_wallet_order",{p_order_id:id});
  if(error){say(error.message.includes("order_cannot_be_cancelled")?"لا يمكن إلغاء الطلب بعد بدء التجهيز أو الشحن. تواصل مع الدعم.":"تعذر إلغاء الطلب: "+error.message);return;}
  say("تم إلغاء الطلب ورد المبلغ إلى محفظتك.");await loadOrders();window.dispatchEvent(new Event("nexora:wallet-refresh"));
 };
 window.nxRefundReturnedOrder=async(id)=>{if(!confirm("هل استلمت المنتج المرتجع وفحصته؟ سيتم رد كامل المبلغ إلى محفظة العميل."))return;const {error}=await db.rpc("owner_refund_returned_wallet_order",{p_order_id:id});if(error){say("تعذر رد المبلغ: "+error.message);return;}say("تم رد المبلغ إلى محفظة العميل وإرجاع المنتج للمخزون.");await loadOrders();window.dispatchEvent(new Event("nexora:wallet-refresh"));};
 window.nxOwnerOrderStatus=async(id,next)=>{
  const {error}=await db.rpc("owner_update_order_status",{p_order_id:id,p_status:next});
  if(error){say("تعذر تحديث حالة الطلب: "+error.message);return;}say("تم تحديث حالة الطلب.");await loadOrders();
 };
 async function loadOrders(){
  if(!db)return;await auth();if(!user){$("nxCustomerOrders").textContent="سجّل الدخول لعرض طلباتك.";return;}
  const {data,error}=await db.from("orders").select("id,total,status,payment_method,created_at,order_items(product_name,unit_price,quantity,line_total)").order("created_at",{ascending:false}).limit(isOwner?100:30);
  if(error){$("nxCustomerOrders").textContent=error.message;return;}
  const mine=data||[];
  $("nxCustomerOrders").innerHTML=mine.map(o=>'<div class="admin-line"><b>طلب #'+o.id+' — '+money(o.total)+' ج.م</b><br><small>'+status[o.status]+' · '+new Date(o.created_at).toLocaleString("ar-EG")+'</small><ul>'+ (o.order_items||[]).map(i=>'<li>'+esc(i.product_name)+' × '+i.quantity+' — '+money(i.line_total)+' ج.م</li>').join("")+'</ul>'+(o.status==="placed"?'<button class="primary" style="background:#a33" onclick="nxCancelOrder('+o.id+')">إلغاء الطلب واسترداد المبلغ</button>':"")+'</div>').join("")||"لا توجد طلبات حتى الآن.";
  if(isOwner&&$("nxOwnerOrdersList"))$("nxOwnerOrdersList").innerHTML=mine.map(o=>'<div class="admin-line"><b>طلب #'+o.id+' — '+money(o.total)+' ج.م</b><br><small>'+status[o.status]+' · '+new Date(o.created_at).toLocaleString("ar-EG")+'</small><ul>'+(o.order_items||[]).map(i=>'<li>'+esc(i.product_name)+' × '+i.quantity+'</li>').join("")+'</ul>'+(o.status==="placed"?'<button class="primary" onclick="nxOwnerOrderStatus('+o.id+',\'processing\')">بدء التجهيز</button>':o.status==="processing"?'<button class="primary" onclick="nxOwnerOrderStatus('+o.id+',\'shipped\')">تم الشحن</button>':o.status==="shipped"?'<button class="primary" onclick="nxOwnerOrderStatus('+o.id+',\'completed\')">إكمال الطلب</button>':o.status==="completed"?'<button class="primary" style="background:#a33" onclick="nxRefundReturnedOrder('+o.id+')">تأكيد استلام المرتجع ورد المبلغ</button>':"")+'</div>').join("")||"لا توجد طلبات.";}
 async function refresh(){await auth();ensurePanels();setupBrandCollections();addFavButtons();await loadFavorites();await loadOrders();}
 if(db){db.auth.onAuthStateChange(()=>setTimeout(refresh,0));if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",refresh);else refresh();}
 const oldShow=window.showPage;window.showPage=function(id,el){oldShow(id,el);if(id==="favorites")loadFavorites();if(id==="profile")loadOrders();};
 const css=document.createElement("style");css.textContent='.nx-product-card{cursor:pointer}.nx-product-detail{direction:rtl}.nx-product-detail>img{width:100%;max-height:55vh;object-fit:contain;background:#fff;border-radius:10px}.nx-product-detail h2{font-size:19px;line-height:1.6}.nx-product-detail p{line-height:1.9;color:#555}.nx-fav{position:absolute;top:9px;left:9px;width:36px;height:36px;border:0;border-radius:50%;background:#fff;color:#b35a65;font-size:23px;box-shadow:0 2px 9px #0002;z-index:2}.product{position:relative}.nx-fav:active{transform:scale(.94)}';document.head.appendChild(css);
})();
