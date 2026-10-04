import { supabaseAdmin } from "../_shared/supabaseUtil.ts";
import { AuthError, authorizeRequest } from "../_shared/auth.ts";

const _PROJECT_URL = Deno.env.get("PROJECT_URL")!;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  // Set a maximum runtime limit in milliseconds (400 seconds).
  const maxDuration = 400 * 1000;
  const startTime = Date.now();

  try {
    // Handle CORS preflight request.
    if (req.method === "OPTIONS") {
      return new Response("ok", { headers: corsHeaders });
    }

    // Parse request body and authorize using the request secret.
    const requestData = await req.json();
    const { requestSecret } = requestData;
    await authorizeRequest({ requestSecret });

    const { data: bankAccounts, error: bankAccountsError } = await supabaseAdmin
      .rpc("get_fetchable_bank_accounts_with_t_count");
    if (bankAccountsError) {
      console.error(
        "Error retrieving fetchable bank accounts",
        bankAccountsError,
      );
      return new Response(
        JSON.stringify({ error: "Failed to retrieve fetchable bank accounts" }),
        {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
          status: 500,
        },
      );
    }

    if (!bankAccounts || bankAccounts.length === 0) {
      return new Response(
        JSON.stringify({ message: "No bank accounts available for fetching" }),
        {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
          status: 200,
        },
      );
    }

    // Filter accounts to process only those with type "FIO".
    const fioAccounts = bankAccounts.filter((account: any) =>
      account.account_type === "FIO"
    );
    if (fioAccounts.length === 0) {
      return new Response(
        JSON.stringify({
          message: "No FIO bank accounts available for fetching",
        }),
        {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
          status: 200,
        },
      );
    }

    // Process each FIO bank account one by one.
    const fetchResults = [];
    for (const account of fioAccounts) {
      const bankAccountId = account.bank_account_id;
      const bankSecret = account.bank_secret;
      const transactionCount = account.transaction_count_last_90_days;

      try {
        // If there are no recent transactions in our DB, set the Fio API pointer to 90 days ago.
        // This prevents downloading a large initial payload and instead prepares the 'last' endpoint to fetch from that date.
        if (transactionCount === 0) {
          const startDate = new Date();
          startDate.setDate(startDate.getDate() - 90);
          const formattedStartDate = startDate.toISOString().split("T")[0];

          const setDateUrl =
            `https://fioapi.fio.cz/v1/rest/set-last-date/${bankSecret}/${formattedStartDate}/`;
          const setDateResponse = await fetch(setDateUrl);
          if (!setDateResponse.ok) {
            // Log the error but proceed anyway, as the subsequent 'last' fetch might still work or provide a useful error.
            console.error(
              `Failed to set last date for account ${bankAccountId}. Status: ${setDateResponse.status}`,
            );
            fetchResults.push({
              bankAccountId,
              error:
                `Failed to set Fio API pointer with status: ${setDateResponse.status}`,
            });
          }
        }

        // Always fetch the latest transactions.
        // If the date was just set, this will get everything since that date.
        // If transactions already exist in our DB, this gets transactions since the last fetch.
        const apiUrl =
          `https://fioapi.fio.cz/v1/rest/last/${bankSecret}/transactions.json`;

        const apiResponse = await fetch(apiUrl);

        if (!apiResponse.ok) {
          console.error(
            `Fio API request failed for account ${bankAccountId} with status: ${apiResponse.status}`,
          );
          fetchResults.push({
            bankAccountId,
            error: `Fio API request failed with status: ${apiResponse.status}`,
          });
          continue; // Move to the next account
        }

        const transactionData = await apiResponse.json();
        const transactions =
          transactionData?.accountStatement?.transactionList?.transaction || [];

        if (transactions.length > 0) {
          // Insert transactions using the "insert_transactions" RPC.
          const { data: insertResult, error: insertError } = await supabaseAdmin
            .rpc("insert_transactions", {
              transactions,
              bank_account_id: bankAccountId,
            });
          if (insertError) {
            console.error(
              `Error inserting transactions for account ${bankAccountId}:`,
              insertError,
            );
            fetchResults.push({
              bankAccountId,
              error: "Failed to insert transactions",
            });
          } else {
            fetchResults.push({
              bankAccountId,
              message: "Transactions processed successfully",
              result: insertResult,
            });
          }
        } else {
          fetchResults.push({
            bankAccountId,
            message: "No new transactions to process",
          });
        }

        // Update the last fetch time for this bank account.
        const { error: updateError } = await supabaseAdmin.rpc(
          "set_last_fetch_time",
          { p_bank_account_id: bankAccountId },
        );
        if (updateError) {
          console.error(
            `Error updating last fetch time for account ${bankAccountId}:`,
            updateError,
          );
          // Note: This error is pushed in addition to any transaction processing results.
          fetchResults.push({
            bankAccountId,
            updateError: "Failed to update last fetch time",
          });
        }
      } catch (error) {
        console.error(
          `Unexpected error processing account ${bankAccountId}:`,
          error,
        );
        fetchResults.push({
          bankAccountId,
          error: "Unexpected error occurred",
        });
      }
    }

    const finalResults = { fetchResults };

    return new Response(
      JSON.stringify({
        message: "Operations completed",
        results: finalResults,
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 200,
      },
    );
  } catch (error) {
    // Handle both custom AuthError and any other unexpected errors.
    const isAuthError = error instanceof AuthError;
    const status = isAuthError ? error.status : 500;
    const message = error instanceof Error
      ? error.message
      : "Unexpected error occurred";

    console.error(`Error [${status}]: ${message}`, isAuthError ? "" : error);

    return new Response(JSON.stringify({ error: message }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: status,
    });
  }
});
