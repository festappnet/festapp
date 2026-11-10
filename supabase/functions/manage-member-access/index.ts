import { createMemberAccessHandler } from "./handler.ts";
import { memberAccessDependencies } from "./dependencies.ts";
Deno.serve(createMemberAccessHandler(memberAccessDependencies));
