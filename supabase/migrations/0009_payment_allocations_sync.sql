-- Advance allocation records use the existing business_records sync table and RLS.
-- No new public table or weaker policy is introduced.
COMMENT ON TABLE public.business_records IS
  'Versioned business sync records; entity_type payment_allocations stores immutable advance-to-invoice allocation payloads.';
