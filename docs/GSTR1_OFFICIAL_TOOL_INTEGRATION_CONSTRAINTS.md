# GSTR-1 official-tool integration constraints

This note records implementation constraints from GST Portal's published Returns Offline Tool user guide and known-issues guidance. It is not a substitute for downloading and validating against the current official tool/schema for the return period.

## Official references

- [GSTN Returns Offline Tool user guide (PDF)](https://tutorial.gst.gov.in/downloads/invoiceuploadofflineutility.pdf)
- [GST Portal known issues and suggested solutions (PDF)](https://tutorial.gst.gov.in/offlineutilities/gsterrorandresolution/gstissuesandsuggestedsolutions.pdf)
- [GST Portal GSTR-1 preparation guidance](https://tutorial.gst.gov.in/userguide/returns/Creation_of_Outward_Supplies_Return_in_GSTR-1.htm)

## Confirmed constraints from published GST Portal guidance

1. The Returns Offline Tool generates a JSON file with the `.json` extension for GSTR-1/IFF.
2. The published user guide states that an uploaded JSON file must not exceed 5 MB. For larger returns, the tool workflow permits multiple JSON files for the same tax period; the records must be divided and uploaded in multiple files.
3. GST Portal's known-issues guidance directs users facing JSON structure validation errors to the GST developer API portal, the GSTR1 “Save GSTR1 data” API request payload, and its downloadable schema. It specifically warns that required properties (the guide gives HSN UQC as an example) can cause upload rejection.
4. The schema/API version and offline-tool version are subject to change. A schema version mentioned in an older guide must not be hard-coded as the current version.

## Required implementation sequence before enabling direct JSON export

1. Obtain the current Returns Offline Tool from the GST Portal Downloads page for the target filing period and record the download date and displayed version.
2. Obtain the matching current GSTR-1 save-data request schema from the GST developer API portal; record the API/schema version and source.
3. Build a versioned DTO/serializer against that schema only. Keep internal accounting models separate from GSTN wire-format models.
4. Validate required fields, GSTIN/return period, document types and numbers, place of supply, tax components, HSN/UQC, amendment references, and section-specific rules before serialization.
5. Enforce the portal's published 5 MB JSON-file ceiling. If splitting is required, split only at complete transaction/document boundaries and make each output independently valid. Never silently truncate or omit transactions.
6. Add golden fixtures derived from sanitized official-tool examples and schema validation. Include boundary tests around file-size splitting, empty sections, decimal precision, duplicate document numbers, and unsupported categories.
7. Validate generated files in the current official offline tool and retain sanitized fixtures plus tool/schema version evidence.
8. Keep direct JSON export disabled or clearly marked experimental until all preceding checks pass and an independent GST practitioner has reviewed the supported sections.

## Current application status

The app's existing GSTR-1 CSV outputs are management/review reports, not GSTN JSON. The app does not yet have a verified direct GSTN JSON exporter. No live return filing-readiness claim is permitted based only on local tests or CSV generation.
