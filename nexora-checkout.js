(() => {
 const cfg=window.NEXORA_CONFIG||{};
 const sb=window.supabase&&cfg.supabaseUrl&&cfg.supabaseAnonKey?window.supabase.createClient(cfg.supabaseUrl,cfg.supabaseAnonKey):null;
 const $=id=>document.getElementById(id);
 const esc=s=>String(s??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
 let cashNumber="";
 async function nxVodafoneCheckout(){
  if(!sb){toast("قاعدة البيانات غير متاحة حاليًا");return;}
  if(!cart||!cart.length){toast("السلة فارغة");return;}
  const {data:{user},error}=await sb.auth.getUser();
  if(error||!user){toast("سجّل الدخول أولًا لإتمام الطلب");showPage("login");return;}
  const {data:settings}=await sb.from("store_settings").select("setting_value").eq("setting_key","transfer_number").maybeSingle();
  cashNumber=(settings?.setting_value||"").trim();
  if(!cashNumber){toast("صاحب المتجر لم يحدد رقم فودافون كاش بعد");return;}
  const total=cart.reduce((s,p)=>s+Number(p[2]||0),0);
  openSheet("الدفع عبر فودافون كاش",`
   <div class="panel" style="margin:0 0 12px">
    <b>حوّل إجمالي الطلب إلى الرقم التالي</b>
    <div style="font-size:24px;font-weight:800;direction:ltr;text-align:center;margin:12px 0">${esc(cashNumber)}</div>
    <button class="primary" onclick="navigator.clipboard?.writeText('${esc(cashNumber)}');toast('تم نسخ الرقم إذا كان النسخ مدعومًا')">نسخ الرقم</button>
    <p>المبلغ المطلوب: <b>${total.toLocaleString("ar-EG")} جنيه</b></p>
    <small>حوّل المبلغ من محفظتك، ثم اكتب رقم الهاتف الذي أرسل التحويل منه ورقم العملية/مرجع التحويل. لا ترسل بيانات سرية أو الرقم السري للمحفظة.</small>
   </div>
   <label>رقم الهاتف الذي أرسلت منه التحويل</label><input class="field" id="nxCashSender" inputmode="tel" placeholder="01xxxxxxxxx">
   <label>رقم العملية أو مرجع التحويل</label><input class="field" id="nxCashRef" placeholder="اكتب مرجع التحويل">
   <button class="primary" onclick="nxSubmitVodafoneOrder()">تأكيد إرسال الطلب</button>
   <p class="muted" id="nxCashError"></p>
  `);
 }
 async function nxSubmitVodafoneOrder(){
  const sender=$("nxCashSender")?.value.trim(),ref=$("nxCashRef")?.value.trim();
  if(!sender||!ref){$("nxCashError").textContent="اكتب رقم الهاتف ومرجع التحويل.";return;}
  const grouped=new Map();
  cart.forEach(p=>{const key=p[0];const old=grouped.get(key);if(old)old.quantity++;else grouped.set(key,{product_name:key,unit_price:Number(p[2]),quantity:1});});
  const {data,error}=await sb.rpc("place_vodafone_order",{p_items:[...grouped.values()],p_sender_phone:sender,p_transfer_reference:ref});
  if(error){$("nxCashError").textContent="تعذر تسجيل الطلب: "+error.message;return;}
  const id=data?.[0]?.order_id;
  cart=[];$("cartCount").textContent="0";renderCart();closeSheet();
  toast("تم تسجيل طلبك رقم #"+id+"، وسيتم مراجعته بعد التحقق من التحويل.");
  nxLoadVodafoneOrders();
 }
 async function nxLoadVodafoneOrders(){
  if(!sb)return;
  const {data:{user}}=await sb.auth.getUser();if(!user)return;
  const owner=(user.email||"").toLowerCase()==="jo306843@gmail.com";
  const {data,error}=await sb.from("orders").select("id,user_id,total,status,sender_phone,transfer_reference,created_at").order("created_at",{ascending:false}).limit(owner?100:30);
  let panel=$("nxVodafoneOrders");
  if(!panel&&owner&&$("admin")){panel=document.createElement("div");panel.id="nxVodafoneOrders";panel.className="panel";panel.innerHTML="<h3>طلبات الشراء — فودافون كاش</h3><div id='nxVodafoneOrdersList'></div>";$("admin").appendChild(panel);}
  const list=$("nxVodafoneOrdersList");if(!list)return;
  if(error){list.textContent=error.message;return;}
  list.innerHTML=(data||[]).map(o=>'<div class="admin-line"><b>طلب #'+o.id+' · '+Number(o.total).toLocaleString("ar-EG")+' ج.م</b><br><small>العميل: '+esc(o.user_id)+'<br>رقم المرسل: '+esc(o.sender_phone)+' · مرجع التحويل: '+esc(o.transfer_reference)+'<br>الحالة: '+esc(o.status)+' · '+new Date(o.created_at).toLocaleString("ar-EG")+'</small>'+(owner&&o.status==="pending_review"?'<div style="display:flex;gap:8px;margin-top:8px"><button class="primary" onclick="nxReviewVodafone('+o.id+',\'paid\')">تأكيد استلام التحويل</button><button class="primary" style="background:#a33" onclick="nxReviewVodafone('+o.id+',\'rejected\')">رفض الطلب</button></div>':"")+'</div>').join("")||"لا توجد طلبات شراء.";
 }
 async function nxReviewVodafone(id,status){
  const note=prompt(status==="paid"?"اكتب ملاحظة تأكيد استلام التحويل بعد التحقق الفعلي:":"اكتب سبب رفض الطلب:");
  if(note===null)return;
  if(status==="paid"&&note.trim().length<3){toast("تحقق من التحويل واكتب ملاحظة");return;}
  const {error}=await sb.rpc("owner_review_vodafone_order",{p_order_id:id,p_status:status,p_note:note});
  if(error){toast("تعذر تحديث الطلب: "+error.message);return;}
  toast("تم تحديث حالة الطلب");nxLoadVodafoneOrders();
 }
 window.nxVodafoneCheckout=nxVodafoneCheckout;
 window.nxSubmitVodafoneOrder=nxSubmitVodafoneOrder;
 window.nxReviewVodafone=nxReviewVodafone;
 if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",nxLoadVodafoneOrders);else nxLoadVodafoneOrders();
 if(sb)sb.auth.onAuthStateChange(()=>setTimeout(nxLoadVodafoneOrders,300));
})();