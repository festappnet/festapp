import { handleGoogleAuth } from "../_shared/googleAuthFlow.ts";
Deno.serve((request) => handleGoogleAuth("complete", request));
