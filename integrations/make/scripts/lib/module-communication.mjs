export function apiCallCommunication(origin) {
    return {
        url: origin + '/{{parameters.url}}',
        method: "{{ifempty(parameters.method, 'POST')}}",
        type: 'raw',
        followRedirect: false,
        followAllRedirect: false,
        headers: {
            'content-type': 'application/json',
            '{{...}}': "{{toCollection(parameters.headers, 'key', 'value')}}",
            host: new URL(origin).host,
            authorization: 'Bearer {{connection.accessToken}}',
        },
        qs: { '{{...}}': "{{toCollection(parameters.qs, 'key', 'value')}}" },
        body: "{{ifempty(parameters.body, '{}')}}",
        response: {
            valid: '{{if(statusCode >= 200, statusCode < 300, false)}}',
            output: { body: '{{body}}', headers: '{{headers}}', statusCode: '{{statusCode}}' },
        },
        log: { sanitize: ['request.body', 'request.headers.authorization', 'request.headers.Authorization'] },
    };
}

export function apiCallParameters(origin, example) {
    const pair = [{ name: 'key', label: 'Key', type: 'text' }, { name: 'value', label: 'Value', type: 'text' }];
    const headerName = {
        ...pair[0],
        required: true,
        validate: { pattern: "^(?!(?:[Hh][Oo][Ss][Tt]|[Aa][Uu][Tt][Hh][Oo][Rr][Ii][Zz][Aa][Tt][Ii][Oo][Nn])$)[!#$%&'*+.^_`|~0-9A-Za-z-]+$" },
        help: 'Enter a header name other than Host or Authorization.',
    };
    return [
        { name: 'url', label: 'URL', type: 'text', required: true,
            validate: { pattern: '^/(?!/)[^\\s\\\\#]*$' },
            help: 'Enter a path relative to ' + origin + ', for example ' + example + '.' },
        { name: 'method', label: 'Method', type: 'select', required: true, default: 'POST',
            options: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD', 'OPTIONS'].map(value => ({ label: value, value })),
            help: 'The documented read operations use POST.' },
        { name: 'headers', label: 'Headers', type: 'array', spec: [headerName, pair[1]],
            help: 'Additional request headers. Host and Authorization are supplied by Make.' },
        { name: 'qs', label: 'Query string', type: 'array', spec: pair },
        { name: 'body', label: 'Body', type: 'text', default: '{}',
            help: 'Enter the request body as JSON for an operation that accepts it.' },
    ];
}

// get_report_ws emits UTC timestamps with six fractional digits.
export const salesReportOutput =
    "{{if(body.data.report.generated_at, set(body.data, 'report.generated_at', parseDate(body.data.report.generated_at, 'YYYY-MM-DDTHH:mm:ss.SSSSSSZ')), body.data)}}";
