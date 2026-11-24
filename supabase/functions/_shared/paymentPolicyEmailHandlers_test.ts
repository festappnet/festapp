import {assert, assertEquals, assertRejects, assertStringIncludes} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { PDFArray, PDFDict, PDFDocument, PDFHexString, PDFName } from "npm:pdf-lib";
Deno.env.set("SUPABASE_URL","https://local-payment-test.invalid");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY","local-test-only");
const {supabaseAdmin} = await import("./supabaseUtil.ts");
const {paymentRegistry} = await import("./payments/runtime.ts");
const {renderQueuedEmail} = await import("./emailRenderer.ts");
const {generateQrCode} = await import("./qrCodePayment.ts");
const {encodeAttachment} = await import("./emailDelivery.ts");
const {getTicketOrderConfirmationTemplate} = await import("../send-email/getTicketOrderConfirmationTemplate.ts");
const {fakturoidGateway} = await import("../send-ticket-order/fakturoid.ts");
import type {PaymentMethodBinding, HostedPaymentDependencies} from "./payments/contracts.ts";

// Exercise production handlers, completion and inherited wrapper; the only fake
// boundary is the already-authorized SQL/provider source. Any HTTP is forbidden.
Deno.test("production payment emails honor method, current collection and inherited wrappers", async () => {
 const originalRpc=supabaseAdmin.rpc, originalResolve=paymentRegistry.resolve, originalHas=paymentRegistry.has;
 const originalFetch=globalThis.fetch; let sourceOpens=0, attachmentHooks=0;
 const originalInvoiceAttachment = fakturoidGateway.getEmailAttachment;
 let fakturoidEnabled = false;
 let method="bank", status="open", allowed=false, currency="CZK", price=100, paid=0, deposit=0;
 let showQrInEmail: boolean | undefined;
 const occasion={id:3,organization:1,unit:2,title:"Podzimní ples",features:[]};
 const bank={account_number:"2000145399/0800",account_number_human_readable:"2000145399/0800",iban:"CZ6508000000192000145399",creditor_name:"Pořadatel plesu"};
 const details=()=>{
  const payment_info={payment_method:method,amount:price,deposit_amount:deposit,paid,returned:0,currency_code:currency,variable_symbol:12345,creditor_reference:'RF18539007547034',deadline:"2026-12-01T18:00:00Z",...bank,account_number:currency==='EUR'?bank.iban:bank.account_number,
   collectionAction:{method,purpose:"collect_payment",allowed},providerPayment:{method,status}};
  return {order:{id:4,order_symbol:"1A2C3E4F5G",price,currency_code:currency,data:{email:"current@example.invalid",tickets:[]},occasion,payment_info},
   occasion,payment_info,bank_account:{...bank,account_number:currency==='EUR'?bank.iban:bank.account_number},latest_history_id:9,order_changes:{version:1,hasChanges:false},form_data:{show_payment_qr_in_email:showQrInEmail},reference_history:[],reply_to:"poradatel@example.invalid"};
 };
 const rpc=async(name:string)=>{
  let data:unknown;
  if(name==="get_order_details_for_email")data={code:200,data:details()};
  else if(name==="generate_request_secret")data="test-secret";
  else if(name==="check_request_secret")data=true;
  else if(name==="is_demo_occasion")data=false;
  else if(name==="get_order_email_overview_source_v1")data=null;
  else if(name==="get_latest_order_history")data={price,currency_code:currency};
  else if(name==="get_external_services"){attachmentHooks++;data=fakturoidEnabled ? [{type:"FAKTUROID", data:{}}] : [];}
  else if(name==="get_email_template_and_wrapper")data={template:{id:1,subject:"{{occasionTitle}}",html:"<p>{{balanceReasoning}}</p>{{paymentAction}}{{fullOrder}}"},wrapper:{html:"<main>{{content}}{{paymentAction}}</main>"}};
  else throw Error("Unexpected SQL call: "+name);
  return {data,error:null};
 };
 supabaseAdmin.rpc=rpc as unknown as typeof supabaseAdmin.rpc;
 paymentRegistry.has=((id:unknown)=>typeof id==="string"&&["bank","cash","stripe","barion","orchard"].includes(id)) as typeof paymentRegistry.has;
 paymentRegistry.resolve=(id:unknown):PaymentMethodBinding=>{
  if(id==="bank"||id==="cash")return originalResolve.call(paymentRegistry,id);
  const connector={id:String(id),displayName:String(id)==="orchard"?"Orchard":"Gateway "+id};
  const hosted={connector,order:{readSource:async()=>({payment:{method,status},payBaseUrl:"https://tickets.example/pay"})},
   openSource:async()=>{sourceOpens++;return {payToken:"a".repeat(64)};},routes:{payPath:"/pay"},allowedOrigins:["https://tickets.example"]} as unknown as HostedPaymentDependencies;
  return {connector,hostedCheckout:hosted} as PaymentMethodBinding;
 };
 globalThis.fetch=()=>Promise.reject(Error("Unexpected external request"));
 try {
  for(method of ["bank","cash","stripe","barion","orchard","unknown"]) {
   for(status of ["open","paid","partially_refunded","refunded","disputed","expired","action_required"]) {
    allowed=false; paid=status==="paid"?100:0;
    const before=attachmentHooks;
    for(const kind of ["order_confirmation","order_update","order_payment_notice","order_storno"]) {
     const result=await renderQueuedEmail({message_id:"message",message_kind:kind,code:kind==="order_confirmation"?"TICKET_ORDER_CONFIRMATION":kind==="order_update"?"TICKET_ORDER_UPDATE":kind==="order_storno"?"TICKET_ORDER_STORNO":"TICKET_ORDER_PAYMENT_DONE",
      data:{lang:"cs",command_id:"command",ticket_order:{order:details().order}},recipient:"snapshot@example.invalid",organization:1,unit:2,occasion:3,order_id:4,lease_token:"lease",attempt_id:"attempt",prepared:null});
     assertEquals(result.prepared.to,"snapshot@example.invalid");
     assertEquals(result.prepared.attachments.length,0,method+"/"+status+"/"+kind);
     assert(!result.prepared.html.includes(bank.account_number),method+" must not leak stale bank data");
     assert(!result.prepared.html.includes("#pay="));
     if (method === "cash" && status === "paid" && kind === "order_payment_notice") {
      assertStringIncludes(result.prepared.html, "Objednávka je plně uhrazena.");
      assert(!result.prepared.html.includes("K úhradě na místě"));
     }
    }
    assertEquals(attachmentHooks,before,"disabled/non-bank paths never consult external attachment or invoice hooks");
   }
  }
  assertEquals(sourceOpens,0,"closed collection never opens a private pay token");
  for(method of ["stripe","barion","orchard"]) {
   status="open";allowed=true;price=100;paid=0;
   const result=await renderQueuedEmail({message_id:"message",message_kind:"order_confirmation",code:"TICKET_ORDER_CONFIRMATION",data:{lang:"cs",ticket_order:{order:details().order}},recipient:"snapshot@example.invalid",organization:1,unit:2,occasion:3,order_id:4,lease_token:"lease",attempt_id:"attempt",prepared:null});
   assertEquals((result.prepared.html.match(/#pay=/g)||[]).length,1,"one CTA across legacy balance, body and wrapper");
   assertStringIncludes(result.prepared.html,method==="orchard"?"Orchard":"Gateway "+method);
   assertEquals(result.prepared.attachments.length,0);
  }
  method="bank";status="open";allowed=true;price=100;paid=20;
  deposit=30;
  showQrInEmail=false;
  const optedOut = await renderQueuedEmail({message_id:"opt-out",message_kind:"order_confirmation",code:"TICKET_ORDER_CONFIRMATION",
    data:{lang:"cs",ticket_order:{order:details().order}},recipient:"snapshot@example.invalid",organization:1,unit:2,occasion:3,order_id:4,lease_token:"lease",attempt_id:"attempt",prepared:null});
  assertEquals(optedOut.prepared.attachments.map(part=>part.disposition),["ATTACHMENT"]);
  assert(!optedOut.prepared.html.includes("cid:festapp-payment-"));
  showQrInEmail=undefined;
  for(currency of ["CZK","EUR","USD"]) {
   const cases = [
     ["order_confirmation", "TICKET_ORDER_CONFIRMATION", deposit, false],
     ["order_update", "TICKET_ORDER_UPDATE", price - paid, false],
     ["order_payment_notice", "TICKET_ORDER_PAYMENT_DONE", price - paid, false],
     ["order_reminder", "TICKET_ORDER_REMINDER", price - paid, false],
     ["order_reminder", "TICKET_ORDER_REMINDER", price - paid, true],
   ] as const;
   for(const [kind,code,expectedAmount,isDepositReminder] of cases) {
    const result=await renderQueuedEmail({message_id:"message",message_kind:kind,code,data:{lang:"cs",is_deposit_reminder:isDepositReminder,ticket_order:{order:details().order}},recipient:"snapshot@example.invalid",organization:1,unit:2,occasion:3,order_id:4,lease_token:"lease",attempt_id:"attempt",prepared:null});
    const {html,attachments}=result.prepared;
    assertEquals(attachments.length,currency==="USD"?0:2,kind+"/"+currency);
    if (currency!=="USD") {
      const [download,inline]=attachments;
      assertEquals(download.disposition,"ATTACHMENT");
      assertEquals(inline.disposition,"INLINE");
      assertEquals(download.contentType,"image/png");
      const request = details();
      const expected = await generateQrCode(
        { ...request.payment_info, amount: expectedAmount },
        request.order,
        occasion.title,
      );
      assertEquals(download.content, encodeAttachment(expected, "binary"));
      assertEquals(inline.content,download.content);
      assert(inline.contentId);
      if (kind === "order_payment_notice") {
        assertStringIncludes(html.replace(/<[^>]*>/g, ""), currency === "EUR" ? "RF18539007547034" : "12345");
        assertStringIncludes(html, "IBAN");
      }
      assertEquals(html.split(`src="cid:${inline.contentId}"`).length,2);
      assert(html.indexOf(`cid:${inline.contentId}`)<html.indexOf("</main>"));
    } else {
      assert(!html.includes('src="cid:festapp-payment-'));
    }
    assert(!result.prepared.html.includes("#pay="));
   }
  }
  for(currency of ["CZK","EUR"]) {
   method="bank";status="open";allowed=false;price=0;paid=0;
   const rendered=await getTicketOrderConfirmationTemplate({data:{lang:"cs",ticket_order:{order:details().order}}});
   assertEquals(rendered.attachments.length,0);
   assert(!JSON.stringify(rendered.subs).includes(bank.account_number));
  }
  fakturoidEnabled = true;
  showQrInEmail = true;
  allowed = true;
  price = 100;
  deposit = 30;
  const originalInvoice = await PDFDocument.create();
  originalInvoice.setTitle("Original document");
  originalInvoice.addPage([400, 500]).drawText("First page");
  originalInvoice.addPage([500, 600]).drawText("Second page");
  await originalInvoice.attach(new Uint8Array([1, 2, 3]), "invoice.isdoc");
  const originalInvoiceBytes = await originalInvoice.save();
  for (const [invoiceCurrency, invoiceQrDisabled] of [
    ["EUR", true], ["CZK", true], ["EUR", false], ["CZK", false],
  ] as const) {
   currency = invoiceCurrency;
   fakturoidGateway.getEmailAttachment = async () => ({
    variableSymbol: "12345",
    invoiceQrDisabled,
    attachment: {
     filename: "proforma.pdf",
     content: originalInvoiceBytes,
     contentType: "application/pdf",
     encoding: "binary",
    },
   });
   const result = await renderQueuedEmail({
    message_id:"fakturoid",message_kind:"order_confirmation",code:"TICKET_ORDER_CONFIRMATION",
    data:{lang:"cs",command_id:"command",ticket_order:{order:details().order}},
    recipient:"snapshot@example.invalid",organization:1,unit:2,occasion:3,order_id:4,
    lease_token:"lease",attempt_id:"attempt",prepared:null,
   });
   assertEquals(result.prepared.attachments.map((part) => part.contentType),
    invoiceQrDisabled ? ["application/pdf", "image/png", "image/png"] : ["application/pdf"]);
   if (invoiceQrDisabled) {
    const {order, payment_info} = details();
    const expected = await generateQrCode(
     {...payment_info, amount: deposit}, order, occasion.title,
    );
    assertEquals(result.prepared.attachments[1].content, encodeAttachment(expected, "binary"));
    assertStringIncludes(result.prepared.html.replace(/<[^>]*>/g, ""),
     currency === "EUR" ? payment_info.creditor_reference : String(payment_info.variable_symbol));
    const bytes = Uint8Array.from(atob(result.prepared.attachments[0].content), (char) => char.charCodeAt(0));
    const combined = await PDFDocument.load(bytes);
    assertEquals(combined.getPageCount(), 3);
    assertEquals(combined.getTitle(), "Original document");
    assertEquals(combined.getPages().slice(0, 2).map((page) => page.getSize()), [
     {width: 400, height: 500}, {width: 500, height: 600},
    ]);
    const names = combined.catalog.lookup(PDFName.of("Names"), PDFDict);
    const embedded = names.lookup(PDFName.of("EmbeddedFiles"), PDFDict);
    const files = embedded.lookup(PDFName.of("Names"), PDFArray);
    assertEquals(files.lookup(0, PDFHexString).decodeText(), "invoice.isdoc");
    const appendixResources = combined.getPage(2).node.Resources();
    assertEquals(appendixResources?.lookup(PDFName.of("XObject"), PDFDict).keys().length, 1);
   } else {
    assertEquals(result.prepared.attachments[0].content, encodeAttachment(originalInvoiceBytes, "binary"));
   }
  }
  fakturoidGateway.getEmailAttachment = async () => ({
   variableSymbol: "12345", invoiceQrDisabled: true,
  });
  await assertRejects(
   () => getTicketOrderConfirmationTemplate({data:{lang:"cs",command_id:"command",ticket_order:{order:details().order}}}),
   Error, "FAKTUROID_INVOICE_PDF_NOT_READY",
  );
 } finally {
  supabaseAdmin.rpc=originalRpc;paymentRegistry.resolve=originalResolve;paymentRegistry.has=originalHas;globalThis.fetch=originalFetch;
  fakturoidGateway.getEmailAttachment = originalInvoiceAttachment;
 }
});
