export type RegistrationCreationResult = {
  data: unknown;
  error: { message?: string } | null;
};

export type RegistrationEmail = {
  to: string;
  recipientUser: string;
  templateCode: "SIGN_IN_CODE";
  context: { organization: number };
  substitutions: {
    code: string;
    email: string;
    platformLinks: string;
    appName: string;
  };
  from: string;
};

type RegistrationInput = {
  creationResult: RegistrationCreationResult;
  userEmail: string;
  organizationId: number;
  appName: string;
  code: string;
  platformLinksHtml: string;
  defaultEmail?: string;
};

type RegistrationResponse = {
  body: Record<string, unknown>;
  status: number;
};

export async function finishRegistration(
  input: RegistrationInput,
  deliver: (message: RegistrationEmail) => Promise<unknown>,
): Promise<RegistrationResponse> {
  if (input.creationResult.error) {
    return { body: { error: "User creation failed" }, status: 500 };
  }

  const creation = input.creationResult.data;
  if (!creation || typeof creation !== "object" || Array.isArray(creation)) {
    return { body: { error: "Invalid user creation response" }, status: 500 };
  }

  const result = creation as Record<string, unknown>;
  if (result.code !== 200) {
    return {
      body: result,
      status: typeof result.code === "number" ? 200 : 500,
    };
  }

  if (typeof result.id !== "string") {
    return { body: { error: "Invalid created user identifier" }, status: 500 };
  }

  await deliver({
    to: input.userEmail,
    recipientUser: result.id,
    templateCode: "SIGN_IN_CODE",
    context: { organization: input.organizationId },
    substitutions: {
      code: input.code,
      email: input.userEmail,
      platformLinks: input.platformLinksHtml,
      appName: input.appName,
    },
    from: `${input.appName} | Festapp <${input.defaultEmail ?? ""}>`,
  });

  return {
    body: { email: input.userEmail, code: 200 },
    status: 200,
  };
}
