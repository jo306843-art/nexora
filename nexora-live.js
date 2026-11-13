(() => {
  const cfg = window.NEXORA_CONFIG || {};
  const client = window.supabase && cfg.supabaseUrl && cfg.supabaseAnonKey
    ? window.supabase.createClient(cfg.supabaseUrl, cfg.supabaseAnonKey) : null;
  const $ = id => document.getElementById(id);
  const OWNER = "jo306843@gmail.com";
  let currentUser = null, owner = false, settings = {};
  const esc = v => String(v ?? "").replace(/[&<>"']/g, c => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
  const money = v => Number(v || 0).toLocaleString("ar-EG",{minimumFractionDigits:2,maximumFractionDigits:2});
  const say = msg => typeof window.toast === "function" ? window.toast(msg) : alert(msg);
  const statusName = s => ({pending:"قيد المراجعة",approved:"مقبول",rejected:"مرفوض"}[s] || s);
  async function loadSettings(){
    if(!client) return;
    const {data,error}=await client.from("store_settings").select("setting_key,setting_value");
    if(error) return;
    settings=Object.fromEntries((data||[]).map(x=>[x.setting_key,x.setting_value]));
    const phone=settings.transfer_number||"لم يحدده صاحب المتجر بعد";
    if($("customerPhone")) $("customerPhone").textContent=phone;
    if($("admPhone")) $("admPhone").textContent=settings.transfer_number||"غير محدد";
    if($("ownerPhone")) $("ownerPhone").value=settings.transfer_number||"";
    if($("ownerTelegram")) $("ownerTelegram").value="@"+(settings.telegram_username||"Vvcghy").replace(/^@/,"");
    const link=$("telegramSupportLink"), handle=(settings.telegram_username||"Vvcghy").replace(/^@/,"");
    if(link) link.href="https://t.me/"+handle;
    if($("supportUnavailable")) $("supportUnavailable").style.display="none";
  }
  function setWalletBalance(v){
    const value=money(v)+" ج.م";
    if($("walletBalance")) $("walletBalance").textContent=value;
    if($("customerBalance")) $("customerBalance").textContent=money(v);
  }
  async function loadWallet(){
    if(!client || !currentUser){setWalletBalance(0);if($("customerWalletRequests")) $("customerWalletRequests").textContent="سجّل الدخول لعرض محفظتك وطلباتك.";return;}
    const [wallet,requests,ledger]=await Promise.all([
      client.from("wallets").select("balance").eq("user_id",currentUser.id).maybeSingle(),
      client.from("wallet_requests").select("id,request_type,amount,status,created_at,review_note").eq("user_id",currentUser.id).order("created_at",{ascending:false}).limit(30),
      client.from("wallet_ledger").select("amount,balance_after,reason,created_at").eq("user_id",currentUser.id).order("created_at",{ascending:false}).limit(20)
    ]);
    if(wallet.error) say("تعذر تحميل الرصيد: "+wallet.error.message);
    setWalletBalance(wallet.data?.balance||0);
    const req= $("customerWalletRequests");
    if(req) req.innerHTML=requests.error?esc(requests.error.message):(requests.data||[]).map(x=>'<div style="padding:10px 0;border-bottom:1px solid #E8E6DF"><b>'+(x.request_type==="deposit"?"إيداع":"سحب")+' · '+money(x.amount)+' ج.م</b><br><small>#'+x.id+' — '+statusName(x.status)+' — '+new Date(x.created_at).toLocaleString("ar-EG")+(x.review_note?" — "+esc(x.review_note):"")+'</small></div>').join("")||"لا توجد طلبات بعد.";
    if($("walletLedger")) $("walletLedger").innerHTML=ledger.error?esc(ledger.error.message):(ledger.data||[]).map(x=>'<div style="padding:8px 0;border-bottom:1px solid #eee"><b>'+ (Number(x.amount)>0?"+":"")+money(x.amount)+' ج.م</b> — '+esc(x.reason)+'<br><small>'+new Date(x.created_at).toLocaleString("ar-EG")+' · الرصيد بعد الحركة '+money(x.balance_after)+'</small></div>').join("")||"لا توجد حركات مالية بعد.";
  }
  async function loadAdmin(){
    if(!owner || !client) return;
    const [profiles,wallets,requests,ledger]=await Promise.all([
      client.from("profiles").select("id,email,full_name,role").order("created_at",{ascending:false}).limit(200),
      client.from("wallets").select("user_id,balance"),
      client.from("wallet_requests").select("id,user_id,request_type,amount,status,sender_phone,payout_phone,transfer_reference,created_at").order("created_at",{ascending:false}).limit(100),
      client.from("wallet_ledger").select("user_id,amount,balance_after,reason,operator_id,created_at").order("created_at",{ascending:false}).limit(100)
    ]);
    const balanceMap=Object.fromEntries((wallets.data||[]).map(x=>[x.user_id,x.balance]));
    const names=Object.fromEntries((profiles.data||[]).map(x=>[x.id,x.email]));
    if($("adminUsers")) $("adminUsers").innerHTML=profiles.error?esc(profiles.error.message):(profiles.data||[]).map(u=>'<div class="admin-line"><b>'+esc(u.full_name||u.email)+'</b><br><small>'+esc(u.email)+' · '+esc(u.id)+'</small><br><b>الرصيد: '+money(balanceMap[u.id]||0)+' ج.م</b><div style="display:grid;grid-template-columns:1fr 1fr;gap:6px;margin-top:8px"><input class="field" id="adj-'+u.id+'" type="number" step="0.01" placeholder="+ أو - مبلغ"><input class="field" id="reason-'+u.id+'" placeholder="سبب التعديل"><button class="primary" style="grid-column:1/-1" onclick="nxAdjustWallet(\''+u.id+'\')">تنفيذ وتسجيل الحركة</button></div></div>').join("")||"لا يوجد عملاء.";
    if($("adminWalletRequests")) $("adminWalletRequests").innerHTML=requests.error?esc(requests.error.message):(requests.data||[]).map(x=>'<div class="admin-line"><b>#'+x.id+' · '+(x.request_type==="deposit"?"إيداع":"سحب")+' · '+money(x.amount)+' ج.م</b><br><small>'+esc(names[x.user_id]||x.user_id)+' · '+statusName(x.status)+'<br>رقم المرسل: '+esc(x.sender_phone||"—")+' · رقم الاستلام: '+esc(x.payout_phone||"—")+'<br>مرجع التحويل: '+esc(x.transfer_reference||"—")+'<br>'+new Date(x.created_at).toLocaleString("ar-EG")+'</small>'+(x.status==="pending"?'<div style="display:flex;gap:8px;margin-top:8px"><button class="primary" style="background:#718A7D" onclick="nxReviewRequest('+x.id+',\'approved\')">اعتماد بعد التحقق</button><button class="primary" style="background:#a33" onclick="nxReviewRequest('+x.id+',\'rejected\')">رفض</button></div>':"")+'</div>').join("")||"لا توجد طلبات محفظة.";
    if($("adminLedger")) $("adminLedger").innerHTML=ledger.error?esc(ledger.error.message):(ledger.data||[]).map(x=>'<div class="admin-line"><b>'+esc(names[x.user_id]||x.user_id)+' · '+(Number(x.amount)>0?"+":"")+money(x.amount)+' ج.م</b><br><small>'+esc(x.reason)+' · '+new Date(x.created_at).toLocaleString("ar-EG")+' · المشغّل '+esc(x.operator_id||"النظام")+'</small></div>').join("")||"لا توجد حركات مسجلة.";
    if($("admWalletCount")) $("admWalletCount").textContent=(requests.data||[]).length;
    if($("admProducts")) $("admProducts").textContent=(profiles.data||[]).length;
  }
  window.nxAdjustWallet=async id=>{
    if(!owner)return;
    const amount=Number($("adj-"+id)?.value), reason=$("reason-"+id)?.value?.trim();
    if(!Number.isFinite(amount)||amount===0||!reason){say("أدخل مبلغًا موجبًا أو سالبًا وسببًا واضحًا.");return;}
    const {error}=await client.rpc("owner_adjust_wallet",{p_user_id:id,p_amount:amount,p_reason:reason});
    if(error){say("تعذر تعديل الرصيد: "+error.message);return;}
    say("تم تسجيل تعديل المحفظة.");await loadAdmin();await loadWallet();
  };
  window.nxReviewRequest=async(id,status)=>{
    if(!owner)return;
    const note=prompt(status==="approved"?"أكد أنك تحققت من التحويل فعليًا، واكتب ملاحظة المراجعة:":"اكتب سبب رفض الطلب:");
    if(note===null)return;
    if(status==="approved" && note.trim().length<3){say("لا تعتمد الإيداع قبل التحقق الفعلي من التحويل وكتابة ملاحظة.");return;}
    const {error}=await client.rpc("owner_review_wallet_request",{p_request_id:id,p_status:status,p_note:note});
    if(error){say("تعذر تحديث الطلب: "+error.message);return;}
    say("تم تحديث الطلب وتسجيل الحركة المالية.");await loadAdmin();await loadWallet();
  };
  window.submitWalletRequest=async type=>{
    if(!client){say("خدمة الحسابات غير متاحة حاليًا.");return;}
    if(!currentUser){showPage("login");say("سجّل الدخول أولًا.");return;}
    const deposit=type==="deposit";
    const amount=Number($(deposit?"depositAmount":"withdrawAmount")?.value);
    const phone=$(deposit?"depositSender":"withdrawPhone")?.value?.trim();
    const ref=$("depositRef")?.value?.trim()||"";
    if(!Number.isFinite(amount)||amount<=0||!phone){say("أدخل مبلغًا صحيحًا ورقم الهاتف.");return;}
    const row={user_id:currentUser.id,request_type:deposit?"deposit":"withdrawal",amount,
      sender_phone:deposit?phone:null,payout_phone:deposit?null:phone,transfer_reference:deposit?ref:null};
    const {error}=await client.from("wallet_requests").insert(row);
    if(error){say("تعذر إرسال الطلب: "+error.message);return;}
    $(deposit?"depositAmount":"withdrawAmount").value="";
    say("تم إرسال الطلب للمراجعة.");await loadWallet();
  };
  window.saveOwnerSettings=async()=>{
    if(!owner)return;
    const transfer=$("ownerPhone")?.value?.trim()||"";
    const telegram=($("ownerTelegram")?.value?.trim()||"@Vvcghy").replace(/^@/,"");
    if(!/^[A-Za-z0-9_]{5,32}$/.test(telegram)){say("اسم تليجرام غير صحيح.");return;}
    const {error}=await client.rpc("owner_set_store_settings",{p_transfer_number:transfer,p_telegram_username:telegram});
    if(error){say("تعذر حفظ الإعدادات: "+error.message);return;}
    say("تم حفظ رقم التحويل والدعم لكل العملاء.");await loadSettings();
  };
  window.saveSupportSettings=window.saveOwnerSettings;
  async function refresh(){
    if(!client){say("تعذر الاتصال بخدمة الحسابات. راجع إعدادات Supabase.");return;}
    const {data:{session}}=await client.auth.getSession();
    currentUser=session?.user||null;owner=(currentUser?.email||"").toLowerCase()===OWNER;
    const name=currentUser?.user_metadata?.full_name||currentUser?.email||"زائر";
    const profileName=document.querySelector(".member-meta b");
    if(profileName)profileName.textContent=name;
    const avatar=document.querySelector(".avatar");if(avatar)avatar.textContent=(name[0]||"N").toUpperCase();
    if($("customerBalance")) $("customerBalance").textContent="0.00";
    const adminButton=$("ownerAdminShortcut");
    if(owner && !adminButton){
      const tools=document.querySelector(".profile-tools");
      if(tools){const b=document.createElement("button");b.id="ownerAdminShortcut";b.innerHTML="<i>⚙️</i>لوحة المالك";b.onclick=()=>showPage("admin");tools.appendChild(b);}
    } else if(!owner && adminButton) adminButton.remove();
    if($("loginStatus")) $("loginStatus").textContent=currentUser?"تم تسجيل الدخول: "+currentUser.email:"لم تسجل الدخول بعد.";
    if($("loginSubmit")) $("loginSubmit").textContent="تسجيل الدخول";
    await loadSettings();await loadWallet();if(owner)await loadAdmin();
    if($("ownerBalance")) $("ownerBalance").closest(".panel")?.remove();
  }
  window.nxLogin=async()=>{
    if(!client){say("خدمة تسجيل الدخول غير مهيأة.");return;}
    const email=$("loginEmail")?.value?.trim().toLowerCase(),password=$("loginPassword")?.value;
    if(!email||!password){say("أدخل البريد الإلكتروني وكلمة المرور.");return;}
    const {error}=await client.auth.signInWithPassword({email,password});
    if(error){say("تعذر تسجيل الدخول: "+error.message);return;}
    say("تم تسجيل الدخول.");await refresh();showPage("profile");
  };
  window.nxSignup=async()=>{
    if(!client){say("خدمة التسجيل غير مهيأة.");return;}
    const email=$("loginEmail")?.value?.trim().toLowerCase(),password=$("loginPassword")?.value,name=$("loginName")?.value?.trim()||"";
    if(!email||!password||password.length<8){say("أدخل بريدًا صحيحًا وكلمة مرور من 8 أحرف على الأقل.");return;}
    const {error}=await client.auth.signUp({email,password,options:{data:{full_name:name}}});
    if(error){say("تعذر إنشاء الحساب: "+error.message);return;}
    say("تم إنشاء الحساب. أكّد بريدك إذا طلبت الخدمة ذلك ثم سجّل الدخول.");
  };
  window.nxLogout=async()=>{if(client)await client.auth.signOut();currentUser=null;owner=false;await refresh();showPage("profile");};
  const oldShow=window.showPage;
  window.showPage=function(id,el){
    if(id==="admin"&&!owner){say("لوحة الإدارة مخصصة لصاحب المتجر فقط.");return;}
    oldShow(id,el);
    if(id==="wallet")loadWallet();
    if(id==="admin"&&owner)loadAdmin();
  };
  const oldCartCheckout=$("checkout");
  if(oldCartCheckout)oldCartCheckout.onclick=()=>say("إتمام الطلب يحتاج إعداد الدفع والطلبات على الخادم.");
  document.addEventListener("DOMContentLoaded",()=>{});
  if(client){
    client.auth.onAuthStateChange(()=>setTimeout(refresh,0));
    refresh();
  } else {
    if($("loginStatus"))$("loginStatus").textContent="خدمة الحسابات غير مهيأة. تحقق من إعدادات Supabase.";
  }
})();