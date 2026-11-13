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
  $("nxBrandProducts").innerHTML=rows.map(p=>'<article class="product"><img loading="lazy" src="'+esc(p.image_url)+'" alt="'+esc(p.name)+'"><div class="name">'+esc(p.name)+'</div><b class="price">'+money(p.price)+' ج.م</b><button class="add" onclick="nxBuyOne(\''+p.id+'\')">اطلب الآن</button></article>').join("");
  $("nxBrandEmpty").style.display=rows.length?"none":"block";
 }

 function addFavButtons(){
  if(typeof window.product!=="function")return;
  const original=window.product;
  if(original.__nxWrapped)return;
  const wrapped=function(p,i){const html=original(p,i);const id=p[5];if(!id)return html;return html.replace('</article>','<button class="nx-fav" aria-label="إضافة للمفضلة" data-fav="'+id+'" onclick="nxToggleFavorite(\''+id+'\',this)">♡</button></article>');};
  wrapped.__nxWrapped=true;window.product=wrapped;
 }
 async function loadFavorites(){
  if(!user){$("nxFavoriteGrid").innerHTML="";$("nxFavoriteEmpty").textContent="سجّل الدخول لحفظ المفضلة ومزامنتها بين أجهزتك.";return;}
  const {data,error}=await db.from("favorites").select("product_id,products(id,name,description,category,price,old_price,image_url,stock,active)").eq("user_id",user.id);
  if(error){$("nxFavoriteEmpty").textContent="تعذر تحميل المفضلة: "+error.message;return;}
  favorites=new Set((data||[]).map(x=>x.product_id));
  const rows=(data||[]).map(x=>x.products).filter(Boolean);
  $("nxFavoriteGrid").innerHTML=rows.map(p=>'<article class="product"><img loading="lazy" src="'+esc(p.image_url)+'" alt="'+esc(p.name)+'"><div class="name">'+esc(p.name)+'</div><b class="price">'+money(p.price)+' ج.م</b><button class="add" onclick="nxBuyOne(\''+p.id+'\')">اطلب الآن</button><button class="add" style="background:#777;margin-top:6px" onclick="nxToggleFavorite(\''+p.id+'\')">إزالة من المفضلة</button></article>').join("");
  $("nxFavoriteEmpty").style.display=rows.length?"none":"block";
 }
 window.nxToggleFavorite=async(id,button)=>{
  if(!await auth()){say("سجّل الدخول أولًا لحفظ المنتجات في المفضلة.");showPage("login");return;}
  if(favorites.has(id)){const {error}=await db.from("favorites").delete().eq("user_id",user.id).eq("product_id",id);if(error){say(error.message);return;}favorites.delete(id);say("تمت إزالة المنتج من المفضلة.");}
  else{const {error}=await db.from("favorites").insert({user_id:user.id,product_id:id});if(error){say("تعذر حفظ المفضلة: "+error.message);return;}favorites.add(id);say("تمت إضافة المنتج للمفضلة ♡");}
  if(button)button.textContent=favorites.has(id)?"♥":"♡";await loadFavorites();
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
 const css=document.createElement("style");css.textContent='.nx-fav{position:absolute;top:9px;left:9px;width:36px;height:36px;border:0;border-radius:50%;background:#fff;color:#b35a65;font-size:23px;box-shadow:0 2px 9px #0002;z-index:2}.product{position:relative}.nx-fav:active{transform:scale(.94)}';document.head.appendChild(css);
})();
