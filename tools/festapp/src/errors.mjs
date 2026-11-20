export class OperationError extends Error {
    constructor(code, retryable = false) {
        super(code);
        this.code = code;
        this.retryable = retryable;
    }
}
export function check(value, code = 'UPSTREAM_CONTRACT_FAILURE') {
    if (!value) throw new OperationError(code);
}
const permissionMessages = new Map([
    ['INSUFFICIENT_SCOPE', 'This connection is missing the required OAuth permissions. Reconnect and explicitly approve the scopes required by this tool; your account must also have permission for the action.'],
    ['ORGANIZER_CONSENT_REQUIRED', 'This connection does not include access to the whole organizer. Reconnect and explicitly select that organizer, rather than only its events. The account must also have the required organizer role; consent alone does not grant that role.'],
    ['FORBIDDEN', 'The connected account or selected connection access does not permit this action. Check the selected event or organizer and ask its administrator to verify your account permissions. Retrying unchanged will not grant access.'],
]);
const operationPermissionMessages = new Map([
    ['units.appLanding.save', 'Changing the application home requires the live administrator role for the organization and whole-organizer consent. Organizer manager rights alone do not authorize this organization-wide setting.'],
    ['forms.save', 'Saving this form was denied. Your account needs form editor rights for this event or its organizer unit, and the form must belong to an event included in this connection. Ask the event organizer to verify your role and check the selected event and form. OAuth consent does not grant account permissions; reconnect only if the connection access or scopes need changing.'],
    ['units.settings.inspect', 'Reading organizer settings requires a live manager role for that organizer. Check the selected organizer and ask its administrator to verify the account role. Event or form editor rights and OAuth consent do not grant an organizer manager role.'],
    ['units.settings.save', 'Changing analytics or other organizer settings requires a live manager role for that organizer. Check the selected organizer and ask its administrator to verify the account role. Event or form editor rights and OAuth consent do not grant an organizer manager role.'],
    ['units.websiteConsent.inspect', 'Reading website consent bindings requires a live manager role for that organizer and whole-organizer consent. Event or form editor rights and OAuth consent do not grant an organizer manager role.'],
    ['units.websiteConsent.export', 'Exporting a website consent binding requires a live manager role for that organizer and whole-organizer consent. Event or form editor rights and OAuth consent do not grant an organizer manager role.'],
    ['units.measurementApproval.inspect', 'Reading the measurement approval requires organizer administration access or a manager role for that organizer and whole-organizer consent.'],
    ['units.measurementApproval.request', 'Requesting measurement approval requires a live manager role for that organizer and whole-organizer consent. Event or form editor rights and OAuth consent do not grant an organizer manager role.'],
    ['units.metaCapiApproval.inspect', 'Reading the Meta Conversions API approval requires organizer administration access or a manager role for that organizer and whole-organizer consent.'],
    ['units.metaCapiApproval.request', 'Requesting Meta Conversions API approval requires a live manager role for that organizer and whole-organizer consent. Event or form editor rights and OAuth consent do not grant an organizer manager role.'],
]);
// Domain outcomes whose remedy is not obvious from the code alone.
const outcomeMessages = new Map([
    ['APPROVAL_REQUEST_LIMITED', error => error.retryable
        ? `Approval request emails are temporarily limited. Nothing was sent; retry after ${error.retryAfter ?? 60} seconds.`
        : 'Approval request emails exceed a limit that waiting does not resolve. Nothing was sent; the platform operator must review the limit.'],
    ['APPROVAL_REQUEST_NO_RECIPIENT', () => 'No organization administrator has a deliverable email address. Nothing was sent and the request remains available; an administrator must verify the account email first.'],
    ['APPROVAL_REQUEST_REJECTED', () => 'The request was not sent: the saved organizer websites or the organization service address are invalid. Check the organizer websites; the platform operator owns the service address.'],
    ['WEBSITE_CONSENT_NOT_READY', () => 'Only a confirmed, ready website consent binding can be exported. Inspect the bindings; confirmation happens in organizer administration.'],
    ['WEBSITE_CONSENT_CHANGED_RELOAD_REQUIRED', () => 'The website consent binding changed. Inspect the bindings again and use the current version.'],
    ['WEBSITE_CONSENT_REJECTED', () => 'The website consent binding cannot be exported because the organization service address is not configured. The platform operator owns that address.'],
    ['CONSENT_EXPORT_REJECTED', () => 'consentExport must be a valid export for the selected organizer and service. Read the current export with festapp_units_website_consent_export and pass it unchanged.'],
    ['CONSENT_EXPORT_SERVICE_MISMATCH', () => 'consentExport names a different service address than this tenant web address. Reading it again returns the same address; the platform operator must align the organization service address with the tenant web address. The administration rejects the same export.'],
    ['EMBED_LABELS_UNAVAILABLE', () => 'This server build lacks the translated embed texts for the selected language. Choose another language or ask the platform operator to redeploy; other tools are unaffected.'],
    ['FORM_PUBLIC_LINK_REQUIRED', () => 'The form has no saved public link yet. Save the form with a public link before generating embed code.'],
]);
const approvalRequestInspection = new Map([
    ['units.measurementApproval.request', 'festapp_units_measurement_approval_inspect'],
    ['units.metaCapiApproval.request', 'festapp_units_meta_capi_approval_inspect'],
]);
export function safeError(error, { operation } = {}) {
    if (error instanceof OperationError && error.code === 'COMMITTED_READBACK_FAILED') {
        const { commandId, receiptId, occasionId, formId } = error.receipt;
        const target = formId ? ` Form ID ${formId} in occasion ${occasionId}.` : '';
        const recovery = operation === 'forms.delete' ? 'Check the form list in administration.'
            : formId ? 'Check the form in administration or inspect it by ID.'
            : 'Check the saved result in administration.';
        return { code: error.code, retryable: false,
            message: `Committed commandId=${commandId}, receiptId=${receiptId}. Result readback failed.${target} ${recovery} If you need the original result, retry only with the same commandId and identical payload.` };
    }
    const inspect = approvalRequestInspection.get(operation);
    const recovery = inspect && `The approval request outcome is uncertain. Check with ${inspect} and obtain fresh approval before sending a new request.`;
    if (error?.name === 'TimeoutError' || error?.name === 'AbortError')
        return { code: 'TIMEOUT', message: recovery || 'TIMEOUT', retryable: !recovery };
    const known = error instanceof OperationError;
    const message = error?.code === 'FORBIDDEN'
        ? operationPermissionMessages.get(operation) ?? permissionMessages.get(error.code)
        : permissionMessages.get(error?.code) ?? (known ? outcomeMessages.get(error.code)?.(error) : undefined) ?? error?.code;
    const retryable = known ? !permissionMessages.has(error.code) && error.retryable : true;
    // A lost response may hide a new round of email. Only an explicit queue
    // rejection establishes that the approval request transaction rolled back.
    if (retryable && recovery && error?.code !== 'APPROVAL_REQUEST_LIMITED')
        return { code: known ? error.code : 'UNAVAILABLE', message: recovery, retryable: false };
    return {
        code: known ? error.code : 'UNAVAILABLE',
        message: known ? message : 'Operation unavailable',
        retryable,
    };
}
export function upstream(error) {
    if (!error) return;
    const status = Number(error.status);
    throw new OperationError(
        status === 401 ||
            [
                'refresh_token_not_found',
                'refresh_token_already_used',
                'session_not_found',
                'invalid_credentials',
            ].includes(error.code)
            ? 'AUTHENTICATION_REQUIRED'
            : status === 403 || error.code === '42501'
              ? 'FORBIDDEN'
              : status === 404
                ? 'NOT_FOUND_OR_INACCESSIBLE'
                : status === 429
                  ? 'TEMPORARILY_LIMITED'
                  : 'UNAVAILABLE',
        status >= 500 || status === 429 || !status,
    );
}

// A network/relay/server failure may hide a committed command. All order and
// waitlist adapters preserve the original UUID, including invoice-pending replies.
export function commandEdgeResponse({data,error},commandId){
 const status=Number(error?.status??error?.context?.status);
 if(['40001','40P01'].includes(error?.code??data?.errorCode))throw new OperationError('TEMPORARY_CONCURRENCY_RETRY_SAME_COMMAND',true);
 if(error&&![401,403].includes(status)&&(['FunctionsFetchError','FunctionsRelayError'].includes(error.name)||[408,429].includes(status)||status>=500))
  throw new OperationError('TEMPORARY_FAILURE_RETRY_SAME_COMMAND',true);
 if(data?.errorCode==='42501')throw new OperationError('FORBIDDEN');
 if(error)upstream({...error,status:error.status??error.context?.status});
 if(data?.code===503&&data.committed){
  check(data.committed.mutation?.commandId===commandId&&data.committed.mutation?.receiptId===commandId);
  return data.committed;
 }
 if(Number(data?.code)>=500)throw new OperationError('TEMPORARY_FAILURE_RETRY_SAME_COMMAND',true);
 if(data?.code===410)throw new OperationError('COMMAND_EXPIRED_DO_NOT_REPLAY');
 return data;
}
