-- Create generic function to update updated_at column if it exists
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Create trigger for bank_accounts
DROP TRIGGER IF EXISTS update_bank_accounts_updated_at ON eshop.bank_accounts;

CREATE TRIGGER update_bank_accounts_updated_at
BEFORE UPDATE ON eshop.bank_accounts
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column();
