import { z } from 'zod';
import { webhookEnvelopeSchema, WEBHOOK_TYPES } from './webhook-protocol.mjs';
const entityId=z.number().int().positive().max(Number.MAX_SAFE_INTEGER);
const text=z.string().nullable();
const responses=z.array(z.record(z.string().regex(/^[1-9][0-9]*$/),z.json()));
const orderData=z.strictObject({
 orderId:entityId,occasionId:entityId,formId:entityId.nullable(),
 customer:z.strictObject({name:text,surname:text,email:text,phone:text}),
 responses,formFields:z.array(z.strictObject({id:entityId,title:text,type:text})),
 tickets:z.array(z.strictObject({id:entityId,responses})),
});
export const webhookEventSchemas=Object.freeze({
 [WEBHOOK_TYPES.orderCreated]:webhookEnvelopeSchema.safeExtend({type:z.literal(WEBHOOK_TYPES.orderCreated),data:orderData}),
 [WEBHOOK_TYPES.test]:webhookEnvelopeSchema.safeExtend({type:z.literal(WEBHOOK_TYPES.test),data:z.strictObject({test:z.literal(true),occasionId:entityId})}),
});
/** The SQL snapshot is validated against this allowlist immediately before
 * dispatch. Extra future SQL fields cannot silently become public disclosures. */
export function validateWebhookEvent(event,occasionId){
 const result=webhookEventSchemas[event?.type]?.parse(event);
 if(!result||result.data.occasionId!==occasionId||
   result.type===WEBHOOK_TYPES.orderCreated&&result.subject!==`orders/${result.data.orderId}`)
  throw new Error('INVALID_WEBHOOK_EVENT');
 return result;
}
