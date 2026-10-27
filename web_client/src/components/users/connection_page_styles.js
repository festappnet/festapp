// The two first-party connection routes share the application's theme tokens.
export const connectionPageStyles = `
.connection-page{--connection-line:color-mix(in srgb,var(--text-color,#20242b) 18%,transparent);box-sizing:border-box;max-width:800px;margin:48px auto;padding:36px 40px;background:var(--card-bg,#fff);color:var(--text-color,#20242b);border:1px solid var(--connection-line);border-radius:16px;overflow-wrap:anywhere}
.connection-page *{box-sizing:border-box}
.connection-page h1{font-size:2rem;line-height:1.2;margin:0 0 20px;text-wrap:balance}
.connection-page h2{font-size:1.3rem;line-height:1.35;margin:0 0 12px}
.connection-page h3{font-size:1.05rem;line-height:1.4}
.connection-page p,.connection-page li{line-height:1.65}
.connection-page p{max-width:68ch;margin:12px 0}
.connection-page a{color:var(--link-color,#243858);text-decoration:underline;text-underline-offset:4px}
.connection-page button{font:inherit;font-weight:600;min-height:44px;padding:10px 18px;margin:8px 10px 8px 0;border:1px solid var(--connection-line);border-radius:8px;background:transparent;color:inherit;cursor:pointer;transition:background-color .15s ease}
.connection-page button:hover:not(:disabled){background:color-mix(in srgb,currentColor 7%,transparent)}
.connection-page button[data-primary]{background:#243858;border-color:#243858;color:#fff}
.connection-page button[data-primary]:hover:not(:disabled){background:#304b73}
.connection-page button:disabled{opacity:.5;cursor:default}
.connection-page :focus-visible{outline:3px solid var(--link-color,#243858);outline-offset:3px}
.connection-page ::selection{background:#b9d9f4;color:#17273f}
.connection-page [role=alert]{color:#a12424}
.connection-page [data-revoke],.connection-page [data-confirm-revoke]{color:#a12424;border-color:color-mix(in srgb,#a12424 45%,transparent)}
.connection-identity{font-weight:600;font-size:.95rem}
.connection-status{display:inline-block;font-size:.85rem;font-weight:600;margin:4px 12px 4px 0!important}
.connection-back{display:inline-block;margin:0 0 24px;font-size:.95rem}
body.dark-mode .connection-page [role=alert],body.dark-mode .connection-page [data-revoke],body.dark-mode .connection-page [data-confirm-revoke]{color:#ffb3b3}
body.dark-mode .connection-page button[data-primary]{background:#a6ccea;color:#17273f;border-color:#a6ccea}
body.dark-mode .connection-page button[data-primary]:hover:not(:disabled){background:#c0def4}
@media(max-width:600px){.connection-page{margin:16px 12px;padding:24px 20px;border-radius:12px}.connection-page h1{font-size:1.7rem}.connection-page button{max-width:100%;white-space:normal}}
@media(prefers-reduced-motion:reduce){.connection-page button{transition:none}}
`;
