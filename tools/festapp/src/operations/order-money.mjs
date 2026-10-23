import {z} from 'zod';
export const decimalAmount=z.string().max(40).regex(/^-?\d+(\.\d+)?$/);
export const currencyCode=z.string().regex(/^[A-Z]{3}$/);
export const orderAmountChangeSchema=z.strictObject({orderId:z.number().int().positive().max(Number.MAX_SAFE_INTEGER),beforeAmount:decimalAmount,afterAmount:decimalAmount,delta:decimalAmount,currencyCode,beforeState:z.string().min(1).max(64),afterState:z.string().min(1).max(64)});
