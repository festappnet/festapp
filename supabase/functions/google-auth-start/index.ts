import { handleGoogleAuth } from "../_shared/googleAuthFlow.ts";
Deno.serve((request) => handleGoogleAuth("start", request));
