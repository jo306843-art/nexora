(() => {
  const cfg = window.NEXORA_CONFIG || {};
  const configured = cfg.supabaseUrl?.startsWith("https://") && cfg.supabaseAnonKey?.length > 20;
  const sb = configured && window.supabase ? window.supabase.createClient(cfg.supabaseUrl, cfg.supabaseAnonKey) : null;
  const $ = (id) => document.getElementById(id);
  const money = n => Number(n || 0).toLocaleString("ar-EG", {maximumFractionDigits:2});
  let user = null, profile = null, products = [], cart = [], authMode = "login", moneyType = "deposit";
  const demo = [
    {id:"watch-silver",name:"ساعة ERYS فضي بمينا كحلي",price:2200,image_url:"https://raw.githubusercontent.com/jo306843-art/waheeb-store/main/watch_01.jpg",stock:10},
    {id:"watch-black",name:"ساعة ERYS أسود",price:2200,image_url:"https://raw.githubusercontent.com/jo306843-art/waheeb-store/main/watch_02_black.jpg",stock:10},
    {id:"watch-gold",name:"ساعة ERYS ذهبي",price:2200,image_url:"https://raw.githubusercontent.com/jo306843-art/waheeb-store/main/watch_03_gold.jpg",stock:10}
  ];
  function toast(msg){$("toast").textContent=msg;$("toast").classList.add("show");setTimeout(()=>$("toast").classList.remove("show"),2800)}
  function moneyNum(n){return Number(n||0).toFixed(2)}
  function renderProducts(){
    $("product-count").textContent=`${products.length} منتجات`;
    $("products-grid").innerHTML=products.map(p=>`<article class="product"><img src="${escapeHtml(p.image_url||"")}" alt="${escapeHtml(p.name)}" onerror="this.style.visibility='hidden'"><div class="product-info"><h3>${escapeHtml(p.name)}</h3><div class="price">${money(p.price)} جنيه</div><div class="product-actions"><button class="btn btn-primary" data-add="${escapeHtml(p.id)}">أضف للسلة</button></div></div></article>`).join("") || '<p class="muted">لا توجد منتجات متاحة حاليًا.</p>';
    document.querySelectorAll("[data-add]").forEach(b=>b.onclick=()=>{const p=products.find(x=>String(x.id)===b.dataset.add);if(p){cart.push(p);renderCart();toast("تمت إضافة المنتج للسلة")}})
  }
  function escapeHtml(v){return String(v??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]))}
  function renderCart(){
    $("cart-count").textContent=`${cart.length} منتجات`;
    $("cart-total").textContent=money(cart.reduce((s,p)=>s+Number(p.price),0));
    $("cart-items").innerHTML=cart.length?cart.map((p,i)=>`<div class="cart-row"><div><strong>${escapeHtml(p.name)}</strong><small>${money(p.price)} جنيه</small></div><button class="text-btn" data-remove="${i}">حذف</button></div>`).join(""):'<p class="muted">سلتك فارغة حاليًا.</p>';
    document.querySelectorAll("[data-remove]").forEach(b=>b.onclick=()=>{cart.splice(Number(b.dataset.remove),1);renderCart()})
  }
  async function loadProducts(){
    if(sb){const {data,error}=await sb.from("products").select("id,name,price,image_url,stock").eq("active",true).order("id");if(!error&&data?.length){products=data;renderProducts();return}}
    products=demo;renderProducts();
    if(!sb) $("account-message").textContent="المعاينة تعمل الآن. أضف بيانات Supabase في config.js لتفعيل الحسابات والطلبات.";
  }
  async function refreshSession(){
    if(!sb)return;
    const {data}=await sb.auth.getSession();user=data.session?.user||null;
    if(user){const r=await sb.from("profiles").select("full_name,role").eq("id",user.id).maybeSingle();profile=r.data}
    updateUser();await loadOrders();await loadAdmin();
  }
  function updateUser(){
    $("user-label").textContent=user?(profile?.full_name||user.email):"زائر";
    $("auth-open").classList.toggle("hidden",!!user);$("logout").classList.toggle("hidden",!user);
    $("account-message").textContent=user?`مرحبًا ${profile?.full_name||user.email}`:"لم تسجل الدخول بعد.";
    $("account-auth").classList.toggle("hidden",!!user);
  }
  function openAuth(){authMode="login";$("auth-title").textContent="تسجيل الدخول";$("auth-submit").textContent="دخول";$("name-wrap").classList.add("hidden");$("auth-switch").textContent="إنشاء حساب جديد";$("auth-error").textContent="";$("auth-dialog").showModal()}
  $("auth-open").onclick=openAuth;$("account-auth").onclick=openAuth;
  $("auth-switch").onclick=()=>{authMode=authMode==="login"?"signup":"login";$("auth-title").textContent=authMode==="login"?"تسجيل الدخول":"إنشاء حساب جديد";$("auth-submit").textContent=authMode==="login"?"دخول":"إنشاء الحساب";$("name-wrap").classList.toggle("hidden",authMode==="login");$("auth-switch").textContent=authMode==="login"?"إنشاء حساب جديد":"لدي حساب بالفعل"};
  $("auth-form").onsubmit=async e=>{e.preventDefault();if(!sb){$("auth-error").textContent="أضف إعدادات Supabase أولًا في config.js.";return}
    const email=$("auth-email").value.trim(),password=$("auth-password").value;
    let result;
    if(authMode==="login") result=await sb.auth.signInWithPassword({email,password});
    else result=await sb.auth.signUp({email,password,options:{data:{full_name:$("auth-name").value.trim()}}});
    if(result.error){$("auth-error").textContent=result.error.message;return}
    $("auth-dialog").close();toast(authMode==="login"?"تم تسجيل الدخول":"تم إنشاء الحساب. راجع بريدك إذا طُلب تأكيده.");await refreshSession();
  };
  $("logout").onclick=async()=>{if(sb)await sb.auth.signOut();user=null;profile=null;updateUser();$("orders-list").textContent="سجّل الدخول لعرض طلباتك.";toast("تم تسجيل الخروج")};
  $("checkout").onclick=async()=>{
    if(!user){openAuth();toast("سجّل الدخول أولًا");return}
    if(!cart.length){toast("السلة فارغة");return}
    if(!sb){toast("اربط Supabase أولًا");return}
    const items=cart.map(p=>({product_id:Number.isFinite(Number(p.id))?Number(p.id):null,product_name:p.name,quantity:1}));
    const {data,error}=await sb.rpc("place_order",{items});
    if(error){toast("تعذر إنشاء الطلب: "+error.message);return}
    cart=[];renderCart();toast("تم تسجيل طلبك بنجاح");await loadOrders();
  };
  async function loadOrders(){
    if(!user||!sb){$("orders-list").textContent="سجّل الدخول لعرض طلباتك.";return}
    const {data,error}=await sb.from("orders").select("id,total,status,created_at").order("created_at",{ascending:false}).limit(20);
    $("orders-list").innerHTML=error?`<p class="error">${escapeHtml(error.message)}</p>`:data?.length?data.map(o=>`<div class="admin-line"><strong>طلب #${o.id}</strong> — ${money(o.total)} جنيه<br><span class="muted">${escapeHtml(o.status)} · ${new Date(o.created_at).toLocaleDateString("ar-EG")}</span></div>`).join(""):"لا توجد طلبات حتى الآن.";
  }
  $("refresh-orders").onclick=loadOrders;
  function openMoney(type){if(!user){openAuth();return}moneyType=type;$("money-title").textContent=type==="deposit"?"طلب إيداع":"طلب سحب";$("money-error").textContent="";$("money-dialog").showModal()}
  $("deposit-open").onclick=()=>openMoney("deposit");$("withdraw-open").onclick=()=>openMoney("withdrawal");
  $("money-form").onsubmit=async e=>{e.preventDefault();if(!sb||!user){$("money-error").textContent="تعذر الاتصال بقاعدة البيانات.";return}
    const amount=Number($("money-amount").value);if(amount<=0)return;
    const {error}=await sb.from("money_requests").insert({user_id:user.id,request_type:moneyType,amount,payment_number:$("money-number").value.trim()||null});
    if(error){$("money-error").textContent=error.message;return}
    $("money-dialog").close();$("wallet-message").textContent="تم إرسال طلبك، وهو الآن قيد مراجعة الإدارة.";toast("تم إرسال الطلب للمراجعة");
  };
  async function loadAdmin(){
    if(!sb||profile?.role!=="admin"){$("admin").classList.add("hidden");return}
    $("admin").classList.remove("hidden");
    const [orders,moneyReq]=await Promise.all([
      sb.from("orders").select("id,total,status,created_at").order("created_at",{ascending:false}).limit(30),
      sb.from("money_requests").select("id,user_id,request_type,amount,payment_number,status,created_at").order("created_at",{ascending:false}).limit(30)
    ]);
    $("admin-orders").innerHTML=orders.error?escapeHtml(orders.error.message):(orders.data||[]).map(o=>`<div class="admin-line">طلب #${o.id} · ${money(o.total)} ج · ${escapeHtml(o.status)}<br><button class="btn btn-outline" data-status="${o.id}|processing">قيد التجهيز</button><button class="btn btn-outline" data-status="${o.id}|shipped">تم الشحن</button></div>`).join("")||"لا توجد طلبات.";
    $("admin-money").innerHTML=moneyReq.error?escapeHtml(moneyReq.error.message):(moneyReq.data||[]).map(m=>`<div class="admin-line">#${m.id} · ${m.request_type==="deposit"?"إيداع":"سحب"} · ${money(m.amount)} ج · ${escapeHtml(m.status)}<br><small>${escapeHtml(m.payment_number||"بدون رقم")}</small><br><button class="btn btn-outline" data-money="${m.id}|approved">اعتماد</button><button class="btn btn-outline" data-money="${m.id}|rejected">رفض</button></div>`).join("")||"لا توجد طلبات محفظة.";
    document.querySelectorAll("[data-status]").forEach(b=>b.onclick=async()=>{const [id,status]=b.dataset.status.split("|");const {error}=await sb.from("orders").update({status}).eq("id",id);if(error)toast(error.message);else{toast("تم تحديث حالة الطلب");loadAdmin()}});
    document.querySelectorAll("[data-money]").forEach(b=>b.onclick=async()=>{const [id,status]=b.dataset.money.split("|");const {error}=await sb.rpc("admin_review_money_request",{request_id:Number(id),new_status:status});if(error)toast(error.message);else{toast("تم تحديث طلب المحفظة");loadAdmin()}});
  }
  if(!configured){$("account-message").textContent="الموقع في وضع المعاينة. أدخل Project URL وPublishable Key في config.js لتفعيل الخدمات."}
  loadProducts();renderCart();refreshSession();
  if(sb)sb.auth.onAuthStateChange(()=>setTimeout(refreshSession,0));
})();